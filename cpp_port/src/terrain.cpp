// ============================================================
// Terrain V2 implementation - faithful C++ port of the
// NumPy/Blender reference algorithm.
//
// Noise/hash arithmetic is reproduced bit-for-bit where the
// reference is bit-exact (int64 hash wraps like NumPy int64),
// so the base terrain SHAPE is identical to the reference.
//
// RELIEF x100: the shape generated below is the reference one,
// then amplifyRelief() raises the mountains to be 100x taller
// (the valley floors/lakes keep their level - see terrain.h).
// ============================================================

#include "terrain.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <random>
#include <string>

namespace terrain {

namespace {

// Wrap semantics of a signed 64 bit multiplication (NumPy int64):
// two's complement wrapping is the same as unsigned multiplication.
inline std::uint64_t mulWrap(std::int64_t a, std::int64_t b) {
    return static_cast<std::uint64_t>(a) * static_cast<std::uint64_t>(b);
}

// ------------------------------------------------------------
// Deterministic value hash  (reference: hash_grid)
// n = x*374761393 + y*668265263 + SEED*1442695041   (int64)
// n ^= n >> 13; n *= 1274126177; n ^= n >> 16
// returns low 32 bits as [0,1)
//
// Performed on uint64: wrapping modulo 2^64 is identical to the
// int64 wrap of NumPy, and the difference between arithmetic and
// logical right shifts only ever touches bits >= 51, which are
// annihilated by the multiplication (2^13 | 1274126177 * 8191 ...),
// so the returned low 32 bits match NumPy exactly.
// ------------------------------------------------------------
inline double hashGrid(std::int64_t x, std::int64_t y) {
    std::uint64_t n = mulWrap(x, 374761393) + mulWrap(y, 668265263) +
                      mulWrap(SEED, 1442695041);
    n ^= n >> 13;
    n *= 1274126177ULL;
    n ^= n >> 16;
    return static_cast<double>(n & 0xffffffffULL) / 4294967295.0;
}

inline int64_t floorLL(double v) { return static_cast<int64_t>(std::floor(v)); }

// Reference 2D value noise: (x,y) coordinates, scale in meters.
// Returns [0,1]
inline double noise2(double x, double y, double scale) {
    const double px = x / scale;
    const double py = y / scale;

    const int64_t ix = floorLL(px);
    const int64_t iy = floorLL(py);

    const double fx = px - static_cast<double>(ix);
    const double fy = py - static_cast<double>(iy);

    const double u = fx * fx * (3.0 - 2.0 * fx);
    const double v = fy * fy * (3.0 - 2.0 * fy);

    // gradient from hash index (8 directions, reference GRADS)
    const double gx[4] = {fx, fx - 1.0, fx, fx - 1.0};
    const double gy[4] = {fy, fy, fy - 1.0, fy - 1.0};
    const int64_t gxIdx[4] = {ix, ix + 1, ix, ix + 1};
    const int64_t gyIdx[4] = {iy, iy, iy + 1, iy + 1};

    double n[4];
    for (int c = 0; c < 4; ++c) {
        const double hf = hashGrid(gxIdx[c], gyIdx[c]) * 8.0;
        const int64_t hi = static_cast<int64_t>(hf) % 8;
        double grX, grY;
        switch (hi) { // reference GRADS table
            case 0: grX = 1.0; grY = 0.0; break;
            case 1: grX = -1.0; grY = 0.0; break;
            case 2: grX = 0.0; grY = 1.0; break;
            case 3: grX = 0.0; grY = -1.0; break;
            case 4: grX = 0.707106; grY = 0.707106; break;
            case 5: grX = -0.707106; grY = 0.707106; break;
            case 6: grX = 0.707106; grY = -0.707106; break;
            default: grX = -0.707106; grY = -0.707106; break;
        }
        n[c] = grX * gx[c] + grY * gy[c];
    }

    const double nx0 = n[0] + (n[1] - n[0]) * u;
    const double nx1 = n[2] + (n[3] - n[2]) * u;
    return (nx0 + (nx1 - nx0) * v) * 0.5 + 0.5;
}

// Fractional brownian motion (reference fbm)
inline double fbm(double x, double y, double scale, int octaves,
                  double persistence = 0.5, double lacunarity = 2.0) {
    double result = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double total = 0.0;

    for (int i = 0; i < octaves; ++i) {
        result += noise2(x * frequency, y * frequency, scale) * amplitude;
        total += amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return result / total;
}

inline double smoothstepEdge(double v) {
    return v * v * (3.0 - 2.0 * v);
}

constexpr double LAKE_SITES[][2] = {
    {90, 40},    {-55, 85},    {45, -80},   {-85, -45},
    {170, -20},  {150, 60},    {-120, 110}, {60, -160},
    {-170, -90}, {280, -40},   {60, 260},   {-260, 150},
    {330, 180},  {-90, 300},   {240, -300}, {820, -380},
    {-780, -420}, {900, 140},
};

// ------------------------------------------------------------
// ROUNDED BOULDER MOUNTAINS
//
// A stack of plain fbm is smooth and rolling (rounded crests).
// Sharp pyramids came from the ridged crests; here every high
// noise area is cut out and smoothed into a dome silhouette,
// which reads as big round boulders.
// ------------------------------------------------------------
} // namespace

// ============================================================
// HEIGHT FIELD SAMPLING
// ============================================================

double domeField(double x, double y, double scale, int octaves) {
    const double n = fbm(x, y, scale, octaves, 0.5, 2.0);
    double t = (n - DOME_THRESHOLD) / DOME_WIDTH;
    t = std::clamp(t, 0.0, 1.0);
    t = smoothstepEdge(t);
    // widen + round the top of each dome
    return std::sin(t * 3.14159265358979323846 * 0.5);
}

double initialWaterDepthAt(double wx, double wz) {
    double depth = 0.0;
    for (const auto& site : LAKE_SITES) {
        const double dx = wx - site[0];
        const double dz = wz - site[1];
        const double d = std::sqrt(dx * dx + dz * dz);
        if (d >= 34.0)
            continue;
        // Broad, deep-enough starting ponds.  The shallow-water solver then
        // levels this volume against the actual eroded basin floor.
        const double t = smoothstepEdge(1.0 - d / 34.0);
        depth = std::max(depth, 0.08 + 2.15 * t);
    }
    return depth;
}

// one height sample of the un-eroded base terrain at a world point
// (RAW metres, same values as the reference algorithm - no relief
// amplification yet, the erosion/filter stages run on these values)
double baseHeightRaw(double wx, double wz) {
    const double X = wx * TERRAIN_SCALE;
    const double Y = wz * TERRAIN_SCALE;

    // ---- Domain warp ----
    const double wx_ = fbm(X + 7000.0, Y - 4000.0, WARP_SCALE, 3);
    const double wy_ = fbm(X - 5000.0, Y + 8000.0, WARP_SCALE, 3);

    const double Xw = X + (wx_ - 0.5) * 2.0 * WARP_STRENGTH;
    const double Yw = Y + (wy_ - 0.5) * 2.0 * WARP_STRENGTH;

    // ---- Continents ----
    const double continent = fbm(Xw, Yw, CONTINENT_SCALE, 5, 0.55, 2.0);
    double land = std::clamp((continent - 0.37) / 0.23, 0.0, 1.0);
    land = smoothstepEdge(land);
    if (LAND_CURVE != 1.0)
        land = std::pow(land, LAND_CURVE);

    // ---- Mountain range mask ----
    const double ranges =
        fbm(Xw + 3000.0, Yw - 1800.0, MOUNTAIN_RANGE_SCALE, 4, 0.55);
    double mountainMask = std::clamp((ranges - 0.44) / 0.20, 0.0, 1.0);
    mountainMask = smoothstepEdge(mountainMask);

    // ---- ROUNDED boulder mountains (was: sharp ridged) ----
    const double domes = domeField(Xw, Yw, MOUNTAIN_SCALE, MOUNTAIN_OCTAVES);
    const double stones = domeField(Xw + 1400.0, Yw - 2300.0, RIDGE_SCALE,
                                    RIDGE_OCTAVES);

    // ---- Hills ----
    double hills = fbm(Xw - 4000.0, Yw + 3000.0, HILL_SCALE, 4, 0.5);
    hills = std::max(hills - 0.42, 0.0);

    // ---- Detail ----
    const double detail =
        fbm(Xw + 8000.0, Yw - 6000.0, DETAIL_SCALE, 4, 0.48) - 0.5;
    const double micro =
        fbm(Xw - 9000.0, Yw + 2000.0, MICRO_SCALE, 3, 0.48) - 0.5;

    // ---- Combine (reference mix) ----
    double height = (continent - 0.45) * 65.0;
    height += hills * 95.0 * (1.0 - mountainMask * 0.7);
    height += domes * 340.0 * RIDGE_FACTOR * mountainMask;
    height += stones * 90.0 * RIDGE_FACTOR * mountainMask;
    height += detail * 22.0;
    height += micro * 6.0;
    height *= (0.40 + land * 0.60);

    // ---- Lowland ----
    const double lowland = std::clamp((0.13 - land) / 0.13, 0.0, 1.0);
    height -= lowland * 55.0;

    // ---- closed lake basins (guaranteed ponds all over the world) ----
    // fixed world sites: near spawn at several directions + mountains
    for (const auto& s2 : LAKE_SITES) {
        const double dx = X - s2[0];
        const double dz = Y - s2[1];
        const double d2 = dx * dx + dz * dz;
        const double d = std::sqrt(d2);
        if (d > 68.0)
            continue;
        // bowl (deep centre)
        if (d < 36.0) {
            const double w = 1.0 - d / 36.0;
            height -= 4.2 * w * w;
        }
        // surrounding rim so the lake cannot drain away on slopes
        if (d > 28.0) {
            const double t = std::clamp((d - 28.0) / 40.0, 0.0, 1.0);
            height += 2.8 * t * t * (3.0 - 2.0 * t);
        }
    }

    if (CUSTOM_MIN > -1e8 || CUSTOM_MAX < 1e8)
        height = std::clamp(height, CUSTOM_MIN, CUSTOM_MAX);
    return std::clamp(height, MIN_HEIGHT, MAX_HEIGHT);
}

// ------------------------------------------------------------
// RELIEF x100: mountains one hundred times taller.
//
// Values at or below the valley level (spawn plains, lake basins)
// keep today's look. Above it a smooth cubic ramp raises the
// factor from 1x to RELIEF_SCALE across VALLEY_RAMP metres, so at
// the top the relief is amplified by exactly RELIEF_SCALE times:
//
//   h' = VALLEY_TOP + (h - VALLEY_TOP) * RELIEF_SCALE
//
// The function is monotone and C1 (smooth) everywhere.
// ------------------------------------------------------------
double amplifyRelief(double h) {
    if (h <= VALLEY_TOP)
        return h;

    double t = (h - VALLEY_TOP) / VALLEY_RAMP;
    t = std::clamp(t, 0.0, 1.0);
    t = smoothstepEdge(t); // cubic ramp 0..1 across the valley rim

    // factor goes 1x (valley floor) -> RELIEF_SCALE (mountain base)
    const double f = 1.0 + (RELIEF_SCALE - 1.0) * t;
    return h + (h - VALLEY_TOP) * (f - 1.0);
}

// public height field: raw reference terrain + the relief x100
double baseHeightAt(double wx, double wz) {
    return amplifyRelief(baseHeightRaw(wx, wz));
}



float HeightField::heightAtWorld(double wx, double wz) const {
    const double x = wx / SPACING + (double)(size - 1) * 0.5;
    const double y = wz / SPACING + (double)(size - 1) * 0.5;

    const double cx = std::clamp(x, 0.0, (double)size - 1.001);
    const double cy = std::clamp(y, 0.0, (double)size - 1.001);

    const int x0 = static_cast<int>(std::floor(cx));
    const int y0 = static_cast<int>(std::floor(cy));
    const int x1 = x0 + 1;
    const int y1 = y0 + 1;

    const double fx = cx - x0;
    const double fy = cy - y0;

    const float h00 = at(x0, y0);
    const float h10 = at(x1, y0);
    const float h01 = at(x0, y1);
    const float h11 = at(x1, y1);

    return static_cast<float>(
        h00 * (1.0 - fx) * (1.0 - fy) + h10 * fx * (1.0 - fy) +
        h01 * (1.0 - fx) * fy + h11 * fx * fy);
}

// ============================================================
// BASE TERRAIN
// ============================================================

void generateBaseHeightmap(HeightField& out) {
    const int n = out.size;
    out.h.assign((size_t)n * n, 0.0f);

    std::printf("Generating base terrain...\n");

    const double axis0 = -WORLD_SIZE * 0.5;

    for (int row = 0; row < n; ++row) {
        const double Y = axis0 + SPACING * row;

        for (int col = 0; col < n; ++col) {
            const double X = axis0 + SPACING * col;
            out.at(col, row) =
                static_cast<float>(baseHeightRaw(X, Y));
        }
    }
}

// ============================================================
// HYDRAULIC DROPLET EROSION (45 000 droplets - same as reference)
// ============================================================

void hydraulicErosion(HeightField& out) {
    const int n = out.size;
    const int radius = EROSION_RADIUS;

    // brush cells (same construction as the reference)
    struct BrushCell {
        int bx, by;
        double weight;
    };
    std::vector<BrushCell> brush;
    double weightSum = 0.0;
    for (int by = -radius; by <= radius; ++by) {
        for (int bx = -radius; bx <= radius; ++bx) {
            const double dist = std::sqrt((double)(bx * bx + by * by));
            if (dist <= radius) {
                const double w = radius - dist + 0.01;
                brush.push_back({bx, by, w});
                weightSum += w;
            }
        }
    }
    for (auto& b : brush)
        b.weight /= weightSum;

    std::printf("\nHydraulic droplet erosion...\n");
    std::printf("  droplets : %d x lifetime %d (same as the reference)\n",
                DROPLETS, DROPLET_LIFETIME);

    std::mt19937_64 rng(SEED);
    auto rng01 = [&rng]() {
        return static_cast<double>(rng() >> 11) * (1.0 / 9007199254740992.0);
    };

    // samples (x,y coordinates inside the grid, like the reference)
    auto sampleHeight = [n](const HeightField& h, double x, double y) {
        x = std::clamp(x, 0.0, (double)n - 1.001);
        y = std::clamp(y, 0.0, (double)n - 1.001);
        const int x0 = static_cast<int>(std::floor(x));
        const int y0 = static_cast<int>(std::floor(y));
        const int x1 = x0 + 1;
        const int y1 = y0 + 1;
        const double fx = x - x0;
        const double fy = y - y0;
        const double h00 = h.at(x0, y0);
        const double h10 = h.at(x1, y0);
        const double h01 = h.at(x0, y1);
        const double h11 = h.at(x1, y1);
        return h00 * (1.0 - fx) * (1.0 - fy) + h10 * fx * (1.0 - fy) +
               h01 * (1.0 - fx) * fy + h11 * fx * fy;
    };

    HeightField work = out;
    // work is float; reference works on float32 during erosion as well

    const int margin = radius + 3;

    for (int d = 0; d < DROPLETS; ++d) {
        double x = margin + rng01() * (double)(n - 2 * margin - 1);
        double y = margin + rng01() * (double)(n - 2 * margin - 1);

        double dirX = 0.0, dirY = 0.0;
        double speed = START_SPEED;
        double water = START_WATER;
        double sediment = 0.0;

        for (int step = 0; step < DROPLET_LIFETIME; ++step) {
            const int cx = static_cast<int>(x);
            const int cy = static_cast<int>(y);

            if (cx < 1 || cx >= n - 2 || cy < 1 || cy >= n - 2)
                break;

            const double hc = work.at(cx, cy);
            const double hl = work.at(cx - 1, cy);
            const double hr = work.at(cx + 1, cy);
            const double hu = work.at(cx, cy - 1);
            const double hd = work.at(cx, cy + 1);

            const double gx = (hr - hl) * 0.5;
            const double gy = (hd - hu) * 0.5;

            // direction with inertia
            dirX = dirX * INERTIA - gx * (1.0 - INERTIA);
            dirY = dirY * INERTIA - gy * (1.0 - INERTIA);

            double len = std::sqrt(dirX * dirX + dirY * dirY);
            if (len < 0.00001) {
                const double angle = rng01() * 2.0 * 3.14159265358979323846;
                dirX = std::cos(angle);
                dirY = std::sin(angle);
            } else {
                dirX /= len;
                dirY /= len;
            }

            x += dirX;
            y += dirY;

            if (x < margin || x >= n - margin - 1 || y < margin ||
                y >= n - margin - 1)
                break;

            const double newH = sampleHeight(work, x, y);
            const double dh = newH - hc;

            if (dh < 0.0) {
                // ---- fell downhill ----
                speed = std::sqrt(
                    std::max(0.01, speed * speed - dh * GRAVITY));

                const double capacity = std::max(
                    -dh * speed * water * SEDIMENT_CAPACITY,
                    MIN_SEDIMENT_CAPACITY);

                if (sediment > capacity) {
                    double amount =
                        (sediment - capacity) * DEPOSIT_SPEED;
                    amount = std::min(amount, 2.0);
                    work.at(cx, cy) += static_cast<float>(amount);
                    sediment -= amount;
                } else {
                    double amount = (capacity - sediment) * ERODE_SPEED;
                    amount = std::min(amount, 1.5);
                    amount *= water;

                    // brush erosion (same weights as the reference)
                    double eroded = 0.0;
                    for (const auto& b : brush) {
                        const int px = cx + b.bx;
                        const int py = cy + b.by;
                        if (px < 1 || px >= n - 1 || py < 1 || py >= n - 1)
                            continue;

                        double a = amount * b.weight;
                        const double available =
                            std::max(0.0, (double)work.at(px, py) - MIN_HEIGHT);
                        a = std::min(a, available);

                        work.at(px, py) -= static_cast<float>(a);
                        eroded += a;
                    }
                    sediment += eroded;
                }
            } else {
                // ---- climbed uphill -> deposit ----
                double deposit =
                    std::min(sediment, dh * 0.5 + 0.001);
                deposit *= DEPOSIT_SPEED * 2.0;
                deposit = std::min(deposit, 2.0);

                work.at(cx, cy) += static_cast<float>(deposit);
                sediment -= deposit;

                speed = std::max(0.1, speed * 0.5);
            }

            // evaporation
            water *= (1.0 - EVAPORATE_SPEED);
            if (water < 0.01)
                break;
        }

        // final deposition
        if (sediment > 0.0) {
            const int cx = static_cast<int>(std::clamp(x, 1.0, (double)n - 2));
            const int cy = static_cast<int>(std::clamp(y, 1.0, (double)n - 2));
            const double amount = std::min(sediment, 2.0);
            work.at(cx, cy) += static_cast<float>(amount);
        }

        if (d % 5000 == 0 && d > 0)
            std::printf("  %d/%d\n", d, DROPLETS);
    }

    out = std::move(work);
}

// ============================================================
// ANTI SPIKE FILTER  (same wraps, iterations, strength)
// ============================================================

void removeSpikes(HeightField& out) {
    const int n = out.size;
    HeightField h = out;

    for (int it = 0; it < SPIKE_ITERATIONS; ++it) {
        HeightField next = h;
        for (int y = 0; y < n; ++y) {
            const int yn = (y - 1 + n) % n; // np.roll(-1, axis=0) is up?
            const int ys = (y + 1) % n;
            for (int x = 0; x < n; ++x) {
                // reference: roll(-1) then average north/south/east/west
                const double north = h.at(x, yn); // roll -1 axis 0
                const double south = h.at(x, ys);
                const double east = h.at((x - 1 + n) % n, y);
                const double west = h.at((x + 1) % n, y);
                const double average = (north + south + east + west) * 0.25;
                const double diff = (double)h.at(x, y) - average;
                if (std::abs(diff) > SPIKE_THRESHOLD) {
                    next.at(x, y) -= static_cast<float>(diff * SPIKE_STRENGTH);
                }
            }
        }
        h = std::move(next);
    }
    out = std::move(h);
}

// ============================================================
// THERMAL EROSION
// ============================================================

void thermalErosion(HeightField& out) {
    const int n = out.size;
    HeightField h = out;

    for (int it = 0; it < THERMAL_ITERATIONS; ++it) {
        // amount[x,y] = max(0, diff - threshold) * strength
        std::vector<float> amount((size_t)n * n, 0.0f);

        for (int y = 0; y < n; ++y) {
            const int yn = (y - 1 + n) % n;
            const int ys = (y + 1) % n;
            for (int x = 0; x < n; ++x) {
                const double north = h.at(x, yn);
                const double south = h.at(x, ys);
                const double east = h.at((x - 1 + n) % n, y);
                const double west = h.at((x + 1) % n, y);
                const double average = (north + south + east + west) * 0.25;
                const double diff = (double)h.at(x, y) - average;
                if (diff > THERMAL_THRESHOLD) {
                    amount[(size_t)y * n + x] = static_cast<float>(
                        (diff - THERMAL_THRESHOLD) * THERMAL_STRENGTH);
                }
            }
        }

        HeightField next = h;
        auto rollShift = [n](int idx, int shift) {
            return (idx + shift % n + n) % n;
        };

        for (int y = 0; y < n; ++y) {
            for (int x = 0; x < n; ++x) {
                float a = amount[(size_t)y * n + x];
                float nv = (float)next.at(x, y) - a;

                // redistribute 0.25 to each of the 4 neighbours
                nv += amount[(size_t)rollShift(y, 1) * n + x] * 0.25f; // roll 1
                nv += amount[(size_t)rollShift(y, -1) * n + x] * 0.25f;
                nv += amount[(size_t)y * n + rollShift(x, 1)] * 0.25f;
                nv += amount[(size_t)y * n + rollShift(x, -1)] * 0.25f;

                next.at(x, y) = nv;
            }
        }
        h = std::move(next);
    }
    out = std::move(h);
}

// ============================================================
// EDGE PROTECTION
// ============================================================

void protectEdges(HeightField& out) {
    const int n = out.size;
    for (int x = 0; x < n; ++x) {
        out.at(x, 0) = out.at(x, 1);
        out.at(x, n - 1) = out.at(x, n - 2);
    }
    for (int y = 0; y < n; ++y) {
        out.at(0, y) = out.at(1, y);
        out.at(n - 1, y) = out.at(n - 2, y);
    }
}

// ============================================================
// FULL PIPELINE
// ============================================================

HeightField generateTerrain() {
    using namespace std::chrono;
    const auto t0 = high_resolution_clock::now();
    auto elapsedSince = [&t0]() {
        return duration_cast<milliseconds>(high_resolution_clock::now() - t0)
            .count() /
               1000.0;
    };

    std::printf("\n");
    std::printf("==================================================\n");
    std::printf("       REALISTIC TERRAIN V2  (C++ / OpenGL port)\n");
    std::printf("       DROPLET HYDRAULIC EROSION\n");
    std::printf("==================================================\n");

    HeightField heightmap;
    heightmap.size = RESOLUTION;

    generateBaseHeightmap(heightmap);

    if (ENABLE_EROSION) {
        std::printf("  (%.2f s so far)\n", elapsedSince());
        hydraulicErosion(heightmap);
    }
    if (ANTI_SPIKE) {
        std::printf("Removing erosion spikes...\n");
        removeSpikes(heightmap);
    }
    std::printf("Thermal erosion...\n");
    thermalErosion(heightmap);
    protectEdges(heightmap);

    for (auto& v : heightmap.h)
        v = std::clamp(v, (float)MIN_HEIGHT, (float)MAX_HEIGHT);

    // RELIEF x100: amplify the finished (eroded + smoothed) field.
    // Filters above ran on raw metre-scale values, so the reference
    // shape stays intact - only the vertical amplitude grows.
    for (auto& v : heightmap.h)
        v = (float)amplifyRelief(v);

    const double elapsed = elapsedSince();

    std::printf("\n");
    std::printf("==================================================\n");
    std::printf("DONE\n");
    std::printf("Time: %.2f seconds (reference Blender: minutes)\n",
                elapsed);
    std::printf("Resolution: %d x %d\n", RESOLUTION, RESOLUTION);
    std::printf("Vertices: %d\n", RESOLUTION * RESOLUTION);
    std::printf("Droplets: %d\n", DROPLETS);
    std::printf("==================================================\n");

    return heightmap;
}

} // namespace terrain

// ============================================================
// per-tile hydraulic erosion (infinite world pages)
//
// The same droplet physics as the reference pipeline, but sized
// to one 67x67 tile (65 domain columns + 1 ring used as read
// context). Droplets never write to the ring, so the eroded
// result of a column is defined by exactly one page.
// ============================================================

namespace terrain {

void erodeTile(std::vector<float>& grid, int size, int droplets,
               std::uint64_t seed) {
    std::mt19937_64 rng(seed);
    auto rng01 = [&rng]() {
        return static_cast<double>(rng() >> 11) * (1.0 / 9007199254740992.0);
    };

    struct BrushCell {
        int bx, by;
        double weight;
    };
    std::vector<BrushCell> brush;
    double weightSum = 0.0;
    for (int by = -EROSION_RADIUS; by <= EROSION_RADIUS; ++by)
        for (int bx = -EROSION_RADIUS; bx <= EROSION_RADIUS; ++bx) {
            const double dist = std::sqrt((double)(bx * bx + by * by));
            if (dist <= EROSION_RADIUS) {
                const double w = EROSION_RADIUS - dist + 0.01;
                brush.push_back({bx, by, w});
                weightSum += w;
            }
        }
    for (auto& b : brush)
        b.weight /= weightSum;

    const int margin = EROSION_RADIUS + 3;

    auto sample = [&grid, size](double x, double y) {
        x = std::clamp(x, 0.0, (double)size - 1.001);
        y = std::clamp(y, 0.0, (double)size - 1.001);
        const int x0 = (int)std::floor(x);
        const int y0 = (int)std::floor(y);
        const int x1 = x0 + 1;
        const int y1 = y0 + 1;
        const double fx = x - x0;
        const double fy = y - y0;
        const double h00 = grid[(size_t)y0 * size + x0];
        const double h10 = grid[(size_t)y0 * size + x1];
        const double h01 = grid[(size_t)y1 * size + x0];
        const double h11 = grid[(size_t)y1 * size + x1];
        return h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) +
               h01 * (1 - fx) * fy + h11 * fx * fy;
    };

    for (int d = 0; d < droplets; ++d) {
        double x = margin + rng01() * (double)(size - 2 * margin - 1);
        double y = margin + rng01() * (double)(size - 2 * margin - 1);

        double dirX = 0, dirY = 0;
        double speed = START_SPEED;
        double water = START_WATER;
        double sediment = 0.0;

        for (int step = 0; step < DROPLET_LIFETIME; ++step) {
            const int cx = (int)x;
            const int cy = (int)y;
            if (cx < 1 || cx >= size - 2 || cy < 1 || cy >= size - 2)
                break;

            const double hc = grid[(size_t)cy * size + cx];
            const double hL = grid[(size_t)cy * size + cx - 1];
            const double hR = grid[(size_t)cy * size + cx + 1];
            const double hU = grid[(size_t)(cy - 1) * size + cx];
            const double hD = grid[(size_t)(cy + 1) * size + cx];

            dirX = dirX * INERTIA - (hR - hL) * 0.5 * (1.0 - INERTIA);
            dirY = dirY * INERTIA - (hD - hU) * 0.5 * (1.0 - INERTIA);

            double len = std::sqrt(dirX * dirX + dirY * dirY);
            if (len < 0.00001) {
                const double angle = rng01() * 2.0 * 3.141592653589793;
                dirX = std::cos(angle);
                dirY = std::sin(angle);
            } else {
                dirX /= len;
                dirY /= len;
            }

            x += dirX;
            y += dirY;
            if (x < margin || x >= size - margin - 1 || y < margin ||
                y >= size - margin - 1)
                break;

            const double dh = sample(x, y) - hc;

            if (dh < 0.0) {
                speed = std::sqrt(std::max(0.01, speed * speed - dh * GRAVITY));
                const double capacity = std::max(
                    -dh * speed * water * SEDIMENT_CAPACITY,
                    MIN_SEDIMENT_CAPACITY);
                if (sediment > capacity) {
                    double amount = std::min((sediment - capacity) *
                                                 DEPOSIT_SPEED,
                                             2.0);
                    grid[(size_t)cy * size + cx] += (float)amount;
                    sediment -= amount;
                } else {
                    double amount = std::min((capacity - sediment) *
                                                 ERODE_SPEED,
                                             1.5) *
                                    water;
                    double eroded = 0.0;
                    for (const auto& b : brush) {
                        const int px = cx + b.bx;
                        const int py = cy + b.by;
                        if (px < 1 || px >= size - 1 || py < 1 ||
                            py >= size - 1)
                            continue;
                        double a = amount * b.weight;
                        const double available =
                            std::max(0.0,
                                     (double)grid[(size_t)py * size + px] -
                                         MIN_HEIGHT);
                        a = std::min(a, available);
                        grid[(size_t)py * size + px] -= (float)a;
                        eroded += a;
                    }
                    sediment += eroded;
                }
            } else {
                double deposit = std::min(sediment, dh * 0.5 + 0.001) *
                                 (DEPOSIT_SPEED * 2.0);
                deposit = std::min(deposit, 2.0);
                grid[(size_t)cy * size + cx] += (float)deposit;
                sediment -= deposit;
                speed = std::max(0.1, speed * 0.5);
            }

            water *= (1.0 - EVAPORATE_SPEED);
            if (water < 0.01)
                break;
        }

        if (sediment > 0.0) {
            const int cx =
                (int)std::clamp(x, 1.0, (double)size - 2);
            const int cy =
                (int)std::clamp(y, 1.0, (double)size - 2);
            grid[(size_t)cy * size + cx] +=
                (float)std::min(sediment, 2.0);
        }
    }
}

} // namespace terrain
