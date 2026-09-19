#include "terraintex.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <system_error>

#include "stb_image.h"

namespace terraintex {

namespace {

constexpr float PI = 3.14159265358979323846f;

uint32_t hashU(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

float hash01(int x, int y, int seed) {
    const uint32_t h =
        hashU(((uint32_t)x * 374761393u + (uint32_t)y * 668265263u) ^
              ((uint32_t)seed * 1442695041u));
    return (float)(h & 0xffffffu) / 16777215.0f;
}

float smoothstepf(float t) { return t * t * (3.0f - 2.0f * t); }

// tileable value noise: the lattice wraps every `period` cells
float valueNoise(float x, float y, int period, int seed) {
    const int xi = (int)std::floor(x);
    const int yi = (int)std::floor(y);
    const float fx = smoothstepf(x - (float)xi);
    const float fy = smoothstepf(y - (float)yi);
    auto wrap = [period](int v) {
        v %= period;
        return v < 0 ? v + period : v;
    };
    const int x0 = wrap(xi), x1 = wrap(xi + 1);
    const int y0 = wrap(yi), y1 = wrap(yi + 1);
    const float v00 = hash01(x0, y0, seed);
    const float v10 = hash01(x1, y0, seed);
    const float v01 = hash01(x0, y1, seed);
    const float v11 = hash01(x1, y1, seed);
    const float a = v00 + (v10 - v00) * fx;
    const float b = v01 + (v11 - v01) * fx;
    return a + (b - a) * fy;
}

float fbm(float x, float y, int period, int octaves, int seed) {
    float sum = 0.0f;
    float amp = 0.5f;
    float norm = 0.0f;
    for (int o = 0; o < octaves; ++o) {
        sum += valueNoise(x, y, period, seed + o * 17) * amp;
        norm += amp;
        amp *= 0.5f;
        x *= 2.0f;
        y *= 2.0f;
        period *= 2;
    }
    return sum / std::max(1e-6f, norm);
}

float ridged(float x, float y, int period, int octaves, int seed) {
    return 1.0f - std::abs(2.0f * fbm(x, y, period, octaves, seed) - 1.0f);
}

struct Builder {
    int size;
    std::vector<float> height;
    std::vector<glm::vec3> albedo;
    std::vector<float> rough;
    std::vector<float> ao;

    explicit Builder(int s)
        : size(s), height((size_t)s * s, 0.0f),
          albedo((size_t)s * s, glm::vec3(0.5f)),
          rough((size_t)s * s, 0.8f),
          ao((size_t)s * s, 1.0f) {}

    void set(int x, int y, const glm::vec3& c, float h, float r) {
        const size_t i = (size_t)y * size + x;
        albedo[i] = c;
        height[i] = h;
        rough[i] = r;
        // cheap cavity AO from the height field (darker in the dips)
        ao[i] = 0.72f + 0.28f * std::clamp(h, 0.0f, 1.0f);
    }

    bake::Image albedoImage() const {
        bake::Image img;
        img.w = img.h = size;
        img.rgba.resize((size_t)size * size * 4);
        for (size_t i = 0; i < albedo.size(); ++i) {
            const glm::vec3 c = glm::clamp(albedo[i], 0.0f, 1.0f);
            img.rgba[i * 4 + 0] = (uint8_t)std::lround(c.r * 255.0f);
            img.rgba[i * 4 + 1] = (uint8_t)std::lround(c.g * 255.0f);
            img.rgba[i * 4 + 2] = (uint8_t)std::lround(c.b * 255.0f);
            img.rgba[i * 4 + 3] =
                (uint8_t)std::lround(glm::clamp(rough[i], 0.0f, 1.0f) * 255.0f);
        }
        return img;
    }

    bake::Image extraImage() const {
        bake::Image img;
        img.w = img.h = size;
        img.rgba.resize((size_t)size * size * 4);
        for (size_t i = 0; i < albedo.size(); ++i) {
            img.rgba[i * 4 + 0] = 0;   // metallic (dielectric terrain)
            img.rgba[i * 4 + 1] =
                (uint8_t)std::lround(glm::clamp(height[i], 0.0f, 1.0f) * 255.0f);
            img.rgba[i * 4 + 2] = 128; // reflectance (neutral)
            img.rgba[i * 4 + 3] = 255;
        }
        return img;
    }

    bake::Image normalImage(float strength) const {
        bake::Image img;
        img.w = img.h = size;
        img.rgba.resize((size_t)size * size * 4);
        auto h = [&](int x, int y) {
            x = (x + size) % size;
            y = (y + size) % size;
            return height[(size_t)y * size + x];
        };
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x) {
                const float dx = (h(x + 1, y) - h(x - 1, y)) * 0.5f * strength;
                const float dy = (h(x, y + 1) - h(x, y - 1)) * 0.5f * strength;
                glm::vec3 n = glm::normalize(glm::vec3(-dx, -dy, 1.0f));
                const size_t i = (size_t)y * size + x;
                img.rgba[i * 4 + 0] =
                    (uint8_t)std::lround((n.x * 0.5f + 0.5f) * 255.0f);
                img.rgba[i * 4 + 1] =
                    (uint8_t)std::lround((n.y * 0.5f + 0.5f) * 255.0f);
                img.rgba[i * 4 + 2] =
                    (uint8_t)std::lround((n.z * 0.5f + 0.5f) * 255.0f);
                img.rgba[i * 4 + 3] =
                    (uint8_t)std::lround(glm::clamp(ao[(size_t)y * size + x],
                                                    0.0f, 1.0f) *
                                         255.0f);
            }
        }
        return img;
    }
};

float fbmScale(int size, float repeats) { return repeats / (float)size; }

// ---- per-material generators -------------------------------------

Builder makeSand(int size) {
    Builder b(size);
    const float g = fbmScale(size, 48.0f);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float u = (float)x, v = (float)y;
            const float dunes = fbm(u * fbmScale(size, 2.0f),
                                    v * fbmScale(size, 2.0f), 2, 3, 11);
            const float ripples =
                std::sin((v * 0.55f + dunes * 4.0f) * 2.0f * PI) * 0.5f + 0.5f;
            const float grain = fbm(u * g, v * g, 48, 3, 23);
            const float h = dunes * 0.55f + ripples * 0.12f + grain * 0.33f;
            glm::vec3 c(0.80f, 0.73f, 0.52f);
            c *= 0.88f + 0.16f * grain;
            c += glm::vec3(0.02f, 0.015f, 0.0f) * ripples;
            b.set(x, y, c, h, 0.78f + 0.12f * grain);
        }
    }
    return b;
}

Builder makeGrass(int size) {
    Builder b(size);
    const float patch = fbmScale(size, 3.0f);
    const float blades = fbmScale(size, 40.0f);
    const float fine = fbmScale(size, 90.0f);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float u = (float)x, v = (float)y;
            const float clumps = fbm(u * patch, v * patch, 3, 4, 31);
            const float blade = fbm(u * blades, v * blades * 0.35f, 40, 2, 41);
            const float grain = fbm(u * fine, v * fine, 90, 2, 53);
            glm::vec3 c(0.30f, 0.44f, 0.17f);
            c = glm::mix(c, glm::vec3(0.42f, 0.54f, 0.22f), clumps);
            c = glm::mix(c, glm::vec3(0.24f, 0.35f, 0.13f),
                         glm::smoothstep(0.45f, 0.8f, blade) * 0.6f);
            c *= 0.90f + 0.20f * grain;
            const float h = clumps * 0.35f + blade * 0.5f + grain * 0.15f;
            b.set(x, y, c, h, 0.86f + 0.10f * grain);
        }
    }
    return b;
}

Builder makeDirt(int size) {
    Builder b(size);
    const float clump = fbmScale(size, 5.0f);
    const float pebble = fbmScale(size, 55.0f);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float u = (float)x, v = (float)y;
            const float clumps = fbm(u * clump, v * clump, 5, 4, 61);
            const float pebbles = ridged(u * pebble, v * pebble, 55, 2, 67);
            glm::vec3 c(0.38f, 0.29f, 0.18f);
            c = glm::mix(c, glm::vec3(0.30f, 0.22f, 0.13f), clumps);
            c += glm::vec3(0.10f) * glm::smoothstep(0.72f, 0.95f, pebbles);
            const float h = clumps * 0.5f + pebbles * 0.5f;
            b.set(x, y, c, h, 0.90f + 0.08f * pebbles);
        }
    }
    return b;
}

Builder makeRock(int size, glm::vec3 base, int seed) {
    Builder b(size);
    const float strata = fbmScale(size, 3.0f);
    const float crack = fbmScale(size, 9.0f);
    const float grain = fbmScale(size, 60.0f);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float u = (float)x, v = (float)y;
            const float layers =
                fbm(u * strata, v * strata * 3.0f, 3, 4, seed);
            const float cracks =
                ridged(u * crack, v * crack, 9, 3, seed + 7);
            const float grainN = fbm(u * grain, v * grain, 60, 2, seed + 13);
            glm::vec3 c = base * (0.82f + 0.36f * layers);
            c *= 1.0f - 0.45f * glm::smoothstep(0.80f, 0.97f, cracks);
            c *= 0.92f + 0.16f * grainN;
            const float h = layers * 0.45f + cracks * 0.4f + grainN * 0.15f;
            b.set(x, y, c, h, 0.62f + 0.20f * layers - 0.12f * cracks);
        }
    }
    return b;
}

Builder makeSnow(int size) {
    Builder b(size);
    const float drift = fbmScale(size, 3.0f);
    const float grain = fbmScale(size, 70.0f);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float u = (float)x, v = (float)y;
            const float drifts = fbm(u * drift, v * drift, 3, 4, 83);
            const float grainN = fbm(u * grain, v * grain, 70, 2, 89);
            const float sparkle =
                glm::smoothstep(0.93f, 1.0f, hash01(x, y, 97)) * 0.35f;
            glm::vec3 c(0.90f, 0.92f, 0.97f);
            c = glm::mix(c, glm::vec3(0.80f, 0.84f, 0.92f), drifts * 0.7f);
            c += glm::vec3(sparkle);
            const float h = drifts * 0.7f + grainN * 0.3f;
            b.set(x, y, c, h, 0.30f + 0.20f * drifts + 0.1f * grainN);
        }
    }
    return b;
}

// ---- texture set loading -----------------------------------------

struct SetPaths {
    const char* name;
    const char* albedo[2];
    const char* normal[2];
    const char* rough[2];  // direct roughness map
    const char* gloss[2];  // alternative: gloss map (rough = 1 - gloss)
    const char* ao[2];
    const char* disp[2];
    const char* metallic[2];
    const char* refl[2];
    float roughMin;
    float roughMax;
};

// texture sets shipped in the project (first existing path wins)
const SetPaths kSets[6] = {
    {"sand",
     {"assets/textures/GroundSand005/GroundSand005_COL_2K.jpg", nullptr},
     {"assets/textures/GroundSand005/GroundSand005_NRM_2K.jpg", nullptr},
     {nullptr, nullptr},
     {"assets/textures/GroundSand005/GroundSand005_GLOSS_2K.jpg", nullptr},
     {"assets/textures/GroundSand005/GroundSand005_AO_2K.jpg", nullptr},
     {"assets/textures/GroundSand005/GroundSand005_DISP_2K.jpg", nullptr},
     {nullptr, nullptr},
     {"assets/textures/GroundSand005/GroundSand005_REFL_2K.jpg", nullptr},
     0.55f, 0.95f},
    {"grass",
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_BaseColor.jpg",
      "assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_COL_2K.jpg"},
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_Normal.png",
      "assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_NRM_2K.jpg"},
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_Roughness.jpg",
      nullptr},
     {nullptr, nullptr},
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_AmbientOcclusion.jpg",
      "assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_AO_2K.jpg"},
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_Displacement.png",
      "assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_DISP_2K.jpg"},
     {"assets/textures/Poliigon_GrassPatchyGround_4585/2K/"
      "Poliigon_GrassPatchyGround_4585_Metallic.jpg",
      nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_REFL_2K.jpg",
      nullptr},
     0.70f, 1.0f},
    {"dirt",
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_COL_2K.jpg",
      nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_NRM_2K.jpg",
      nullptr},
     {nullptr, nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_GLOSS_2K.jpg",
      nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_AO_2K.jpg",
      nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_DISP_2K.jpg",
      nullptr},
     {nullptr, nullptr},
     {"assets/textures/GroundDirtWeedsPatchy004/"
      "GroundDirtWeedsPatchy004_REFL_2K.jpg",
      nullptr},
     0.65f, 1.0f},
    {"rock",
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_diff_2k.jpg",
      nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_nor_gl_2k.png",
      nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_rough_2k.jpg",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_disp_2k.png",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     0.40f, 0.90f},
    {"grey",
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_diff_2k.jpg",
      nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_nor_gl_2k.png",
      nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_rough_2k.jpg",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     {"assets/textures/rocks_ground_04_2k.blend/textures/"
      "rocks_ground_04_disp_2k.png",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     0.40f, 0.90f},
    {"snow",
     {"assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Color.jpg", nullptr},
     {"assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_NormalGL.jpg", nullptr},
     {"assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Roughness.jpg",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     {"assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Displacement.jpg",
      nullptr},
     {nullptr, nullptr},
     {nullptr, nullptr},
     0.35f, 0.80f},
};

std::string firstExisting(const std::string& root, const char* const paths[2]) {
    for (int i = 0; i < 2 && paths[i]; ++i) {
        const std::string p = root + "/" + paths[i];
        if (std::FILE* f = std::fopen(p.c_str(), "rb")) {
            std::fclose(f);
            return p;
        }
    }
    return {};
}

// loads an image and box-filters it down to size x size
bool loadResized(const std::string& path, int size, int channels,
                 std::vector<uint8_t>& out) {
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f)
        return false;
    std::fseek(f, 0, SEEK_END);
    const long len = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    if (len <= 0) {
        std::fclose(f);
        return false;
    }
    std::vector<uint8_t> bytes((size_t)len);
    const size_t got = std::fread(bytes.data(), 1, bytes.size(), f);
    std::fclose(f);
    if (got != bytes.size())
        return false;
    int w = 0, h = 0, c = 0;
    unsigned char* px = stbi_load_from_memory(bytes.data(), (int)bytes.size(),
                                              &w, &h, &c, channels);
    if (!px || w <= 0 || h <= 0) {
        if (px)
            stbi_image_free(px);
        return false;
    }
    out.assign((size_t)size * size * channels, 0);
    for (int y = 0; y < size; ++y) {
        const int sy0 = (int)((int64_t)y * h / size);
        const int sy1 = std::max(sy0 + 1, (int)((int64_t)(y + 1) * h / size));
        for (int x = 0; x < size; ++x) {
            const int sx0 = (int)((int64_t)x * w / size);
            const int sx1 =
                std::max(sx0 + 1, (int)((int64_t)(x + 1) * w / size));
            uint32_t acc[4] = {0, 0, 0, 0};
            int count = 0;
            for (int sy = sy0; sy < sy1; ++sy)
                for (int sx = sx0; sx < sx1; ++sx) {
                    const unsigned char* p =
                        px + ((size_t)sy * w + sx) * channels;
                    for (int k = 0; k < channels; ++k)
                        acc[k] += p[k];
                    ++count;
                }
            uint8_t* d = &out[((size_t)y * size + x) * channels];
            for (int k = 0; k < channels; ++k)
                d[k] = (uint8_t)(acc[k] / (uint32_t)std::max(1, count));
        }
    }
    stbi_image_free(px);
    return true;
}

} // namespace

namespace {

uint64_t fileStamp(const std::string& path) {
    if (path.empty())
        return 0;
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f)
        return 0;
    std::fseek(f, 0, SEEK_END);
    const long len = std::ftell(f);
    std::fclose(f);
    return len > 0 ? (uint64_t)len : 0;
}

std::string cachePath() {
    if (const char* p = std::getenv("BW_TERRAIN_CACHE"))
        return p;
    const char* xdg = std::getenv("XDG_CACHE_HOME");
    std::string dir = xdg ? std::string(xdg) : std::string(std::getenv("HOME")
                                                               ? std::getenv("HOME")
                                                               : ".");
    return dir + "/.cache/balloonwar/terrain.bin";
}

struct Resolved {
    std::string albedo, normal, rough, gloss;
    std::string ao, disp, metallic, refl;
};

constexpr int kStamps = 6 * 7;

bool cacheLoad(const std::string& path, int size,
               const uint64_t stamps[kStamps], std::vector<Layer>& layers) {
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f)
        return false;
    char magic[8] = {0};
    int32_t fileSize = 0, count = 0;
    uint64_t fileStamps[kStamps] = {0};
    bool ok = std::fread(magic, 1, 8, f) == 8 &&
              std::memcmp(magic, "BWTX2\0\0\0", 8) == 0 &&
              std::fread(&fileSize, sizeof(fileSize), 1, f) == 1 &&
              std::fread(&count, sizeof(count), 1, f) == 1 &&
              fileSize == size && count == 6 &&
              std::fread(fileStamps, sizeof(uint64_t), kStamps, f) ==
                  kStamps &&
              std::memcmp(fileStamps, stamps, sizeof(fileStamps)) == 0;
    if (!ok) {
        std::fclose(f);
        return false;
    }
    layers.resize(6);
    for (int i = 0; i < 6 && ok; ++i) {
        int32_t nameLen = 0;
        ok = std::fread(&nameLen, sizeof(nameLen), 1, f) == 1 &&
             nameLen > 0 && nameLen < 64;
        if (!ok)
            break;
        char name[64] = {0};
        ok = std::fread(name, 1, (size_t)nameLen, f) == (size_t)nameLen;
        if (!ok)
            break;
        Layer& l = layers[i];
        l.name = name;
        l.source = "file";
        const size_t bytes = (size_t)size * size * 4;
        l.albedoRough.w = l.albedoRough.h = size;
        l.albedoRough.rgba.resize(bytes);
        l.normal.w = l.normal.h = size;
        l.normal.rgba.resize(bytes);
        l.extra.w = l.extra.h = size;
        l.extra.rgba.resize(bytes);
        ok = std::fread(l.albedoRough.rgba.data(), 1, bytes, f) == bytes &&
             std::fread(l.normal.rgba.data(), 1, bytes, f) == bytes &&
             std::fread(l.extra.rgba.data(), 1, bytes, f) == bytes;
    }
    std::fclose(f);
    return ok;
}

void cacheSave(const std::string& path, int size,
               const uint64_t stamps[kStamps],
               const std::vector<Layer>& layers) {
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(path).parent_path(), ec);
    std::FILE* f = std::fopen((path + ".tmp").c_str(), "wb");
    if (!f)
        return;
    const int32_t fileSize = size, count = 6;
    bool ok = std::fwrite("BWTX2\0\0\0", 1, 8, f) == 8 &&
              std::fwrite(&fileSize, sizeof(fileSize), 1, f) == 1 &&
              std::fwrite(&count, sizeof(count), 1, f) == 1 &&
              std::fwrite(stamps, sizeof(uint64_t), kStamps, f) == kStamps;
    for (int i = 0; i < 6 && ok; ++i) {
        const int32_t nameLen = (int32_t)layers[i].name.size();
        ok = std::fwrite(&nameLen, sizeof(nameLen), 1, f) == 1 &&
             std::fwrite(layers[i].name.data(), 1, (size_t)nameLen, f) ==
                 (size_t)nameLen;
        const size_t bytes = (size_t)size * size * 4;
        ok = ok &&
             std::fwrite(layers[i].albedoRough.rgba.data(), 1, bytes, f) ==
                 bytes &&
             std::fwrite(layers[i].normal.rgba.data(), 1, bytes, f) == bytes &&
             std::fwrite(layers[i].extra.rgba.data(), 1, bytes, f) == bytes;
    }
    std::fclose(f);
    if (ok)
        std::filesystem::rename(path + ".tmp", path, ec);
    else
        std::remove((path + ".tmp").c_str());
}

} // namespace

std::vector<Layer> generate(int size, const std::string& root) {
    size = std::max(16, size);
    std::vector<Layer> layers(6);

    auto procedural = [&](int idx, Builder&& b, float normalStrength) {
        Layer& l = layers[idx];
        l.name = kSets[idx].name;
        l.source = "procedural";
        l.albedoRough = b.albedoImage();
        l.normal = b.normalImage(normalStrength);
        l.extra = b.extraImage();
    };

    // resolve the texture files (user overrides take priority)
    Resolved res[6];
    uint64_t stamps[kStamps] = {0};
    for (int i = 0; i < 6; ++i) {
        layers[i].name = kSets[i].name;
        layers[i].source = "procedural";
        if (root.empty())
            continue;
        const SetPaths& set = kSets[i];
        auto exists = [](const std::string& p) {
            std::FILE* f = std::fopen(p.c_str(), "rb");
            if (f) {
                std::fclose(f);
                return true;
            }
            return false;
        };
        const std::string base =
            root + "/assets/textures/terrain/" + layers[i].name;
        if (exists(base + "_albedo.png"))
            res[i].albedo = base + "_albedo.png";
        if (exists(base + "_normal.png"))
            res[i].normal = base + "_normal.png";
        if (exists(base + "_rough.png"))
            res[i].rough = base + "_rough.png";
        if (res[i].albedo.empty())
            res[i].albedo = firstExisting(root, set.albedo);
        if (res[i].normal.empty())
            res[i].normal = firstExisting(root, set.normal);
        if (res[i].rough.empty())
            res[i].rough = firstExisting(root, set.rough);
        if (res[i].rough.empty())
            res[i].gloss = firstExisting(root, set.gloss);
        if (res[i].ao.empty())
            res[i].ao = firstExisting(root, set.ao);
        if (res[i].disp.empty())
            res[i].disp = firstExisting(root, set.disp);
        if (res[i].metallic.empty())
            res[i].metallic = firstExisting(root, set.metallic);
        if (res[i].refl.empty())
            res[i].refl = firstExisting(root, set.refl);
        stamps[i * 7 + 0] = fileStamp(res[i].albedo);
        stamps[i * 7 + 1] = fileStamp(res[i].normal);
        stamps[i * 7 + 2] = fileStamp(res[i].rough.empty() ? res[i].gloss
                                                           : res[i].rough);
        stamps[i * 7 + 3] = fileStamp(res[i].ao);
        stamps[i * 7 + 4] = fileStamp(res[i].disp);
        stamps[i * 7 + 5] = fileStamp(res[i].metallic);
        stamps[i * 7 + 6] = fileStamp(res[i].refl);
    }

    const std::string cache = cachePath();
    if (cacheLoad(cache, size, stamps, layers))
        return layers;

    // build from the files, falling back to procedural per material
    for (int i = 0; i < 6; ++i) {
        const SetPaths& set = kSets[i];
        Layer& l = layers[i];
        if (res[i].albedo.empty())
            continue;
        std::vector<uint8_t> albedo, normal, rough, ao, disp, metallic, refl;
        if (!loadResized(res[i].albedo, size, 3, albedo))
            continue;
        const bool hasNormal = loadResized(res[i].normal, size, 3, normal);
        const bool hasRough = loadResized(res[i].rough, size, 1, rough);
        const bool hasGloss =
            !hasRough && loadResized(res[i].gloss, size, 1, rough);
        const bool hasAo = loadResized(res[i].ao, size, 1, ao);
        const bool hasDisp = loadResized(res[i].disp, size, 1, disp);
        const bool hasMetal = loadResized(res[i].metallic, size, 1, metallic);
        const bool hasRefl = loadResized(res[i].refl, size, 1, refl);

        l.albedoRough.w = l.albedoRough.h = size;
        l.albedoRough.rgba.assign((size_t)size * size * 4, 255);
        l.normal.w = l.normal.h = size;
        l.normal.rgba.assign((size_t)size * size * 4, 255);
        l.extra.w = l.extra.h = size;
        l.extra.rgba.assign((size_t)size * size * 4, 255);
        for (size_t p = 0; p < (size_t)size * size; ++p) {
            l.albedoRough.rgba[p * 4 + 0] = albedo[p * 3 + 0];
            l.albedoRough.rgba[p * 4 + 1] = albedo[p * 3 + 1];
            l.albedoRough.rgba[p * 4 + 2] = albedo[p * 3 + 2];
            float r = 0.85f;
            if (hasRough)
                r = rough[p] / 255.0f;
            else if (hasGloss)
                r = 1.0f - rough[p] / 255.0f;
            r = std::clamp(r, set.roughMin, set.roughMax);
            l.albedoRough.rgba[p * 4 + 3] = (uint8_t)std::lround(r * 255.0f);
            if (hasNormal) {
                l.normal.rgba[p * 4 + 0] = normal[p * 3 + 0];
                l.normal.rgba[p * 4 + 1] = normal[p * 3 + 1];
                l.normal.rgba[p * 4 + 2] = normal[p * 3 + 2];
            } else {
                l.normal.rgba[p * 4 + 0] = 128;
                l.normal.rgba[p * 4 + 1] = 128;
                l.normal.rgba[p * 4 + 2] = 255;
            }
            l.normal.rgba[p * 4 + 3] = hasAo ? ao[p] : 255;
            l.extra.rgba[p * 4 + 0] = hasMetal ? metallic[p] : 0;
            l.extra.rgba[p * 4 + 1] = hasDisp ? disp[p] : 128;
            l.extra.rgba[p * 4 + 2] = hasRefl ? refl[p] : 128;
            l.extra.rgba[p * 4 + 3] = 255;
        }
        l.source = "file";
    }

    if (layers[SAND].source != "file")
        procedural(SAND, makeSand(size), 1.0f);
    if (layers[GRASS].source != "file")
        procedural(GRASS, makeGrass(size), 2.2f);
    if (layers[DIRT].source != "file")
        procedural(DIRT, makeDirt(size), 2.0f);
    if (layers[ROCK].source != "file")
        procedural(ROCK, makeRock(size, glm::vec3(0.46f, 0.44f, 0.42f), 71),
                   2.6f);
    if (layers[GREY].source != "file")
        procedural(GREY, makeRock(size, glm::vec3(0.62f, 0.62f, 0.63f), 101),
                   2.2f);
    if (layers[SNOW].source != "file")
        procedural(SNOW, makeSnow(size), 1.4f);

    cacheSave(cache, size, stamps, layers);
    return layers;
}

} // namespace terraintex
