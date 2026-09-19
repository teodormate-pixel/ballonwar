#include "world.h"

#include <algorithm>
#include <cmath>
#include <functional>

namespace world {

namespace {
// clamp01 + smoothstep
inline double ss(double v) {
    v = std::clamp(v, 0.0, 1.0);
    return v * v * (3.0 - 2.0 * v);
}

inline int64_t colKey(int64_t cx, int64_t cz) {
    return ((int64_t)(uint32_t)cx << 32) | (uint32_t)cz;
}
} // namespace

// ------------------------------------------------------------
// construction: cache eroded - base deltas for the central map
// ------------------------------------------------------------

TerrainSurface::TerrainSurface(terrain::HeightField eroded)
    : eroded_(std::move(eroded)) {}

double TerrainSurface::carveBilinear(double wx, double wz) const {
    const double cx = wx / CELL;
    const double cz = wz / CELL;
    const int64_t x0 = (int64_t)std::floor(cx);
    const int64_t z0 = (int64_t)std::floor(cz);
    const double fx = cx - (double)x0;
    const double fz = cz - (double)z0;

    auto get = [&](int64_t x, int64_t z) {
        auto it = carve_.find(colKey(x, z));
        return it == carve_.end() ? 0.0f : it->second;
    };

    const float a = get(x0, z0);
    const float b = get(x0 + 1, z0);
    const float c = get(x0, z0 + 1);
    const float d = get(x0 + 1, z0 + 1);
    const double top = a + (b - a) * fx;
    const double bot = c + (d - c) * fx;
    return top + (bot - top) * fz;
}

// ------------------------------------------------------------
// height function (infinite)
// ------------------------------------------------------------

double TerrainSurface::heightAt(double wx, double wz) const {
    const double r = std::max(std::abs(wx), std::abs(wz));
    const double a =
        (r <= ERODE_R_IN)
            ? 1.0
            : (r >= ERODE_R_OUT
                   ? 0.0
                   : ss((ERODE_R_OUT - r) / (ERODE_R_OUT - ERODE_R_IN)));

    double h;
    if (a > 0.0) {
        // sampled eroded map (reference pipeline output)
        h = eroded_.heightAtWorld(wx, wz);
        if (a < 1.0) {
            const double base = terrain::baseHeightAt(wx, wz);
            h = base + (h - base) * a;
        }
    } else {
        h = terrain::baseHeightAt(wx, wz);
    }
    return h - carveBilinear(wx, wz);
}

// ------------------------------------------------------------
// raycast (digging)
// ------------------------------------------------------------

HitPoint TerrainSurface::raycast(const glm::vec3& origin,
                                 const glm::vec3& dir,
                                 double maxDist) const {
    HitPoint hp;
    const glm::dvec3 o(origin);
    const glm::dvec3 d(dir);

    const double step = 0.18;
    double t = step * 0.5;
    bool prevInside = false;
    for (; t < maxDist; t += step) {
        const glm::dvec3 p = o + d * t;
        const double g = heightAt(p.x, p.z);
        const bool inside = p.y <= g - 0.02;
        if (inside && !prevInside) {
            hp.hit = true;
            hp.x = (float)p.x;
            hp.y = (float)p.y;
            hp.z = (float)p.z;
            return hp;
        }
        prevInside = inside;
    }
    return hp;
}

// ------------------------------------------------------------
// digging: brush into the sparse column map + refresh affected pages
// ------------------------------------------------------------

namespace {
// refresh the stored page grid + vertex normals for a rectangle of
// WORLD COLUMNS [x0..x1] x [z0..z1] (inclusive)
void refreshPage(Page& p, int64_t x0, int64_t x1, int64_t z0, int64_t z1,
                 const std::function<double(double, double)>& fn) {
    const int64_t px0 = p.px * PAGE_CELLS - 1; // grid col of index 0
    const int64_t pz0 = p.pz * PAGE_CELLS - 1;

    const int gx0 = (int)std::clamp(x0 - px0, (int64_t)0, (int64_t)66);
    const int gx1 = (int)std::clamp(x1 - px0, (int64_t)0, (int64_t)66);
    const int gz0 = (int)std::clamp(z0 - pz0, (int64_t)0, (int64_t)66);
    const int gz1 = (int)std::clamp(z1 - pz0, (int64_t)0, (int64_t)66);

    for (int gz = gz0; gz <= gz1; ++gz)
        for (int gx = gx0; gx <= gx1; ++gx)
            p.h[(size_t)gz * 67 + gx] =
                (float)fn(colWorld(px0 + gx), colWorld(pz0 + gz));

    // vertices whose one-ring grid cells changed need new normals
    const int vx0 = std::max(0, gx0 - 2);
    const int vx1 = std::min(64, gx1);
    const int vz0 = std::max(0, gz0 - 2);
    const int vz1 = std::min(64, gz1);
    const double inv2 = 1.0 / (2.0 * CELL);
    for (int vz = vz0; vz <= vz1; ++vz)
        for (int vx = vx0; vx <= vx1; ++vx) {
            const int gix = vx + 1;
            const int giz = vz + 1;
            const float y = p.h[(size_t)giz * 67 + gix];
            const float hx0 = p.h[(size_t)giz * 67 + gix - 1];
            const float hx1 = p.h[(size_t)giz * 67 + gix + 1];
            const float hz0 = p.h[(size_t)(giz - 1) * 67 + gix];
            const float hz1 = p.h[(size_t)(giz + 1) * 67 + gix];
            const double dxs = (hx1 - hx0) * inv2;
            const double dzs = (hz1 - hz0) * inv2;
            glm::vec3 n =
                glm::normalize(glm::vec3((float)-dxs, 1.0f, (float)-dzs));
            float* v = &p.verts[((size_t)vz * PAGE_VERTS + vx) * 6];
            v[0] = (float)colWorld(p.px * PAGE_CELLS + vx);
            v[1] = y;
            v[2] = (float)colWorld(p.pz * PAGE_CELLS + vz);
            v[3] = n.x;
            v[4] = n.y;
            v[5] = n.z;
        }
}
} // namespace

void TerrainSurface::digAt(double wx, double wz) {
    const int64_t cx = colIndex(wx);
    const int64_t cz = colIndex(wz);
    lastDigX_ = cx;
    lastDigZ_ = cz;

    constexpr double DEPTH = 1.5;
    constexpr double R1 = 0.5, R2 = 0.13;

    for (int64_t dj = -2; dj <= 2; ++dj)
        for (int64_t di = -2; di <= 2; ++di) {
            const int d = (int)std::max(std::abs(di), std::abs(dj));
            const double rel =
                d == 0 ? 1.0 : (d == 1 ? R1 : (d == 2 ? R2 : 0.0));
            if (rel <= 0)
                continue;
            const int64_t x = cx + di;
            const int64_t z = cz + dj;
            float& v = carve_[colKey(x, z)];
            v = std::min(v + (float)(DEPTH * rel), 14.0f);
        }

    refreshPages(cx - 2, cx + 2, cz - 2, cz + 2);
}

void TerrainSurface::refreshPages(int64_t bx0, int64_t bx1, int64_t bz0,
                                  int64_t bz1) {
    const int64_t px0 = (int64_t)std::ceil((double)(bx0 - 65) / PAGE_CELLS);
    const int64_t px1 = (bx1 + 1) / PAGE_CELLS;
    const int64_t pz0 = (int64_t)std::ceil((double)(bz0 - 65) / PAGE_CELLS);
    const int64_t pz1 = (bz1 + 1) / PAGE_CELLS;

    std::function<double(double, double)> fn = [this](double x, double z) {
        return heightAt(x, z);
    };

    for (auto& [key, p] : pages_) {
        (void)key;
        if (!p.built)
            continue;
        if (p.px < px0 || p.px > px1 || p.pz < pz0 || p.pz > pz1)
            continue;
        refreshPage(p, bx0, bx1, bz0, bz1, fn);
        p.dirtyMesh = true;
    }
}

void TerrainSurface::carveTo(double wx, double wz, double targetHeight) {
    const double current = heightAt(wx, wz);
    if (current <= targetHeight)
        return;
    const int64_t cx = colIndex(wx);
    const int64_t cz = colIndex(wz);
    float& v = carve_[colKey(cx, cz)];
    v = std::min(v + (float)(current - targetHeight), 80.0f);
    refreshPages(cx - 1, cx + 1, cz - 1, cz + 1);
}

// ------------------------------------------------------------
// page building
// ------------------------------------------------------------

void TerrainSurface::ensureBuilt(int64_t px, int64_t pz) {
    const int64_t key = pageKey(px, pz);
    auto it = pages_.find(key);
    if (it != pages_.end() && it->second.built)
        return;

    Page& page = pages_[key];
    page.px = px;
    page.pz = pz;
    page.built = true;
    page.dirtyMesh = true;
    page.h.assign((size_t)67 * 67, 0.0f);
    page.verts.resize((size_t)PAGE_VERTS * PAGE_VERTS * 6);

    const int64_t cx0 = px * PAGE_CELLS - 1; // ring start column
    const int64_t cz0 = pz * PAGE_CELLS - 1;

    // heights with one-column ring
    for (int z = 0; z < 67; ++z)
        for (int x = 0; x < 67; ++x)
            page.h[(size_t)z * 67 + x] =
                (float)heightAt(colWorld(cx0 + x), colWorld(cz0 + z));

    // Hydraulic erosion for pages fully outside the central eroded
    // map: the same reference droplets run per tile (each column is
    // eroded exactly once, by its own page) so mountains far away
    // keep the eroded gullies/channels look.
    {
        const int64_t bx = px * PAGE_CELLS;
        const int64_t bz = pz * PAGE_CELLS;
        // nearest corner distance to the world centre (Chebyshev)
        double minR = 1e300;
        for (int c = 0; c <= 64; c += 64)
            for (int r = 0; r <= 64; r += 64) {
                const double rx = std::abs(colWorld(bx + c));
                const double rz = std::abs(colWorld(bz + r));
                minR = std::min(minR, std::max(rx, rz));
            }
        if (minR > ERODE_R_OUT) {
            const uint64_t seed =
                ((uint64_t)(uint32_t)px * 0x9E3779B97F4A7C15ULL) ^
                ((uint64_t)(uint32_t)pz * 0xBF58476D1CE4E5B9ULL) ^
                0x1944ULL;
            constexpr int TILE_DROPLETS = 1000;
            terrain::erodeTile(page.h, 67, TILE_DROPLETS, seed);

            // light thermal smoothing (reference does this after the
            // droplets) so no erosion spikes remain
            for (int it = 0; it < 3; ++it) {
                for (int z = 1; z <= 65; ++z)
                    for (int x = 1; x <= 65; ++x) {
                        const float hc = page.h[(size_t)z * 67 + x];
                        const float avg =
                            (page.h[(size_t)z * 67 + x + 1] +
                             page.h[(size_t)z * 67 + x - 1] +
                             page.h[(size_t)(z + 1) * 67 + x] +
                             page.h[(size_t)(z - 1) * 67 + x]) *
                            0.25f;
                        const float d = hc - avg;
                        if (std::abs(d) > 5.0f)
                            page.h[(size_t)z * 67 + x] -=
                                (d > 0 ? 1.0f : -1.0f) *
                                std::min(std::abs(d) - 5.0f, 4.0f) * 0.5f;
                    }
            }
        }
    }

    // mesh vertices + smooth normals
    const int64_t bx = px * PAGE_CELLS;
    const int64_t bz = pz * PAGE_CELLS;
    const double inv2 = 1.0 / (2.0 * CELL);

    for (int vz = 0; vz < PAGE_VERTS; ++vz)
        for (int vx = 0; vx < PAGE_VERTS; ++vx) {
            const int gx = vx + 1; // grid index (ring offset)
            const int gz = vz + 1;
            const float y = page.h[(size_t)gz * 67 + gx];
            const float hx0 = page.h[(size_t)gz * 67 + gx - 1];
            const float hx1 = page.h[(size_t)gz * 67 + gx + 1];
            const float hz0 = page.h[(size_t)(gz - 1) * 67 + gx];
            const float hz1 = page.h[(size_t)(gz + 1) * 67 + gx];

            const double dxs = (hx1 - hx0) * inv2;
            const double dzs = (hz1 - hz0) * inv2;
            glm::vec3 n = glm::normalize(
                glm::vec3((float)-dxs, 1.0f, (float)-dzs));

            float* v = &page.verts[((size_t)vz * PAGE_VERTS + vx) * 6];
            v[0] = (float)colWorld(bx + vx);
            v[1] = y;
            v[2] = (float)colWorld(bz + vz);
            v[3] = n.x;
            v[4] = n.y;
            v[5] = n.z;
        }
}

} // namespace world
