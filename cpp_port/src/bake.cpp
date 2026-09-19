#include "bake.h"

#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>

namespace bake {

namespace {

struct Texel {
    bool filled = false;
    glm::vec3 pos{0.0f};
    glm::vec3 nrm{0.0f};
    int bone = -1;
};

struct Tri {
    glm::vec2 uv[3];
    glm::vec3 p[3];
    glm::vec3 n[3];
    int bone[3];
    int geom = -1;
    uint32_t vi[3] = {0, 0, 0};
};

// The shipped meshes come from an automatic unwrap with heavily
// overlapping UV islands (8% of the atlas), which makes a baked
// texture bleed between body parts. Repack the islands into a
// non-overlapping shelf layout before rasterising. Islands are also
// split when they mix bone groups (e.g. two heel triangles sharing
// UV space with the face), so every packed island has one colour
// region.
void repackUVs(std::vector<Tri>& tris,
               const std::function<int(int)>& boneGroup) {
    const size_t n = tris.size();
    if (n == 0)
        return;
    std::vector<int> triGroup(n, 0);
    if (boneGroup) {
        for (size_t i = 0; i < n; ++i) {
            int g[3];
            for (int k = 0; k < 3; ++k)
                g[k] = tris[i].bone[k] >= 0 ? boneGroup(tris[i].bone[k]) : 0;
            triGroup[i] = g[0] == g[1] || g[0] == g[2] ? g[0] : g[1];
        }
    }
    // union-find over triangles sharing an edge with matching UVs
    std::vector<int> parent(n);
    for (size_t i = 0; i < n; ++i)
        parent[i] = (int)i;
    auto find = [&](int a) {
        while (parent[a] != a) {
            parent[a] = parent[parent[a]];
            a = parent[a];
        }
        return a;
    };
    auto unite = [&](int a, int b) {
        const int ra = find(a), rb = find(b);
        if (ra != rb)
            parent[ra] = rb;
    };
    struct EdgeKey {
        long long a, b;
        bool operator==(const EdgeKey& o) const {
            return a == o.a && b == o.b;
        }
    };
    struct EdgeHash {
        size_t operator()(const EdgeKey& k) const {
            return std::hash<long long>()(k.a * 1000003LL ^ k.b);
        }
    };
    // quantised edge key -> first triangle using it
    auto q = [](float v) { return (long long)std::lround(v * 4096.0f); };
    std::unordered_map<EdgeKey, int, EdgeHash> edgeMap;
    for (size_t i = 0; i < n; ++i) {
        for (int e = 0; e < 3; ++e) {
            const int v0 = e, v1 = (e + 1) % 3;
            long long a = q(tris[i].uv[v0].x) * 8192LL + q(tris[i].uv[v0].y);
            long long b = q(tris[i].uv[v1].x) * 8192LL + q(tris[i].uv[v1].y);
            if (a > b)
                std::swap(a, b);
            const EdgeKey key{a, b};
            auto it = edgeMap.find(key);
            if (it == edgeMap.end())
                edgeMap.emplace(key, (int)i);
            else if (triGroup[i] == triGroup[it->second])
                unite((int)i, it->second);
        }
    }

    // island bounds (in UV space); very elongated islands are rotated
    // 90 degrees so the shelf packer does not waste whole rows on them
    std::unordered_map<int, glm::vec4> bounds; // minx, miny, maxx, maxy
    auto addBounds = [&](int r, const glm::vec2& uv) {
        auto it = bounds.find(r);
        if (it == bounds.end())
            it = bounds.emplace(r, glm::vec4(1e9f, 1e9f, -1e9f, -1e9f)).first;
        it->second.x = std::min(it->second.x, uv.x);
        it->second.y = std::min(it->second.y, uv.y);
        it->second.z = std::max(it->second.z, uv.x);
        it->second.w = std::max(it->second.w, uv.y);
    };
    for (size_t i = 0; i < n; ++i)
        for (int k = 0; k < 3; ++k)
            addBounds(find((int)i), tris[i].uv[k]);

    // island -> triangle list (built once, so the rotation pass below
    // stays linear instead of scanning all triangles per island)
    std::unordered_map<int, std::vector<int>> islandTris;
    islandTris.reserve(bounds.size());
    for (size_t i = 0; i < n; ++i)
        islandTris[find((int)i)].push_back((int)i);
    for (auto& [root, b] : bounds) {
        const float w = b.z - b.x;
        const float h = b.w - b.y;
        if (w < 1e-6f || h < 1e-6f)
            continue;
        if (w / h < 3.0f && h / w < 3.0f)
            continue;
        // rotate this island: (u,v) -> (v, 1-u)
        for (int i : islandTris[root])
            for (int k = 0; k < 3; ++k) {
                const glm::vec2 uv = tris[i].uv[k];
                tris[i].uv[k] = glm::vec2(uv.y, 1.0f - uv.x);
            }
        b = glm::vec4(1e9f, 1e9f, -1e9f, -1e9f);
        for (int i : islandTris[root])
            for (int k = 0; k < 3; ++k)
                addBounds(root, tris[i].uv[k]);
    }
    if (bounds.size() <= 1)
        return; // nothing to repack

    // shelf packing: sort by height, fill rows in a unit square
    struct Island {
        int root;
        float w, h;
        float x = 0, y = 0;
    };
    std::vector<Island> islands;
    islands.reserve(bounds.size());
    for (const auto& [root, b] : bounds) {
        const float w = std::max(1e-5f, b.z - b.x);
        const float h = std::max(1e-5f, b.w - b.y);
        islands.push_back({root, w, h});
    }
    std::sort(islands.begin(), islands.end(),
              [](const Island& a, const Island& b) { return a.h > b.h; });
    const float pad = 0.004f;
    float shelfY = pad;
    float shelfH = 0.0f;
    float cursorX = pad;
    float usedX = pad;
    for (auto& isl : islands) {
        if (cursorX + isl.w + pad > 1.0f) {
            shelfY += shelfH + pad;
            shelfH = 0.0f;
            cursorX = pad;
        }
        isl.x = cursorX;
        isl.y = shelfY;
        cursorX += isl.w + pad;
        usedX = std::max(usedX, cursorX);
        shelfH = std::max(shelfH, isl.h);
    }
    const float usedY = shelfY + shelfH + pad;
    const float extent = std::max(usedX, usedY);
    const float scale = extent > 1.0f ? 1.0f / extent : 1.0f;
    // centre the packed layout in the unit square
    const float cx = (1.0f - usedX * scale) * 0.5f;
    const float cy = (1.0f - usedY * scale) * 0.5f;
    std::unordered_map<int, glm::vec2> offsets;
    for (const auto& isl : islands) {
        const glm::vec4 b = bounds[isl.root];
        offsets[isl.root] = glm::vec2(
            cx + isl.x * scale - b.x * scale,
            cy + isl.y * scale - b.y * scale);
    }
    for (size_t i = 0; i < n; ++i) {
        const int r = find((int)i);
        const glm::vec2 off = offsets[r];
        for (int k = 0; k < 3; ++k)
            tris[i].uv[k] = tris[i].uv[k] * scale + off;
    }
}

float hashNoise(const glm::vec3& p, float scale) {
    const glm::vec3 x = p * scale;
    const float h = std::sin(x.x * 12.9898f + x.y * 78.233f + x.z * 37.719f) *
                    43758.5453f;
    return h - std::floor(h);
}

glm::vec3 lerp(const glm::vec3& a, const glm::vec3& b, float t) {
    return a + (b - a) * t;
}

} // namespace

std::vector<Tri> gatherTris(const model::Scene& sc) {
    std::vector<Tri> tris;
    for (const auto& obj : sc.objs) {
        if (obj.mesh < 0 || obj.mesh >= (int)sc.geoms.size())
            continue;
        const model::SceneGeom& g = sc.geoms[obj.mesh];
        const bool skinned = g.skinned && !g.joints.empty();
        const glm::mat3 normalInv =
            glm::transpose(glm::inverse(glm::mat3(obj.base)));
        const size_t vcount = g.verts.size() / 8;
        for (size_t i = 0; i + 2 < g.indices.size(); i += 3) {
            const uint32_t ia = g.indices[i];
            const uint32_t ib = g.indices[i + 1];
            const uint32_t ic = g.indices[i + 2];
            if (ia >= vcount || ib >= vcount || ic >= vcount)
                continue;
            Tri tri;
            tri.geom = obj.mesh;
            const uint32_t vidx[3] = {ia, ib, ic};
            for (int k = 0; k < 3; ++k) {
                tri.vi[k] = vidx[k];
                const float* v = &g.verts[(size_t)vidx[k] * 8];
                const glm::vec3 lp(v[0], v[1], v[2]);
                const glm::vec3 ln(v[3], v[4], v[5]);
                tri.uv[k] = glm::vec2(v[6], v[7]);
                if (skinned) {
                    tri.p[k] = lp;
                    tri.n[k] = ln;
                    int best = 0;
                    for (int c = 1; c < 4; ++c)
                        if (g.weights[(size_t)vidx[k] * 4 + c] >
                            g.weights[(size_t)vidx[k] * 4 + best])
                            best = c;
                    tri.bone[k] = g.joints[(size_t)vidx[k] * 4 + best];
                } else {
                    tri.p[k] = glm::vec3(obj.base * glm::vec4(lp, 1.0f));
                    tri.n[k] = glm::normalize(normalInv * ln);
                }
            }
            tris.push_back(tri);
        }
    }
    return tris;
}

void repackSceneUVs(model::Scene& sc) {
    std::vector<Tri> tris = gatherTris(sc);
    if (tris.empty())
        return;
    // group function: bone -> region (0 when not skinned)
    BoneGroupFn group;
    if (!sc.skins.empty()) {
        std::vector<int> jointGroup(sc.nodeNames.size(), 0);
        for (size_t j = 0; j < sc.skins[0].joints.size(); ++j) {
            const int node = sc.skins[0].joints[j];
            if (node < 0 || node >= (int)sc.nodeNames.size())
                continue;
            const std::string& n = sc.nodeNames[node];
            int g = 0;
            if (n == "spine.006")
                g = 5;
            else if (n == "hand.L" || n == "hand.R")
                g = 4;
            else if (n.rfind("foot", 0) == 0 || n.rfind("toe", 0) == 0 ||
                     n.rfind("heel", 0) == 0)
                g = 3;
            else if (n.rfind("thigh", 0) == 0 || n.rfind("shin", 0) == 0 ||
                     n.rfind("pelvis", 0) == 0)
                g = 2;
            else if (n.rfind("upper_arm", 0) == 0 ||
                     n.rfind("forearm", 0) == 0 || n.rfind("shoulder", 0) == 0)
                g = 1;
            jointGroup[node] = g;
        }
        group = [jointGroup](int bone) {
            return bone >= 0 && bone < (int)jointGroup.size()
                       ? jointGroup[bone]
                       : 0;
        };
    }
    repackUVs(tris, group);
    // write the packed UVs back into the geometry
    for (const Tri& t : tris) {
        if (t.geom < 0 || t.geom >= (int)sc.geoms.size())
            continue;
        model::SceneGeom& g = sc.geoms[t.geom];
        for (int k = 0; k < 3; ++k) {
            const size_t base = (size_t)t.vi[k] * 8;
            if (base + 7 >= g.verts.size())
                continue;
            g.verts[base + 6] = t.uv[k].x;
            g.verts[base + 7] = t.uv[k].y;
        }
    }
}

Image bake(const model::Scene& sc, int size, const ShadeFn& shade) {
    Image out;
    if (size < 16 || sc.objs.empty())
        return out;
    out.w = out.h = size;

    // the scene UVs must already be packed (repackSceneUVs)
    const std::vector<Tri> tris = gatherTris(sc);

    std::vector<Texel> texels((size_t)size * size);
    for (const Tri& tri : tris) {
        const glm::vec2 a = tri.uv[0] * (float)(size - 1);
        const glm::vec2 b = tri.uv[1] * (float)(size - 1);
        const glm::vec2 c = tri.uv[2] * (float)(size - 1);
        const float den =
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
        if (std::abs(den) < 1e-12f)
            continue;
        const int x0 = std::max(0, (int)std::floor(std::min({a.x, b.x, c.x})));
        const int x1 = std::min(size - 1, (int)std::ceil(std::max({a.x, b.x, c.x})));
        const int y0 = std::max(0, (int)std::floor(std::min({a.y, b.y, c.y})));
        const int y1 = std::min(size - 1, (int)std::ceil(std::max({a.y, b.y, c.y})));
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const float px = (float)x + 0.5f;
                const float py = (float)y + 0.5f;
                const float u =
                    ((px - a.x) * (c.y - a.y) - (py - a.y) * (c.x - a.x)) /
                    den;
                const float v =
                    ((b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)) /
                    den;
                const float w = 1.0f - u - v;
                if (u < -1e-4f || v < -1e-4f || w < -1e-4f)
                    continue;
                Texel& t = texels[(size_t)y * size + x];
                t.filled = true;
                t.pos = w * tri.p[0] + u * tri.p[1] + v * tri.p[2];
                t.nrm = w * tri.n[0] + u * tri.n[1] + v * tri.n[2];
                if (tri.bone[0] >= 0 || tri.bone[1] >= 0 || tri.bone[2] >= 0) {
                    if (w >= u && w >= v)
                        t.bone = tri.bone[0];
                    else if (u >= v)
                        t.bone = tri.bone[1];
                    else
                        t.bone = tri.bone[2];
                }
            }
        }
    }

    // shade filled texels
    std::vector<glm::vec3> color((size_t)size * size, glm::vec3(0.0f));
    std::vector<uint8_t> filled((size_t)size * size, 0);
    for (size_t i = 0; i < texels.size(); ++i) {
        if (!texels[i].filled)
            continue;
        color[i] = shade(texels[i].pos, texels[i].nrm, texels[i].bone);
        filled[i] = 1;
    }

    // Fill every empty texel with the nearest island colour (BFS flood
    // fill). This keeps bilinear filtering and mipmaps from blending
    // the packed islands with black, which would darken the model at
    // distance. The first rings are darkened a little to keep a subtle
    // outline around each island.
    std::vector<int> dist((size_t)size * size, -1);
    std::vector<size_t> queue;
    queue.reserve(texels.size());
    for (size_t i = 0; i < filled.size(); ++i)
        if (filled[i]) {
            dist[i] = 0;
            queue.push_back(i);
        }
    for (size_t head = 0; head < queue.size(); ++head) {
        const size_t i = queue[head];
        const int d = dist[i];
        const int x = (int)(i % size);
        const int y = (int)(i / size);
        const int dx[4] = {1, -1, 0, 0};
        const int dy[4] = {0, 0, 1, -1};
        for (int k = 0; k < 4; ++k) {
            const int nx = x + dx[k];
            const int ny = y + dy[k];
            if (nx < 0 || ny < 0 || nx >= size || ny >= size)
                continue;
            const size_t j = (size_t)ny * size + nx;
            if (dist[j] >= 0)
                continue;
            dist[j] = d + 1;
            const float fade = d < 2 ? 0.78f : 1.0f;
            color[j] = color[i] * fade;
            queue.push_back(j);
        }
    }

    out.rgba.resize((size_t)size * size * 4);
    for (size_t i = 0; i < color.size(); ++i) {
        const glm::vec3 c = glm::clamp(color[i], 0.0f, 1.0f);
        out.rgba[i * 4 + 0] = (uint8_t)std::lround(c.r * 255.0f);
        out.rgba[i * 4 + 1] = (uint8_t)std::lround(c.g * 255.0f);
        out.rgba[i * 4 + 2] = (uint8_t)std::lround(c.b * 255.0f);
        out.rgba[i * 4 + 3] = 255;
    }
    return out;
}

namespace {

struct Palette {
    glm::vec3 skin{1.00f, 0.84f, 0.70f};
    glm::vec3 hood{0.36f, 0.57f, 0.78f};
    glm::vec3 hoodDark{0.24f, 0.41f, 0.60f};
    glm::vec3 jacket{0.42f, 0.63f, 0.82f};
    glm::vec3 pants{0.45f, 0.42f, 0.48f};
    glm::vec3 boots{0.40f, 0.26f, 0.15f};
    glm::vec3 gloves{0.52f, 0.38f, 0.23f};
    glm::vec3 eye{0.09f, 0.08f, 0.10f};
};

} // namespace

Image characterTexture(const model::Scene& sc, int size) {
    if (sc.skins.empty())
        return {};
    // joint index -> short name
    std::vector<std::string> jointNames;
    for (int j : sc.skins[0].joints) {
        jointNames.push_back(j >= 0 && j < (int)sc.nodeNames.size()
                                 ? sc.nodeNames[j]
                                 : std::string());
    }
    const Palette pal;
    const glm::vec3 FWD(-1.0f, 0.0f, 0.0f);
    auto group = [&](const std::string& n) {
        if (n == "spine.006")
            return 5; // head/hood
        if (n == "hand.L" || n == "hand.R")
            return 4;
        if (n.rfind("foot", 0) == 0 || n.rfind("toe", 0) == 0 ||
            n.rfind("heel", 0) == 0)
            return 3;
        if (n.rfind("thigh", 0) == 0 || n.rfind("shin", 0) == 0 ||
            n.rfind("pelvis", 0) == 0)
            return 2;
        if (n.rfind("upper_arm", 0) == 0 || n.rfind("forearm", 0) == 0 ||
            n.rfind("shoulder", 0) == 0)
            return 1;
        return 0; // torso
    };
    std::vector<int> boneGroup(jointNames.size());
    for (size_t i = 0; i < jointNames.size(); ++i)
        boneGroup[i] = group(jointNames[i]);

    return bake(sc, size, [&](const glm::vec3& p, const glm::vec3& n,
                              int bone) -> glm::vec3 {
        const int grp =
            bone >= 0 && bone < (int)boneGroup.size() ? boneGroup[bone] : 0;
        const float front = glm::dot(n, FWD);
        glm::vec3 c = pal.jacket;
        switch (grp) {
        case 1:
            c = pal.jacket;
            break;
        case 2:
            c = pal.pants;
            break;
        case 3:
            c = pal.boots;
            break;
        case 4:
            c = pal.gloves;
            break;
        case 5:
            c = pal.hood;
            break;
        default:
            c = pal.jacket;
            break;
        }

        if (grp == 5) {
            // soft oval face on the front of the head + dark hood rim
            const float cy = 0.848f, ry = 0.098f;
            const float cz = 0.030f, rz = 0.118f;
            const float ty = (p.y - cy) / ry;
            const float tz = (p.z - cz) / rz;
            const float t = ty * ty + tz * tz;
            const bool frontish = front > 0.20f && p.x > -0.045f;
            if (frontish && t < 0.75f) {
                c = pal.skin;
                // eyes
                for (float sgn : {1.0f, -1.0f}) {
                    const float dy = (p.y - (cy + 0.014f)) / 0.022f;
                    const float dz = (p.z - (cz + sgn * 0.048f)) / 0.017f;
                    if (dy * dy + dz * dz < 1.0f && t < 0.9f)
                        c = pal.eye;
                }
            } else if (frontish && t < 1.45f) {
                c = t < 1.0f
                        ? lerp(pal.skin, pal.hoodDark, (t - 0.75f) / 0.25f)
                        : pal.hoodDark;
            }
        }

        // subtle material variation (the game shader does the lighting)
        const float grain = hashNoise(p, 55.0f);
        c *= 0.95f + 0.10f * grain;
        c *= 0.90f + 0.10f * glm::clamp(p.y / 1.05f, 0.0f, 1.0f);
        return c;
    });
}

Image arrowTexture(const model::Scene& sc, int size) {
    return bake(sc, size, [](const glm::vec3& p, const glm::vec3& n,
                             int) -> glm::vec3 {
        const glm::vec3 wood(0.45f, 0.30f, 0.16f);
        const glm::vec3 metal(0.62f, 0.64f, 0.68f);
        const glm::vec3 feather(0.75f, 0.20f, 0.16f);
        // the tip is at -X, the fletching at +X
        glm::vec3 c = wood;
        if (p.x < -0.42f)
            c = metal;
        else if (p.x > 0.30f)
            c = feather;
        // grain along the shaft
        const float g = hashNoise(p, 90.0f);
        c *= 0.92f + 0.16f * g;
        (void)n;
        return c;
    });
}

} // namespace bake
