#include "water.h"

#include <algorithm>
#include <cmath>
#include <glm/gtc/constants.hpp>

namespace water {

namespace {

constexpr double GRAV_FLOW = 1.05;
constexpr int SUBSTEPS = 2;
constexpr double RAIN_ALT = 90.0; // ridges and high hills feed more streams
constexpr double RAIN_RATE = 0.0018;
constexpr double DRIZZLE_RATE = 0.00012;
constexpr double STORM_RATE = 0.0016; // heavy rain (6 m/h)
constexpr double EVAP_RATE = 0.00005; // slow evaporation
constexpr float WET_EPS = 0.006f; // make shallow streams visible sooner

// terrain column height (world pages store a 1-ring grid: 67x67)
inline float terrainCol(const world::TerrainSurface& t, int64_t px,
                        int64_t pz, int x, int z) {
    const auto it = t.pages().find(world::pageKey(px, pz));
    if (it == t.pages().end() || !it->second.built)
        return (float)terrain::MIN_HEIGHT;
    return it->second.h[(size_t)(z + 1) * 67 + (x + 1)];
}

inline int64_t pageOf(int64_t c) { // floor division by N
    return c >= 0 ? c / N : -((-c + N - 1) / N);
}

// column (c,r) cell accessors over the pages map
struct Cell {
    float s = 0; // water depth
    float b = 0; // terrain bottom
    bool valid = false;
};

} // namespace

// ------------------------------------------------------------
// page management
// ------------------------------------------------------------

WPage* Sim::findPage(int64_t px, int64_t pz) {
    auto it = pages_.find(world::pageKey(px, pz));
    return it == pages_.end() ? nullptr : &it->second;
}
const WPage* Sim::findPage(int64_t px, int64_t pz) const {
    auto it = pages_.find(world::pageKey(px, pz));
    return it == pages_.end() ? nullptr : &it->second;
}

namespace {
// raw water cell for a lattice column; dry (s=0,b=terrain) when the
// page exists, invalid when no page is simulated there at all
inline Cell cellAt(const std::unordered_map<int64_t, WPage>& pages,
                   const world::TerrainSurface&, int64_t c, int64_t r) {
    Cell out;
    const int64_t px = pageOf(c);
    const int64_t pz = pageOf(r);
    const int gx = (int)(c - px * N);
    const int gz = (int)(r - pz * N);
    if (gx < 0 || gx >= N || gz < 0 || gz >= N) {
        out.valid = false;
        return out;
    }
    const auto it = pages.find(world::pageKey(px, pz));
    if (it == pages.end()) {
        out.valid = false;
        return out;
    }
    const int i = gz * N + gx;
    out.s = it->second.S[i];
    out.b = it->second.b[i];
    out.valid = true;
    return out;
}
} // namespace

void Sim::ensurePage(int64_t px, int64_t pz) {
    if (findPage(px, pz))
        return;
    terrain_.ensureBuilt(px, pz);
    const auto it = terrain_.pages().find(world::pageKey(px, pz));
    if (it == terrain_.pages().end() || !it->second.built)
        return;

    WPage& p = pages_[world::pageKey(px, pz)];
    p.px = px;
    p.pz = pz;
    p.active = false;
    p.hasWater = false;
    p.dirty = false;
    p.surfReady = false;
    p.S.assign((size_t)N * N, 0.0f);
    p.b.assign((size_t)N * N, 0.0f);
    p.surf.assign((size_t)65 * 65 * 10, 0.0f);
    p.idx.clear();
    p.rainy = false;

    for (int z = 0; z < N; ++z)
        for (int x = 0; x < N; ++x) {
            const float b = terrainCol(terrain_, px, pz, x, z);
            const size_t i = (size_t)z * N + x;
            p.b[i] = b;
            const double wx = world::colWorld(px * N + x);
            const double wz = world::colWorld(pz * N + z);
            const float initial =
                (float)terrain::initialWaterDepthAt(wx, wz);
            if (initial > 0.0f) {
                p.S[i] = initial;
                p.hasWater = true;
                p.dirty = true;
            }
            if (b > (float)RAIN_ALT)
                p.rainy = true;
        }
    p.active = p.rainy || p.hasWater;
}

void Sim::terrainChanged(int64_t px, int64_t pz) {
    WPage* p = findPage(px, pz);
    if (!p)
        return;
    for (int z = 0; z < N; ++z)
        for (int x = 0; x < N; ++x)
            p->b[(size_t)z * N + x] = terrainCol(terrain_, px, pz, x, z);
    if (p->hasWater)
        p->dirty = true;
}

void Sim::maintainAround(const glm::dvec3& eye, double radiusMeters) {
    const int64_t pcx = pageOf(world::colIndex(eye.x));
    const int64_t pcz = pageOf(world::colIndex(eye.z));
    const int64_t r = (int64_t)std::ceil(radiusMeters / world::PAGE_SIZE);
    for (int64_t dz = -r; dz <= r; ++dz)
        for (int64_t dx = -r; dx <= r; ++dx)
            ensurePage(pcx + dx, pcz + dz);

    // prune far pages so endless walking does not leak memory
    const int64_t r2 = r + 1;
    for (auto it = pages_.begin(); it != pages_.end();) {
        const WPage& p = it->second;
        if (std::abs(p.px - pcx) > r2 || std::abs(p.pz - pcz) > r2)
            it = pages_.erase(it);
        else {
            if (p.hasWater)
                pages_[it->first].active = true;
            ++it;
        }
    }
}

// ------------------------------------------------------------
// solver
// ------------------------------------------------------------

namespace {
inline double depthAt(const float* S, const float* b, int i) {
    const double d = (double)S[i] - b[i];
    return d > 0 ? d : 0.0;
}

inline double faceMove(float* SA, const float*, int ia, float* SB,
                       const float*, int ib, double want) {
    // S is stored as depth above terrain (S = free - b), so the
    // donor depth check simply uses S itself.
    const double da = SA[ia] > 0 ? (double)SA[ia] : 0.0;
    const double db = SB[ib] > 0 ? (double)SB[ib] : 0.0;
    if (da <= 0.0 && db <= 0.0)
        return 0.0;
    const double donor = want > 0 ? da : db;
    if (donor <= 0.0)
        return 0.0;
    const double cap = 0.28 * donor;
    const double t = std::clamp(want, -cap, cap);
    if (std::abs(t) < 1e-10)
        return 0.0;
    SA[ia] = (float)std::max(0.0, (double)SA[ia] - t);
    SB[ib] = (float)std::max(0.0, (double)SB[ib] + t);
    return std::abs(t);
}
} // namespace

void Sim::solvePage(WPage& p, double dt) {
    float* S = p.S.data();
    (void)0;
    const float* b = p.b.data();
    double maxMove = 0.0;
    const double dtS = dt / SUBSTEPS;

    auto fs = [](const float* S, const float* b, int i) {
        return (double)S[i] + b[i]; // absolute free surface
    };

    // neighbour page pointers
    WPage* NR = findPage(p.px + 1, p.pz);
    WPage* ND = findPage(p.px, p.pz + 1);

    for (int sub = 0; sub < SUBSTEPS; ++sub) {
        for (int z = 0; z < N; ++z)
            for (int x = 0; x < N - 1; ++x) {
                const int i = z * N + x;
                maxMove = std::max(
                    maxMove,
                    faceMove(S, b, i, S, b, i + 1,
                             GRAV_FLOW * (fs(S, b, i) - fs(S, b, i + 1)) *
                                 dtS));
            }
        for (int z = 0; z < N - 1; ++z)
            for (int x = 0; x < N; ++x) {
                const int i = z * N + x;
                maxMove = std::max(
                    maxMove,
                    faceMove(S, b, i, S, b, i + N,
                             GRAV_FLOW * (fs(S, b, i) - fs(S, b, i + N)) *
                                 dtS));
            }

        // right border: our x=N-1 <-> neighbour x=0
        if (NR) {
            float* SN = NR->S.data();
            const float* bN = NR->b.data();
            for (int z = 0; z < N; ++z) {
                const int i = z * N + (N - 1);
                const int j = z * N + 0;
                const double mv =
                    faceMove(S, b, i, SN, bN, j,
                             GRAV_FLOW * (fs(S, b, i) - fs(SN, bN, j)) *
                                 dtS);
                maxMove = std::max(maxMove, mv);
                if (mv > 0)
                    NR->active = true;
            }
        } else {
            // open boundary: water flows out of the simulated world
            const auto tit =
                terrain_.pages().find(world::pageKey(p.px + 1, p.pz));
            const float* tN = (tit != terrain_.pages().end() &&
                               tit->second.built)
                                  ? tit->second.h.data()
                                  : nullptr;
            for (int z = 0; z < N; ++z) {
                const int i = z * N + (N - 1);
                if (S[i] <= 0.0f)
                    continue;
                const double target = tN ? (double)tN[(size_t)(z + 1) * 67 + 1]
                                         : (double)b[i];
                const double t = std::clamp(
                    GRAV_FLOW * (S[i] + b[i] - target) * dtS, 0.0,
                    0.28 * (double)S[i]);
                if (t > 0)
                    maxMove = std::max(maxMove, t);
                S[i] = (float)std::max(0.0, (double)S[i] - t);
            }
        }

        // down border: our z=N-1 <-> neighbour z=0
        if (ND) {
            float* SN = ND->S.data();
            const float* bN = ND->b.data();
            for (int x = 0; x < N; ++x) {
                const int i = (N - 1) * N + x;
                const int j = 0 * N + x;
                const double mv =
                    faceMove(S, b, i, SN, bN, j,
                             GRAV_FLOW * (fs(S, b, i) - fs(SN, bN, j)) *
                                 dtS);
                maxMove = std::max(maxMove, mv);
                if (mv > 0)
                    ND->active = true;
            }
        } else {
            const auto tit =
                terrain_.pages().find(world::pageKey(p.px, p.pz + 1));
            const float* tN = (tit != terrain_.pages().end() &&
                               tit->second.built)
                                  ? tit->second.h.data()
                                  : nullptr;
            for (int x = 0; x < N; ++x) {
                const int i = (N - 1) * N + x;
                if (S[i] <= 0.0f)
                    continue;
                const double target = tN ? (double)tN[(size_t)1 * 67 + (x + 1)]
                                         : (double)b[i];
                const double t = std::clamp(
                    GRAV_FLOW * (S[i] + b[i] - target) * dtS, 0.0,
                    0.28 * (double)S[i]);
                if (t > 0)
                    maxMove = std::max(maxMove, t);
                S[i] = (float)std::max(0.0, (double)S[i] - t);
            }
        }
    }

    // rain / evaporation / storms on the domain.
    // thin water films are NOT force-dried: they must be removed by
    // evaporation only, so rain can accumulate and flow (streams)
    bool wet = false;
    for (int z = 0; z < N; ++z)
        for (int x = 0; x < N; ++x) {
            const int i = z * N + x;
            double s = S[i];
            if (b[i] > RAIN_ALT)
                s += RAIN_RATE * (double)rainBoost * dt;
            else
                s += DRIZZLE_RATE * dt; // constant light drizzle
            if (storm)
                s += STORM_RATE * (double)rainBoost * dt;
            if (s > 1e-6) {
                if (!storm)
                    s -= EVAP_RATE * dt;
                if (s <= 0.0)
                    s = 0.0;
                else if (s > WET_EPS)
                    wet = true;
            }
            S[i] = (float)s;
        }

    p.hasWater = wet;
    p.active = wet || p.active;
    p.dirty = wet && maxMove > 2e-4;
}

void Sim::step(double dt) {
    dt = std::clamp(dt, 0.0, 0.05);
    for (auto& [key, p] : pages_) {
        (void)key;
        if (p.hasWater || storm) {
            solvePage(p, dt);
            continue;
        }
        if (!p.active)
            continue; // nothing to do (page fully dry)
        // thin-film accumulation: cheap, no face sweeps
        bool nowWet = false;
        float* S = p.S.data();
        const float* b = p.b.data();
        for (int z = 0; z < N; ++z)
            for (int x = 0; x < N; ++x) {
                const int i = z * N + x;
                double s = S[i];
                if (b[i] > RAIN_ALT)
                    s += RAIN_RATE * (double)rainBoost * dt;
                else
                    s += DRIZZLE_RATE * dt;
                if (storm) // never here, but keep symmetric
                    s += STORM_RATE * (double)rainBoost * dt;
                if (s > 1e-6)
                    s -= EVAP_RATE * dt;
                if (s <= 0.0)
                    s = 0.0;
                else if (s > WET_EPS)
                    nowWet = true;
                S[i] = (float)s;
            }
        if (nowWet) {
            p.hasWater = true;
            p.dirty = true;
        }
    }
    for (auto& [key, p] : pages_) {
        (void)key;
        p.active = p.rainy || p.hasWater || p.dirty || storm;
    }
}

// ------------------------------------------------------------
// surface queries (player physics)
// ------------------------------------------------------------

float Sim::surfaceAt(double wx, double wz, float& depthOut) const {
    const double cx = wx / world::CELL;
    const double cz = wz / world::CELL;
    const int64_t x0 = (int64_t)std::floor(cx);
    const int64_t z0 = (int64_t)std::floor(cz);
    const double fx = cx - x0;
    const double fz = cz - z0;

    auto sample = [&](int64_t x, int64_t z) {
        const Cell c = cellAt(pages_, terrain_, x, z);
        return c;
    };

    const Cell s00 = sample(x0, z0);
    const Cell s10 = sample(x0 + 1, z0);
    const Cell s01 = sample(x0, z0 + 1);
    const Cell s11 = sample(x0 + 1, z0 + 1);
    if (!s00.valid || !s10.valid || !s01.valid || !s11.valid) {
        depthOut = 0;
        return (float)terrain_.heightAt(wx, wz);
    }
    auto mix2 = [fx, fz](const Cell& a, const Cell& c, const Cell& b,
                         const Cell& d) {
        const double top = (a.s + a.b) * (1 - fx) * (1 - fz) +
                           (b.s + b.b) * fx * (1 - fz) +
                           (c.s + c.b) * (1 - fx) * fz +
                           (d.s + d.b) * fx * fz;
        const double bot = a.b * (1 - fx) * (1 - fz) + b.b * fx * (1 - fz) +
                           c.b * (1 - fx) * fz + d.b * fx * fz;
        return std::pair<double, double>(top, bot);
    };
    const auto [top, bot] = mix2(s00, s01, s10, s11);
    depthOut = (float)std::max(0.0, top - bot);
    return (float)top;
}

// ------------------------------------------------------------
// CPU surface buffers for the renderer
// ------------------------------------------------------------

void Sim::rebuildSurfaces() {
    for (auto& [key, p] : pages_) {
        (void)key;
        if (!p.hasWater)
            continue;
        if (p.surfReady && !p.dirty)
            continue; // calm water: nothing changed since last upload
        p.surfReady = true;
        p.surf.assign((size_t)65 * 65 * 10, 0.0f);
        p.idx.clear();

        auto topAt = [&](int64_t c, int64_t r, float& topOut,
                         float& depthOut) -> bool {
            const Cell cell = cellAt(pages_, terrain_, c, r);
            if (!cell.valid)
                return false;
            topOut = cell.b + cell.s;
            depthOut = cell.s;
            return true;
        };

        const int64_t c0 = p.px * N;
        const int64_t r0 = p.pz * N;

        for (int vz = 0; vz < 65; ++vz)
            for (int vx = 0; vx < 65; ++vx) {
                float top = 0, depth = 0;
                if (!topAt(c0 + vx, r0 + vz, top, depth)) {
                    continue; // outside simulated area
                }
                const bool wet = depth > 0.004f;
                const double wx = world::colWorld(c0 + vx);
                const double wz = world::colWorld(r0 + vz);

                // slope & speed from the free-surface neighbours
                float tL = top, tR = top, tU = top, tD = top;
                topAt(c0 + vx - 1, r0 + vz, tL, depth);
                topAt(c0 + vx + 1, r0 + vz, tR, depth);
                topAt(c0 + vx, r0 + vz - 1, tU, depth);
                topAt(c0 + vx, r0 + vz + 1, tD, depth);
                const double dxs = (tR - tL) / (2.0 * world::CELL);
                const double dzs = (tD - tU) / (2.0 * world::CELL);
                const double speed = std::sqrt(dxs * dxs + dzs * dzs);
                glm::vec3 nrm(0, 1, 0);
                if (wet)
                    nrm = glm::normalize(glm::vec3((float)-dxs, 1.0f,
                                                   (float)-dzs));

                glm::vec3 shallow(0.22f, 0.42f, 0.38f);
                glm::vec3 deep(0.05f, 0.16f, 0.28f);
                glm::vec3 col =
                    glm::mix(shallow, deep,
                             std::clamp(depth / 1.8f, 0.0f, 1.0f));
                float alpha =
                    std::clamp(0.50f + depth * 0.35f, 0.42f, 0.92f);
                const float foam =
                    std::clamp((float)((speed - 0.06) / 0.30), 0.0f, 1.0f);
                col = glm::mix(col, glm::vec3(0.85f, 0.9f, 0.93f),
                               foam * 0.85f);
                alpha = glm::mix(alpha, 0.96f, foam * 0.5f);

                float* v = &p.surf[((size_t)vz * 65 + vx) * 10];
                v[0] = (float)wx;
                v[1] = wet ? top : (float)terrain::MIN_HEIGHT - 1.0f;
                v[2] = (float)wz;
                v[3] = nrm.x;
                v[4] = nrm.y;
                v[5] = nrm.z;
                v[6] = col.r;
                v[7] = col.g;
                v[8] = col.b;
                v[9] = wet ? alpha : 0.0f;
            }

        for (int vz = 0; vz < 64; ++vz)
            for (int vx = 0; vx < 64; ++vx) {
                bool any = false;
                for (int dz = 0; dz <= 1; ++dz)
                    for (int dx = 0; dx <= 1; ++dx) {
                        const float* v = &p.surf
                            [((size_t)(vz + dz) * 65 + vx + dx) * 10];
                        if (v[9] > 0.01f) {
                            any = true;
                            break;
                        }
                    }
                if (!any)
                    continue;
                const uint32_t a0 = (uint32_t)(vz * 65 + vx);
                p.idx.push_back(a0);
                p.idx.push_back(a0 + 1);
                p.idx.push_back(a0 + 66);
                p.idx.push_back(a0);
                p.idx.push_back(a0 + 66);
                p.idx.push_back(a0 + 65);
            }
        p.idx.shrink_to_fit();
    }
}

} // namespace water
