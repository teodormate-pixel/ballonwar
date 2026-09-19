// ============================================================
// INFINITE smooth diggable terrain surface.
//
// The height function is the reference algorithm evaluated per
// point, so it is continuous and unbounded in every direction:
//
//   height(x,z) = baseHeightAt(x,z)                 (noise, any point)
//               + erodedDelta(x,z) * feather        (central eroded map)
//               - carve(x,z)                        (player digging)
//
// Rendering is paged: pages of 65 x 65 vertices (128 m, 2 m
// cells) are meshed lazily around the player, CPU-side, into
// position+normal vertex buffers. The GPU just displaces nothing
// - it receives real geometry and shades it.
// ============================================================

#pragma once

#include <cstdint>
#include <glm/glm.hpp>
#include <unordered_map>
#include <vector>

#include "terrain.h"

namespace world {

// ------------------------------------------------------------
// constants
// ------------------------------------------------------------

constexpr double CELL = 2.0;   // meters per terrain column
constexpr int PAGE_CELLS = 64; // cells per page side
constexpr int PAGE_VERTS = PAGE_CELLS + 1;     // 65
constexpr int PAGE_SIZE = PAGE_CELLS * CELL;   // 128 m
constexpr double ERODE_R_IN = 340.0;           // eroded core radius
constexpr double ERODE_R_OUT = 480.0;          // full feather-out radius

// world coordinate of lattice column c (infinite grid, 2 m cells)
inline double colWorld(int64_t c) { return (double)c * CELL; }
inline int64_t colIndex(double w) {
    return (int64_t)std::floor(w / CELL + 0.5);
}

inline int64_t pageKey(int64_t px, int64_t pz) {
    // unsigned shifts: shifting negative px would be undefined behaviour
    return (int64_t)(((uint64_t)(uint32_t)px << 32) ^ (uint64_t)(uint32_t)pz);
}

// one CPU page: [PAGE_VOL] heights with a 1-column ring (67 x 67)
struct Page {
    int64_t px = 0, pz = 0;
    bool built = false;
    bool dirtyMesh = false; // -> main re-uploads the VBO
    std::vector<float> h;   // 67*67, h[(z+1)*67+(x+1)] = col px*64+x
    std::vector<float> verts; // pos3+nrm3, PAGE_VERTS*PAGE_VERTS
};

struct HitPoint {
    bool hit = false;
    float x = 0, y = 0, z = 0;
};

// ------------------------------------------------------------
// the surface world
// ------------------------------------------------------------

class TerrainSurface {
  public:
    explicit TerrainSurface(terrain::HeightField eroded);

    const terrain::HeightField& eroded() const { return eroded_; }

    // continuous surface height (base + eroded feather - carve)
    double heightAt(double wx, double wz) const;
    double baseAt(double wx, double wz) const { return terrain::baseHeightAt(wx, wz); }

    // pick the surface along a ray (digging)
    HitPoint raycast(const glm::vec3& origin, const glm::vec3& dir,
                     double maxDist) const;

    int64_t lastDigX() const { return lastDigX_; }
    int64_t lastDigZ() const { return lastDigZ_; }

    // dig a brush stroke centred on the world point (wx, wz)
    void digAt(double wx, double wz);

    // lower the surface at one column so it ends at most at targetHeight
    // (sphere digging / explosions)
    void carveTo(double wx, double wz, double targetHeight);

    // ---- paging ----
    void ensureBuilt(int64_t px, int64_t pz);
    const std::unordered_map<int64_t, Page>& pages() const { return pages_; }
    std::unordered_map<int64_t, Page>& pages() { return pages_; }
    int64_t pageKeyOf(double wx, double wz) const {
        return pageKey(colIndex(wx) / PAGE_CELLS, colIndex(wz) / PAGE_CELLS);
    }
    static int64_t pxOf(double wx) {
        return (int64_t)std::floor(colIndex(wx) / (double)PAGE_CELLS);
    }

  private:
    double carveBilinear(double wx, double wz) const;
    // refresh built pages that sample the brushed world columns
    void refreshPages(int64_t bx0, int64_t bx1, int64_t bz0, int64_t bz1);

    terrain::HeightField eroded_;
    int64_t lastDigX_ = 0, lastDigZ_ = 0;
    // dug depth per lattice column (sparse, huge world)
    std::unordered_map<int64_t, float> carve_;

    std::unordered_map<int64_t, Page> pages_;
};

} // namespace world
