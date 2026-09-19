#include "model.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>
#include <nlohmann/json.hpp>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include <stb_image.h>

namespace model {

using nlohmann::json;

namespace {
struct AccessorInfo {
    int64_t bufferView = -1;
    int64_t byteOffset = 0;
    int componentType = 0;
    int64_t count = 0;
    int type = 0; // 0 scalar 1 vec2 2 vec3
};

// vertex stride helper
inline size_t vIdx(size_t i) { return i * 8; }
} // namespace

bool loadGLB(const std::string& path, Mesh& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        std::fprintf(stderr, "cannot open %s\n", path.c_str());
        return false;
    }
    std::vector<uint8_t> data((std::istreambuf_iterator<char>(f)),
                              std::istreambuf_iterator<char>());
    if (data.size() < 20)
        return false;
    const uint32_t magic = *(uint32_t*)&data[0];
    if (magic != 0x46546C67)
        return false;
    const uint8_t* jsonData = nullptr;
    const uint8_t* binData = nullptr;
    size_t jsonLen = 0, binLen = 0, total = *(uint32_t*)&data[8];
    size_t off = 12;
    while (off + 8 <= total && off + 8 <= data.size()) {
        const uint32_t len = *(uint32_t*)&data[off];
        const uint32_t type = *(uint32_t*)&data[off + 4];
        if (type == 0x4E4F534A) { jsonData = &data[off + 8]; jsonLen = len; }
        else if (type == 0x004E4942) { binData = &data[off + 8]; binLen = len; }
        off += 8 + len;
    }
    if (!jsonData)
        return false;
    json g;
    try { g = json::parse(jsonData, jsonData + jsonLen); }
    catch (...) { std::fprintf(stderr, "glb JSON parse failed\n"); return false; }

    auto readAccessor = [&](int idx, AccessorInfo& a) {
        if (!g.contains("accessors") || idx >= (int)g["accessors"].size())
            return false;
        const auto& j = g["accessors"][idx];
        a.bufferView = j.value("bufferView", -1);
        a.byteOffset = j.value("byteOffset", 0);
        a.componentType = j.value("componentType", 0);
        a.count = j.value("count", 0);
        const std::string t = j.value("type", "SCALAR");
        a.type = t == "VEC3" ? 2 : (t == "VEC2" ? 1 : 0);
        return true;
    };
    auto slice = [&](const AccessorInfo& a, size_t size) -> const uint8_t* {
        const auto& bv = g["bufferViews"][a.bufferView];
        const int64_t base = bv.value("byteOffset", 0);
        const int64_t absOff = base + a.byteOffset;
        if (binData && absOff >= 0 && absOff + (int64_t)size <= (int64_t)binLen)
            return binData + absOff;
        return nullptr;
    };
    auto primTextured = [&](int matIdx) -> bool {
        if (!g.contains("materials") || matIdx < 0 ||
            matIdx >= (int)g["materials"].size())
            return false;
        const auto& pr = g["materials"][matIdx]
                             .value("pbrMetallicRoughness", json::object());
        return pr.contains("baseColorTexture");
    };

    // ---- phase 1: measure textured primitives, drop huge "scene"
    // objects so only house-sized parts are kept -----------------
    struct Cand { size_t mesh, prim; float diag; };
    std::vector<Cand> cands;
    {
        float minDiag = 1e30f;
        size_t texturedTotal = 0;
        size_t mi = 0;
        for (const auto& m : g["meshes"]) {
            size_t pi = 0;
            for (const auto& pr : m.value("primitives", json::array())) {
                const int matIdx = pr.value("material", -1);
                if (primTextured(matIdx)) {
                    ++texturedTotal;
                    const auto& attrs = pr["attributes"];
                    if (attrs.contains("POSITION")) {
                        AccessorInfo ap;
                        readAccessor(attrs["POSITION"], ap);
                        const uint8_t* pp = slice(ap, (size_t)ap.count * 12);
                        if (pp) {
                            glm::vec3 mn(1e30f), mx(-1e30f);
                            for (int64_t i = 0; i < ap.count; ++i) {
                                const float* v = (const float*)(pp + i * 12);
                                mn = glm::min(mn, glm::vec3(v[0], v[1], v[2]));
                                mx = glm::max(mx, glm::vec3(v[0], v[1], v[2]));
                            }
                            const float diag = glm::length(mx - mn);
                            minDiag = std::min(minDiag, diag);
                            cands.push_back({mi, pi, diag});
                        }
                    }
                }
                ++pi;
            }
            ++mi;
        }
        const float cutoff = std::max(8.0f, minDiag * 1.6f);
        std::vector<Cand> keep;
        for (auto& c : cands)
            if (c.diag <= cutoff)
                keep.push_back(c);
        cands = std::move(keep);
        std::printf("  house-sized primitives kept: %zu (of %zu textured)\n",
                    cands.size(), texturedTotal);
    }

    std::vector<float> pos, nrm, uv;
    std::vector<uint32_t> idx;
    size_t acceptedPrims = 0;
    size_t miIdx = 0;
    for (const auto& m : g["meshes"]) {
        size_t primOrd = 0;
        for (const auto& pr : m.value("primitives", json::array())) {
            const bool keep = std::any_of(
                cands.begin(), cands.end(),
                [&](const Cand& c) { return c.mesh == miIdx && c.prim == primOrd; });
            ++primOrd;
            if (!keep)
                continue;

            const auto& attrs = pr["attributes"];
            const int64_t baseIdx = (int64_t)pos.size() / 3;

            AccessorInfo ap, an, at, ai;
            if (!readAccessor(attrs["POSITION"], ap))
                continue;
            const uint8_t* pp = slice(ap, (size_t)ap.count * 12);
            if (!pp)
                continue;
            for (int64_t i = 0; i < ap.count; ++i) {
                const float* v = (const float*)(pp + i * 12);
                pos.push_back(v[0]); pos.push_back(v[1]); pos.push_back(v[2]);
            }
            if (attrs.contains("NORMAL")) {
                readAccessor(attrs["NORMAL"], an);
                const uint8_t* pn = slice(an, (size_t)an.count * 12);
                if (pn)
                    for (int64_t i = 0; i < an.count; ++i) {
                        const float* v = (const float*)(pn + i * 12);
                        nrm.push_back(v[0]); nrm.push_back(v[1]); nrm.push_back(v[2]);
                    }
            }
            if (attrs.contains("TEXCOORD_0")) {
                readAccessor(attrs["TEXCOORD_0"], at);
                const uint8_t* pt = slice(at, (size_t)at.count * 8);
                // glTF coordinates already address the image rows in their
                // stored order. Flipping them by default mirrors Blender's
                // baked texture vertically. Keep an opt-in override only
                // for debugging non-conforming assets.
                const char* uvf = std::getenv("UV_FLIP");
                const bool flip = uvf && uvf[0] == '1';
                if (pt)
                    for (int64_t i = 0; i < at.count; ++i) {
                        const float* v = (const float*)(pt + i * 8);
                        uv.push_back(v[0]);
                        uv.push_back(flip ? 1.0f - v[1] : v[1]);
                    }
            }

            if (pr.contains("indices")) {
                readAccessor(pr["indices"], ai);
                if (ai.componentType == 5125) {
                    const uint8_t* pi = slice(ai, (size_t)ai.count * 4);
                    if (!pi) continue;
                    for (int64_t i = 0; i < ai.count; ++i)
                        idx.push_back(*(const uint32_t*)(pi + i * 4) + (uint32_t)baseIdx);
                } else if (ai.componentType == 5123) {
                    const uint8_t* pi = slice(ai, (size_t)ai.count * 2);
                    if (!pi) continue;
                    for (int64_t i = 0; i < ai.count; ++i)
                        idx.push_back(*(const uint16_t*)(pi + i * 2) + (uint32_t)baseIdx);
                }
            } else {
                for (int64_t i = 0; i < ap.count; ++i)
                    idx.push_back((uint32_t)(baseIdx + i));
            }
            ++acceptedPrims;
        }
        ++miIdx;
    }
    if (acceptedPrims == 0) {
        std::fprintf(stderr, "glb: no house-sized textured primitive\n");
        return false;
    }
    const size_t vertsN = pos.size() / 3;
    if (nrm.size() != vertsN * 3)
        nrm.assign(vertsN * 3, 0.0f);
    if (uv.size() != vertsN * 2)
        uv.assign(vertsN * 2, 0.0f);

    out.verts.clear();
    out.verts.reserve(vertsN * 8);
    for (size_t i = 0; i < vertsN; ++i) {
        const float* p = &pos[i * 3];
        const float* n = &nrm[i * 3];
        const float* t = &uv[i * 2];
        out.verts.insert(out.verts.end(),
                         {p[0], p[1], p[2], n[0], n[1], n[2], t[0], t[1]});
    }
    out.indices = std::move(idx);
    if (!out.indices.empty()) {
        out.bmin = glm::vec3(1e30f);
        out.bmax = glm::vec3(-1e30f);
        for (uint32_t v : out.indices) {
            const float* p = &out.verts[vIdx(v)];
            out.bmin = glm::min(out.bmin, glm::vec3(p[0], p[1], p[2]));
            out.bmax = glm::max(out.bmax, glm::vec3(p[0], p[1], p[2]));
        }
    }

    // texture: read the first embedded image
    out.textured = false;
    if (g.contains("images") && !g["images"].empty() &&
        g["images"][0].contains("bufferView")) {
        const int imgBV = g["images"][0]["bufferView"];
        const auto& bv = g["bufferViews"][imgBV];
        const int64_t b0 = bv.value("byteOffset", 0);
        const int64_t bl = bv.value("byteLength", 0);
        if (binData && b0 >= 0 && b0 + bl <= (int64_t)binLen) {
            out.texture.assign(binData + b0, binData + b0 + bl);
            out.textured = true;
        }
    }
    // base colour factor (tint) of the first textured material
    for (const auto& m : g["materials"]) {
        const auto& pr = m.value("pbrMetallicRoughness", json::object());
        if (pr.contains("baseColorTexture") &&
            pr.contains("baseColorFactor")) {
            const auto& f = pr["baseColorFactor"];
            if (f.size() >= 3) {
                out.tint = glm::vec4(f[0].get<float>(), f[1].get<float>(),
                                     f[2].get<float>(),
                                     f.size() > 3 ? f[3].get<float>() : 1.0f);
            }
        }
        if (pr.contains("baseColorTexture"))
            break;
    }

    std::printf("GLB %s: %zu tris, %zu verts, bbox %.1f..%.1f | %.1f..%.1f | "
                "%.1f..%.1f, textured=%d tex=%zu B\n",
                path.c_str(), out.indices.size() / 3, vertsN, out.bmin.x,
                out.bmax.x, out.bmin.y, out.bmax.y, out.bmin.z, out.bmax.z,
                out.textured, out.texture.size());
    return !out.empty();
}

bool decodeTexture(const std::vector<uint8_t>& png, int& w, int& h,
                   std::vector<uint8_t>& rgba) {
    int c = 0;
    unsigned char* px = stbi_load_from_memory(
        png.data(), (int)png.size(), &w, &h, &c, 4);
    if (!px)
        return false;
    rgba.assign(px, px + (size_t)w * h * 4);
    stbi_image_free(px);
    return true;
}

// ------------------------------------------------------------
// fragmentation: k-means spatial clustering of triangles
// ------------------------------------------------------------

void splitIntoParts(const Mesh& mesh, int n, std::vector<Part>& out,
                    std::vector<uint32_t>* reordered) {
    out.clear();
    if (reordered)
        reordered->clear();
    const size_t triCount = mesh.indices.size() / 3;
    if (triCount == 0 || n < 1)
        return;
    n = std::min(n, (int)triCount);

    std::vector<glm::vec3> cent(triCount);
    for (size_t t = 0; t < triCount; ++t) {
        const uint32_t a = mesh.indices[t * 3];
        const uint32_t b = mesh.indices[t * 3 + 1];
        const uint32_t c = mesh.indices[t * 3 + 2];
        const float* pa = &mesh.verts[vIdx(a)];
        const float* pb = &mesh.verts[vIdx(b)];
        const float* pc = &mesh.verts[vIdx(c)];
        cent[t] = (glm::vec3(pa[0], pa[1], pa[2]) +
                   glm::vec3(pb[0], pb[1], pb[2]) +
                   glm::vec3(pc[0], pc[1], pc[2])) /
                  3.0f;
    }

    std::vector<glm::vec3> seeds(n);
    {
        const int g = (int)std::ceil(std::cbrt((double)n));
        int gi = 0;
        for (int i = 0; i < g && gi < n; ++i)
            for (int j = 0; j < g && gi < n; ++j)
                for (int k = 0; k < g && gi < n; ++k) {
                    const float fx = (i + 0.5f) / g;
                    const float fy = (j + 0.5f) / g;
                    const float fz = (k + 0.5f) / g;
                    seeds[gi++] =
                        mesh.bmin +
                        glm::vec3(mesh.bmax - mesh.bmin) *
                            glm::vec3(fx, fy, fz);
                }
        for (; gi < n; ++gi)
            seeds[gi] = seeds[gi % 8];
    }

    std::vector<int> assign(triCount);
    for (int iter = 0; iter < 9; ++iter) {
        for (size_t t = 0; t < triCount; ++t) {
            int best = 0;
            float bestD = 1e30f;
            for (int s = 0; s < n; ++s) {
                const float dx = cent[t].x - seeds[s].x;
                const float dy = cent[t].y - seeds[s].y;
                const float dz = cent[t].z - seeds[s].z;
                const float d = dx * dx + dy * dy + dz * dz;
                if (d < bestD) {
                    bestD = d;
                    best = s;
                }
            }
            assign[t] = best;
        }
        std::vector<glm::vec3> sum(n, glm::vec3(0));
        std::vector<int> cnt(n, 0);
        for (size_t t = 0; t < triCount; ++t) {
            sum[assign[t]] += cent[t];
            ++cnt[assign[t]];
        }
        for (int s = 0; s < n; ++s)
            if (cnt[s] > 0)
                seeds[s] = sum[s] / (float)cnt[s];
    }

    struct TriBucket {
        uint32_t idx[3];
        glm::vec3 c;
    };
    std::vector<std::vector<TriBucket>> buckets(n);
    for (size_t t = 0; t < triCount; ++t) {
        TriBucket tb = {mesh.indices[t * 3], mesh.indices[t * 3 + 1],
                        mesh.indices[t * 3 + 2], cent[t]};
        buckets[assign[t]].push_back(tb);
    }
    std::vector<uint32_t> ordered;
    ordered.reserve(mesh.indices.size());
    for (int s = 0; s < n; ++s) {
        if (buckets[s].empty())
            continue;
        Part p;
        p.indexBegin = (uint32_t)ordered.size();
        p.indexCount = (uint32_t)(buckets[s].size() * 3);
        p.pmin = glm::vec3(1e30f);
        p.pmax = glm::vec3(-1e30f);
        glm::vec3 csum(0);
        for (auto& tb : buckets[s]) {
            ordered.push_back(tb.idx[0]);
            ordered.push_back(tb.idx[1]);
            ordered.push_back(tb.idx[2]);
            p.pmin = glm::min(p.pmin, tb.c);
            p.pmax = glm::max(p.pmax, tb.c);
            csum += tb.c;
        }
        p.centroid = csum / (float)buckets[s].size();
        out.push_back(p);
    }
    if (reordered)
        *reordered = std::move(ordered);
}

} // namespace model

namespace model {

// ============================================================
// SCENE LOADER (hierarchical nodes + textures + transforms)
// ============================================================

namespace {

ObjTag tagOfName(const std::string& name) {
    std::string n;
    for (char c : name)
        n.push_back((char)std::tolower((unsigned char)c));
    auto has = [&](const char* key) { return n.find(key) != std::string::npos; };
    if (has("lant") || has("senila") || has("track"))
        return TAG_TRACK;
    if (has("turla") || has("tureta") || has("turret") || has("turela"))
        return TAG_TURRET;
    if (has("teva") || has("tun") || has("barrel") || has("gun") ||
        has("canon") || has("tanc") || has("cannon"))
        return TAG_BARREL;
    return TAG_HULL;
}

glm::mat4 composeTRS(const glm::vec3& t, const glm::quat& r,
                     const glm::vec3& s) {
    glm::mat4 m = glm::mat4_cast(r);
    m[0] *= s.x;
    m[1] *= s.y;
    m[2] *= s.z;
    m[3] = glm::vec4(t, 1.0f);
    return m;
}

} // namespace

bool loadGLBScene(const std::string& path, Scene& out, const char* rootHint) {
    out = Scene{};
    std::ifstream f(path, std::ios::binary);
    if (!f)
        return false;
    std::vector<uint8_t> data((std::istreambuf_iterator<char>(f)),
                              std::istreambuf_iterator<char>());
    if (data.size() < 20)
        return false;
    const uint8_t* jsonData = nullptr;
    const uint8_t* binData = nullptr;
    size_t jsonLen = 0, binLen = 0;
    const uint32_t total = *(uint32_t*)&data[8];
    size_t off = 12;
    while (off + 8 <= total && off + 8 <= data.size()) {
        const uint32_t len = *(uint32_t*)&data[off];
        const uint32_t type = *(uint32_t*)&data[off + 4];
        if (type == 0x4E4F534A) { jsonData = &data[off + 8]; jsonLen = len; }
        else if (type == 0x004E4942) { binData = &data[off + 8]; binLen = len; }
        off += 8 + len;
    }
    if (!jsonData)
        return false;
    json g;
    try { g = json::parse(jsonData, jsonData + jsonLen); }
    catch (...) { return false; }
    // ---- images / textures ----
    const auto& imgs = g.value("images", json::array());
    const auto& texs = g.value("textures", json::array());
    std::vector<int> texToImage(texs.size(), -1);
    for (size_t i = 0; i < texs.size(); ++i) {
        if (texs[i].contains("source"))
            texToImage[i] = texs[i]["source"];
    }
    std::vector<int> imageInScene(imgs.size(), -1);
    for (size_t i = 0; i < imgs.size(); ++i) {
        const auto& im = imgs[i];
        if (!im.contains("bufferView"))
            continue;
        const int bvid = im["bufferView"];
        const auto& bv = g["bufferViews"][bvid];
        const int64_t b0 = bv.value("byteOffset", 0);
        const int64_t bl = bv.value("byteLength", 0);
        if (!binData || b0 < 0 || b0 + bl > (int64_t)binLen) { std::fprintf(stderr, "  skip\n"); continue; }
        SceneImage si;
        if (decodeTexture(std::vector<uint8_t>(binData + b0, binData + b0 + bl),
                          si.w, si.h, si.rgba))
            si.ok = true;
        imageInScene[i] = (int)out.images.size();
        out.images.push_back(std::move(si));
    }

    // ---- materials -> image ----
    std::vector<int> matToImage;
    std::vector<glm::vec4> matTint;
    for (const auto& m : g.value("materials", json::array())) {
        int img = -1;
        glm::vec4 tint(1, 1, 1, 1);
        const auto& pr = m.value("pbrMetallicRoughness", json::object());
        if (pr.contains("baseColorTexture")) {
            const int t = pr["baseColorTexture"].value("index", -1);
            if (t >= 0 && t < (int)texToImage.size() &&
                texToImage[t] >= 0 && imageInScene[texToImage[t]] >= 0)
                img = imageInScene[texToImage[t]];
        }
        if (pr.contains("baseColorFactor")) {
            const auto& fc = pr["baseColorFactor"];
            if (fc.size() >= 3)
                tint = glm::vec4(fc[0].get<float>(), fc[1].get<float>(),
                                 fc[2].get<float>(),
                                 fc.size() > 3 ? fc[3].get<float>() : 1.0f);
        }
        matToImage.push_back(img);
        matTint.push_back(tint);
    }
    // ---- geometries ----
    const auto& meshes = g.value("meshes", json::array());
    // A glTF mesh can contain many primitives, each with its own accessor and
    // material. Keep them separate so no indices, vertices, or textures are
    // lost when exporting a joined Blender object.
    std::vector<std::vector<int>> meshToScene(meshes.size());

    struct AccView {
        const uint8_t* ptr = nullptr;
        size_t stride = 0;
        int componentType = 0;
        int components = 0;
        int64_t count = 0;
        bool normalized = false;
    };
    auto componentBytes = [](int type) -> size_t {
        switch (type) {
        case 5120:
        case 5121: return 1;
        case 5122:
        case 5123: return 2;
        case 5125:
        case 5126: return 4;
        default: return 0;
        }
    };
    auto componentCount = [](const std::string& type) {
        if (type == "VEC2") return 2;
        if (type == "VEC3") return 3;
        if (type == "VEC4") return 4;
        if (type == "MAT4") return 16;
        return 1;
    };
    auto readAcc = [&](int idx, AccView& av) -> bool {
        av = AccView{};
        const auto& accessors = g.value("accessors", json::array());
        const auto& views = g.value("bufferViews", json::array());
        if (idx < 0 || idx >= (int)accessors.size())
            return false;
        const auto& a = accessors[idx];
        const int bvId = a.value("bufferView", -1);
        if (bvId < 0 || bvId >= (int)views.size() || !binData)
            return false;
        const auto& bv = views[bvId];
        av.componentType = a.value("componentType", 0);
        av.components = componentCount(a.value("type", "SCALAR"));
        av.count = a.value("count", 0);
        av.normalized = a.value("normalized", false);
        const size_t cb = componentBytes(av.componentType);
        if (!cb || av.components <= 0 || av.count <= 0)
            return false;
        const int64_t base = bv.value("byteOffset", 0) +
                             a.value("byteOffset", 0);
        av.stride = (size_t)bv.value(
            "byteStride", (int64_t)(cb * (size_t)av.components));
        const int64_t last = base +
            (av.count - 1) * (int64_t)av.stride +
            (int64_t)(cb * (size_t)av.components);
        if (base < 0 || last > (int64_t)binLen)
            return false;
        av.ptr = binData + base;
        return true;
    };
    auto readComponent = [&](const AccView& av, int64_t i, int c) -> float {
        const size_t cb = componentBytes(av.componentType);
        const uint8_t* p = av.ptr + (size_t)i * av.stride + (size_t)c * cb;
        switch (av.componentType) {
        case 5126: {
            float v = 0;
            std::memcpy(&v, p, sizeof(v));
            return v;
        }
        case 5125: {
            uint32_t v = 0;
            std::memcpy(&v, p, sizeof(v));
            return av.normalized ? (float)((double)v / 4294967295.0)
                                 : (float)v;
        }
        case 5123: {
            uint16_t v = 0;
            std::memcpy(&v, p, sizeof(v));
            return av.normalized ? (float)v / 65535.0f : (float)v;
        }
        case 5122: {
            int16_t v = 0;
            std::memcpy(&v, p, sizeof(v));
            return av.normalized ? std::max(-1.0f, (float)v / 32767.0f)
                                 : (float)v;
        }
        case 5121:
            return av.normalized ? (float)*p / 255.0f : (float)*p;
        case 5120: {
            const int8_t v = *(const int8_t*)p;
            return av.normalized ? std::max(-1.0f, (float)v / 127.0f)
                                 : (float)v;
        }
        default: return 0.0f;
        }
    };
    auto readIndex = [&](const AccView& av, int64_t i) -> uint32_t {
        const uint8_t* p = av.ptr + (size_t)i * av.stride;
        if (av.componentType == 5125) {
            uint32_t v = 0;
            std::memcpy(&v, p, sizeof(v));
            return v;
        }
        if (av.componentType == 5123) {
            uint16_t v = 0;
            std::memcpy(&v, p, sizeof(v));
            return v;
        }
        return *p;
    };

    for (int mi = 0; mi < (int)meshes.size(); ++mi) {
        for (const auto& pr : meshes[mi].value("primitives", json::array())) {
            if (pr.value("mode", 4) != 4 || !pr.contains("attributes"))
                continue;
            const auto& attrs = pr["attributes"];
            if (!attrs.contains("POSITION"))
                continue;

            AccView pos, nrm, uv;
            if (!readAcc(attrs["POSITION"].get<int>(), pos) ||
                pos.components < 3)
                continue;
            const bool haveNrm = attrs.contains("NORMAL") &&
                readAcc(attrs["NORMAL"].get<int>(), nrm) &&
                nrm.components >= 3 && nrm.count == pos.count;
            const bool haveUv = attrs.contains("TEXCOORD_0") &&
                readAcc(attrs["TEXCOORD_0"].get<int>(), uv) &&
                uv.components >= 2 && uv.count == pos.count;

            AccView jnt, wgt;
            const bool skinned =
                attrs.contains("JOINTS_0") && attrs.contains("WEIGHTS_0") &&
                readAcc(attrs["JOINTS_0"].get<int>(), jnt) &&
                readAcc(attrs["WEIGHTS_0"].get<int>(), wgt) &&
                jnt.components >= 4 && wgt.components >= 4 &&
                jnt.count == pos.count && wgt.count == pos.count;

            SceneGeom gg;
            gg.skinned = skinned;
            if (skinned) {
                gg.joints.resize((size_t)pos.count * 4);
                gg.weights.resize((size_t)pos.count * 4);
                for (int64_t i = 0; i < pos.count; ++i)
                    for (int c = 0; c < 4; ++c) {
                        gg.joints[(size_t)i * 4 + c] =
                            (uint8_t)std::clamp(
                                (int)readComponent(jnt, i, c), 0, 255);
                        gg.weights[(size_t)i * 4 + c] =
                            std::max(0.0f, readComponent(wgt, i, c));
                    }
            }
            gg.verts.reserve((size_t)pos.count * 8);
            gg.bmin = glm::vec3(1e30f);
            gg.bmax = glm::vec3(-1e30f);
            for (int64_t i = 0; i < pos.count; ++i) {
                const glm::vec3 p(readComponent(pos, i, 0),
                                  readComponent(pos, i, 1),
                                  readComponent(pos, i, 2));
                const glm::vec3 n = haveNrm
                    ? glm::vec3(readComponent(nrm, i, 0),
                                readComponent(nrm, i, 1),
                                readComponent(nrm, i, 2))
                    : glm::vec3(0, 1, 0);
                // glTF UVs already address the image rows in their stored
                // order; flipping them mirrors baked textures vertically.
                // UV_FLIP=1 remains available for non-conforming assets.
                const char* uvf = std::getenv("UV_FLIP");
                const bool uvFlip = uvf && uvf[0] == '1';
                const glm::vec2 t = haveUv
                    ? glm::vec2(readComponent(uv, i, 0),
                                uvFlip ? 1.0f - readComponent(uv, i, 1)
                                       : readComponent(uv, i, 1))
                    : glm::vec2(0);
                gg.verts.insert(gg.verts.end(),
                                {p.x, p.y, p.z, n.x, n.y, n.z, t.x, t.y});
                gg.bmin = glm::min(gg.bmin, p);
                gg.bmax = glm::max(gg.bmax, p);
            }

            if (pr.contains("indices")) {
                AccView ind;
                if (!readAcc(pr["indices"].get<int>(), ind) ||
                    ind.components != 1 ||
                    (ind.componentType != 5121 &&
                     ind.componentType != 5123 &&
                     ind.componentType != 5125))
                    continue;
                gg.indices.reserve((size_t)ind.count);
                bool valid = true;
                for (int64_t i = 0; i < ind.count; ++i) {
                    const uint32_t v = readIndex(ind, i);
                    if (v >= (uint32_t)pos.count) {
                        valid = false;
                        break;
                    }
                    gg.indices.push_back(v);
                }
                if (!valid)
                    continue;
            } else {
                gg.indices.reserve((size_t)pos.count);
                for (int64_t i = 0; i < pos.count; ++i)
                    gg.indices.push_back((uint32_t)i);
            }
            if (gg.indices.empty())
                continue;

            const int material = pr.value("material", -1);
            if (material >= 0 && material < (int)matToImage.size()) {
                gg.texImage = matToImage[material];
                gg.tint = matTint[material];
            }
            meshToScene[mi].push_back((int)out.geoms.size());
            out.geoms.push_back(std::move(gg));
        }
    }
    // ---- skins (joints + inverse bind matrices) ----
    for (const auto& sk : g.value("skins", json::array())) {
        Skin skin;
        for (const auto& j : sk.value("joints", json::array()))
            skin.joints.push_back(j.get<int>());
        if (sk.contains("inverseBindMatrices")) {
            AccView ibm;
            if (readAcc(sk["inverseBindMatrices"].get<int>(), ibm) &&
                ibm.components == 16) {
                skin.inverseBind.resize((size_t)ibm.count, glm::mat4(1.0f));
                for (int64_t i = 0; i < ibm.count; ++i)
                    for (int col = 0; col < 4; ++col)
                        for (int row = 0; row < 4; ++row)
                            skin.inverseBind[(size_t)i][col][row] =
                                readComponent(ibm, i, col * 4 + row);
            }
        }
        out.skins.push_back(std::move(skin));
    }

    // ---- animations (baked clips, e.g. Idle/Walk/Run) ----
    for (const auto& an : g.value("animations", json::array())) {
        Animation anim;
        anim.name = an.value("name", "");
        for (const auto& s : an.value("samplers", json::array())) {
            if (!s.contains("input") || !s.contains("output"))
                continue;
            AccView in, outp;
            if (!readAcc(s["input"].get<int>(), in) || in.components != 1)
                continue;
            if (!readAcc(s["output"].get<int>(), outp) || outp.count <= 0)
                continue;
            AnimSampler as;
            as.step = s.value("interpolation", "LINEAR") == "STEP";
            as.times.resize((size_t)in.count);
            for (int64_t i = 0; i < in.count; ++i)
                as.times[(size_t)i] = readComponent(in, i, 0);
            const int comps = std::min(4, outp.components);
            as.values.assign((size_t)outp.count, glm::vec4(0.0f));
            for (int64_t i = 0; i < outp.count; ++i)
                for (int c = 0; c < comps; ++c)
                    as.values[(size_t)i][c] = readComponent(outp, i, c);
            if (as.times.empty() || as.values.empty())
                continue;
            anim.duration = std::max(anim.duration, as.times.back());
            anim.samplers.push_back(std::move(as));
        }
        for (const auto& ch : an.value("channels", json::array())) {
            if (!ch.contains("target") || !ch.contains("sampler"))
                continue;
            AnimChannel c;
            c.node = ch["target"].value("node", -1);
            const std::string p = ch["target"].value("path", "");
            c.path = p == "translation" ? 0
                     : p == "rotation"  ? 1
                     : p == "scale"     ? 2
                                        : -1;
            c.sampler = ch.value("sampler", -1);
            if (c.node < 0 || c.path < 0 || c.sampler < 0 ||
                c.sampler >= (int)anim.samplers.size())
                continue;
            anim.channels.push_back(c);
        }
        if (!anim.samplers.empty() && !anim.channels.empty())
            out.animations.push_back(std::move(anim));
    }
    if (!out.animations.empty())
        std::printf("SCENE %s: %zu animations\n", path.c_str(),
                    out.animations.size());

    // ---- nodes / hierarchy ----
    const auto& nodes = g.value("nodes", json::array());
    // pick the root that contains rootHint
    auto subtreeHas = [&](int root, const char* hint) {
        std::vector<int> st = {root};
        while (!st.empty()) {
            const int i = st.back();
            st.pop_back();
            const auto& n = nodes[i];
            const std::string nm = n.value("name", "");
            if (nm.find(hint) != std::string::npos)
                return true;
            for (int c : n.value("children", json::array()))
                st.push_back(c);
        }
        return false;
    };

    // traverse EVERY scene root (skip duplicates via visited): extra
    // roots often hold additional parts (turret mantlet, gun mounts)
    out.bmin = glm::vec3(1e30f);
    out.bmax = glm::vec3(-1e30f);
    std::vector<glm::mat4> mats(nodes.size(), glm::mat4(1.0f));
    std::vector<bool> visited(nodes.size(), false);
    std::vector<int> roots;
    if (g.contains("scenes") && !g["scenes"].empty()) {
        const int sceneId = std::clamp(g.value("scene", 0), 0,
                                       (int)g["scenes"].size() - 1);
        for (int r : g["scenes"][sceneId].value("nodes", json::array()))
            roots.push_back(r);
    }
    if (roots.empty()) {
        std::vector<bool> isChild(nodes.size(), false);
        for (const auto& n : nodes)
            for (int c : n.value("children", json::array()))
                if (c >= 0 && c < (int)isChild.size())
                    isChild[c] = true;
        for (int i = 0; i < (int)nodes.size(); ++i)
            if (!isChild[i])
                roots.push_back(i);
    }
    // prefer to start from the root that matches the hint
    if (rootHint && rootHint[0])
        for (int r : roots)
            if (subtreeHas(r, rootHint)) {
                roots.erase(std::remove(roots.begin(), roots.end(), r),
                            roots.end());
                roots.insert(roots.begin(), r);
                break;
            }

    out.nodeLocal.assign(nodes.size(), glm::mat4(1.0f));
    out.nodeParent.assign(nodes.size(), -1);
    out.nodeChildren.assign(nodes.size(), {});
    out.nodeMesh.assign(nodes.size(), -1);
    out.nodeNames.resize(nodes.size());
    for (int i = 0; i < (int)nodes.size(); ++i) {
        const auto& n = nodes[i];
        out.nodeNames[i] = n.value("name", "");
        out.nodeMesh[i] = n.value("mesh", -1);
        glm::mat4 local(1.0f);
        if (n.contains("matrix") && n["matrix"].size() == 16) {
            for (int col = 0; col < 4; ++col)
                for (int row = 0; row < 4; ++row)
                    local[col][row] = n["matrix"][col * 4 + row].get<float>();
        } else {
            glm::vec3 t(0);
            glm::quat r(1, 0, 0, 0);
            glm::vec3 s(1);
            if (n.contains("translation"))
                t = glm::vec3(n["translation"][0].get<float>(),
                              n["translation"][1].get<float>(),
                              n["translation"][2].get<float>());
            if (n.contains("rotation"))
                r = glm::quat(n["rotation"][3].get<float>(),
                              n["rotation"][0].get<float>(),
                              n["rotation"][1].get<float>(),
                              n["rotation"][2].get<float>());
            if (n.contains("scale"))
                s = glm::vec3(n["scale"][0].get<float>(),
                              n["scale"][1].get<float>(),
                              n["scale"][2].get<float>());
            local = composeTRS(t, r, s);
        }
        out.nodeLocal[i] = local;
        for (const auto& c : n.value("children", json::array())) {
            const int child = c.get<int>();
            if (child >= 0 && child < (int)nodes.size()) {
                out.nodeChildren[i].push_back(child);
                out.nodeParent[child] = i;
            }
        }
    }

    std::vector<int> dfs;
    std::vector<glm::mat4> parM;
    for (int root : roots) {
        if (visited[root])
            continue;
        dfs.push_back(root);
        parM.push_back(glm::mat4(1.0f));
        while (!dfs.empty()) {
            const int i = dfs.back();
            const glm::mat4 pm = parM.back();
            dfs.pop_back();
            parM.pop_back();
            if (visited[i])
                continue;
            visited[i] = true;
            const auto& n = nodes[i];
            const glm::mat4 local = out.nodeLocal[i];
            const glm::mat4 M = pm * local;
            mats[i] = M;

            const int meshId = n.value("mesh", -1);
            if (meshId >= 0 && meshId < (int)meshToScene.size() &&
                !meshToScene[meshId].empty()) {
                const std::string name = n.value("name", "");
                const ObjTag tag = tagOfName(name);
                glm::vec3 muzzleLocal(0, 0, 1);
                glm::vec3 muzzleDir(0, 0, 1);
                float muzzleLen = 0.0f;
                if (tag == TAG_BARREL) {
                    const glm::vec3 pivot = glm::vec3(M * glm::vec4(0, 0, 0, 1));
                    for (int geomId : meshToScene[meshId]) {
                        const SceneGeom& gm = out.geoms[geomId];
                        for (size_t v = 0; v < gm.verts.size() / 8; ++v) {
                            const float* p = &gm.verts[v * 8];
                            const glm::vec3 lp(p[0], p[1], p[2]);
                            const glm::vec3 w = M * glm::vec4(lp, 1);
                            const float d = glm::length(w - pivot);
                            if (d > muzzleLen) {
                                muzzleLen = d;
                                muzzleLocal = lp;
                                muzzleDir = glm::normalize(lp);
                            }
                        }
                    }
                }
                for (int geomId : meshToScene[meshId]) {
                    SceneObj obj;
                    obj.base = M;
                    obj.baseInv = glm::inverse(M);
                    obj.mesh = geomId;
                    obj.node = i;
                    obj.skin = n.value("skin", -1);
                    obj.name = name;
                    obj.tag = tag;
                    obj.pivotLocal = glm::vec3(M[3]);
                    obj.muzzleLocal = muzzleLocal;
                    obj.muzzleDirLocal = muzzleDir;
                    obj.muzzleLen = muzzleLen;
                    out.objs.push_back(std::move(obj));
                }
            }

            const auto& kids = n.value("children", json::array());
            for (int k = (int)kids.size() - 1; k >= 0; --k) {
                if (!visited[kids[k]]) {
                    dfs.push_back(kids[k]);
                    parM.push_back(M);
                }
            }
        }
    }

    // overall bbox (sample transformed mesh bbox corners)
    for (const SceneObj& o : out.objs) {
        const SceneGeom& gm = out.geoms[o.mesh];
        for (int c = 0; c < 8; ++c) {
            const glm::vec3 corner(
                (c & 1) ? gm.bmax.x : gm.bmin.x,
                (c & 2) ? gm.bmax.y : gm.bmin.y,
                (c & 4) ? gm.bmax.z : gm.bmin.z);
            const glm::vec3 w = o.base * glm::vec4(corner, 1);
            out.bmin = glm::min(out.bmin, w);
            out.bmax = glm::max(out.bmax, w);
        }
    }
    out.minY = out.bmin.y;
    out.ok = !out.objs.empty() && !out.geoms.empty();
    std::printf("SCENE %s: %zu objects, %zu geoms, %zu images, "
                "bbox %.1f..%.1f | %.1f..%.1f | %.1f..%.1f\n",
                path.c_str(), out.objs.size(), out.geoms.size(),
                out.images.size(), out.bmin.x, out.bmax.x, out.bmin.y,
                out.bmax.y, out.bmin.z, out.bmax.z);
    return out.ok;
}

int findNode(const Scene& sc, const std::string& name) {
    for (int i = 0; i < (int)sc.nodeNames.size(); ++i)
        if (sc.nodeNames[i] == name)
            return i;
    // Blender sometimes prefixes bone names with the armature name
    for (int i = 0; i < (int)sc.nodeNames.size(); ++i) {
        const std::string& n = sc.nodeNames[i];
        if (n.size() > name.size() &&
            n.compare(n.size() - name.size(), name.size(), name) == 0)
            return i;
    }
    return -1;
}

void computeNodeGlobals(const Scene& sc, const std::vector<glm::mat4>& locals,
                        std::vector<glm::mat4>& out) {
    const size_t n = sc.nodeLocal.size();
    out.assign(n, glm::mat4(1.0f));
    std::vector<int> stack;
    for (size_t i = 0; i < n; ++i)
        if (sc.nodeParent[i] < 0)
            stack.push_back((int)i);
    std::vector<bool> done(n, false);
    while (!stack.empty()) {
        const int i = stack.back();
        stack.pop_back();
        if (done[i])
            continue;
        done[i] = true;
        const glm::mat4& local =
            i < (int)locals.size() ? locals[i] : sc.nodeLocal[i];
        const int parent = sc.nodeParent[i];
        out[i] = parent >= 0 ? out[parent] * local : local;
        for (int c : sc.nodeChildren[i])
            if (!done[c])
                stack.push_back(c);
    }
}

void computeSkinMatrices(const Scene& sc,
                         const std::vector<glm::mat4>& globals, int skinIndex,
                         std::vector<glm::mat4>& out) {
    out.clear();
    if (skinIndex < 0 || skinIndex >= (int)sc.skins.size())
        return;
    const Skin& skin = sc.skins[skinIndex];
    out.resize(skin.joints.size(), glm::mat4(1.0f));
    for (size_t j = 0; j < skin.joints.size(); ++j) {
        const int node = skin.joints[j];
        if (node < 0 || node >= (int)globals.size())
            continue;
        const glm::mat4& ibm =
            j < skin.inverseBind.size() ? skin.inverseBind[j]
                                        : glm::mat4(1.0f);
        out[j] = globals[node] * ibm;
    }
}

} // namespace model
