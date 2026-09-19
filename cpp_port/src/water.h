// ============================================================
// REAL WATER SIMULATION (height-field shallow water fluids)
//
// Gravity-driven, mass-conserving flow on the same 2 m column
// lattice as the terrain. Each page owns 64x64 columns; border
// faces are solved exactly once by the owner of the lower
// column, so water flows across pages without seams or loss.
//
// Rain falls on the high mountains -> permanent streams/rivers
// run down the valleys; water pools in pits and dug trenches
// (flooding) and settles into calm flat lakes at equilibrium.
// Evaporation removes thin films; water leaving the simulated
// radius drains away at the boundary.
// ============================================================

#pragma once

#include <cstdint>
#include <glm/glm.hpp>
#include <unordered_map>
#include <vector>

#include "world.h"

namespace water {

constexpr int N = world::PAGE_CELLS; // 64 columns per page

struct WPage {
    int64_t px = 0, pz = 0;
    bool active = false;
    bool hasWater = false;
    bool dirty = false;
    bool rainy = false; // terrain here exceeds RAIN_ALT (always active)

    // S: free-surface height above terrain bottom (depth), meters
    std::vector<float> S; // N*N, S[z*N+x]
    // cached terrain bottom per column (kept in sync after digging)
    std::vector<float> b; // N*N

    // rendered surface: 65x65 vertices (pos3 + nrm3 + rgba4)
    bool surfReady = false;
    std::vector<float> surf;  // 65*65*10
    std::vector<uint32_t> idx;
};

class Sim {
  public:
    explicit Sim(world::TerrainSurface& terrain) : terrain_(terrain) {}

    void maintainAround(const glm::dvec3& eye, double radiusMeters);
    void step(double dt);

    // terrain changed around these columns (digging): resync bottoms
    void terrainChanged(int64_t px, int64_t pz);

    // rebuild the CPU surface buffers of every wet page
    void rebuildSurfaces();

    const std::unordered_map<int64_t, WPage>& pages() const {
        return pages_;
    }
    std::unordered_map<int64_t, WPage>& pages() { return pages_; }

    // water surface absolute height + depth at a world point
    float surfaceAt(double wx, double wz, float& depthOut) const;

    float rainBoost = 1.0f;
    bool storm = false;

  private:
    WPage* findPage(int64_t px, int64_t pz);
    const WPage* findPage(int64_t px, int64_t pz) const;
    void ensurePage(int64_t px, int64_t pz);
    void solvePage(WPage& p, double dt);

    world::TerrainSurface& terrain_;
    std::unordered_map<int64_t, WPage> pages_;
};

} // namespace water
