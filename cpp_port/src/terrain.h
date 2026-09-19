// ============================================================
// TERRAIN V2 - C++ port of "algoridmDereferinta.py"
//
// Realistic procedural terrain
//  - domain warp
//  - ridged mountains
//  - hills
//  - hydraulic droplet erosion (SAME droplet count 45 000)
//  - anti-spike filter
//  - thermal smoothing
//  - RELIEF x100: mountains amplified 100x taller above the
//    valley level (lakes/plains keep today's heights)
//
// Every constant keeps the value from the reference script.
// Single-threaded C++ => the same erosion finishes ~100x faster
// than the NumPy reference.
// ============================================================

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace terrain {

// ------------------------------------------------------------
// CONFIG (identical to the reference algorithm)
// ------------------------------------------------------------

// Runtime-settable world seed (BalloonWar chooses it from the menu).
// Set BEFORE generateTerrain()/baseHeightAt() so every stage agrees.
inline int SEED = 194423;

// BalloonWar Creator parameters, applied by baseHeightRaw().
// Defaults keep the reference "23 august 1944" look exactly.
inline double TERRAIN_SCALE = 1.0;    // terrain_frequency / 0.018
inline double WARP_STRENGTH = 250.0;  // menu value 5.0 -> 250
inline double LAND_CURVE = 1.0;       // terrain_curve / 0.7
inline double RIDGE_FACTOR = 1.0;     // ridge_strength / 0.8
inline double CUSTOM_MIN = -1e9;      // surface_min_height (clamp, -1e9 = off)
inline double CUSTOM_MAX = 1e9;       // surface_max_height

constexpr double WORLD_SIZE = 1000.0; // meters, -500..+500
constexpr int RESOLUTION = 513;

constexpr double MIN_HEIGHT = -80.0;
constexpr double MAX_HEIGHT = 500.0;

// ============================================================
// RELIEF amplifier (BalloonWar: natural mountain height)
//
// The raw terrain keeps today's shape everywhere below the
// valley level (spawn plains + lake basins), then smoothly
// grows to RELIEF_SCALE between VALLEY_TOP and
// VALLEY_TOP+VALLEY_RAMP. Everything at or above the top of the
// ramp is amplified by exactly RELIEF_SCALE times its height
// above the valley floor:
//
//   height' = VALLEY_TOP + (height - VALLEY_TOP) * RELIEF_SCALE
//             (full ramp: height >= VALLEY_TOP + VALLEY_RAMP)
//
// The reference project used 100 (kilometre-high mountains); the
// BalloonWar port defaults to 3.0 so ranges stay natural next to
// the plains (peaks around 1000-1500 m). It can be changed from
// the Creator menu (1.0 = raw reference shape).
// ============================================================
inline double RELIEF_SCALE = 3.0;   // 1.0 = raw, 3.0 = natural, 100 = reference
constexpr double VALLEY_TOP = 25.0; // valley level kept as-is (m)
constexpr double VALLEY_RAMP = 40.0; // smooth transition width (m)

// Terrain shape
constexpr double CONTINENT_SCALE = 5000.0;
constexpr double MOUNTAIN_RANGE_SCALE = 1800.0;
constexpr double MOUNTAIN_SCALE = 520.0;
constexpr int MOUNTAIN_OCTAVES = 5;
constexpr double RIDGE_SCALE = 180.0;
constexpr int RIDGE_OCTAVES = 5;
constexpr double HILL_SCALE = 300.0;
constexpr double DETAIL_SCALE = 70.0;
constexpr double MICRO_SCALE = 25.0;

// Rounded "boulder" mountains (dome shaping instead of sharp
// ridged peaks): threshold + smoothstep of a plain fbm stack.
constexpr double DOME_THRESHOLD = 0.43;
constexpr double DOME_WIDTH = 0.36;

// Domain warp
constexpr double WARP_SCALE = 1100.0;
// (WARP_STRENGTH is the runtime-settable variable declared above)

// Hydraulic erosion
constexpr bool ENABLE_EROSION = true;
constexpr int DROPLETS = 45000;
constexpr int DROPLET_LIFETIME = 32;
constexpr int EROSION_RADIUS = 3;
constexpr double INERTIA = 0.30;
constexpr double SEDIMENT_CAPACITY = 3.0;
constexpr double MIN_SEDIMENT_CAPACITY = 0.01;
constexpr double DEPOSIT_SPEED = 0.30;
constexpr double ERODE_SPEED = 0.22;
constexpr double EVAPORATE_SPEED = 0.015;
constexpr double GRAVITY = 4.0;
constexpr double START_SPEED = 1.0;
constexpr double START_WATER = 1.0;

// Anti spike
constexpr bool ANTI_SPIKE = true;
constexpr int SPIKE_ITERATIONS = 4;
constexpr double SPIKE_THRESHOLD = 8.0;
constexpr double SPIKE_STRENGTH = 0.65;

// Thermal
constexpr int THERMAL_ITERATIONS = 5;
constexpr double THERMAL_THRESHOLD = 5.0;
constexpr double THERMAL_STRENGTH = 0.12;

// Height sampling spacing between two neighbouring samples
constexpr double SPACING = WORLD_SIZE / (double)(RESOLUTION - 1);

// ------------------------------------------------------------
// Data
// ------------------------------------------------------------

struct HeightField {
    int size = RESOLUTION;
    // row major, index = y * size + x  (y = world z column)
    std::vector<float> h;

    float& at(int x, int y) { return h[(size_t)y * size + x]; }
    const float& at(int x, int y) const { return h[(size_t)y * size + x]; }

    // Bilinear sample of the field at a WORLD position (meters, -500..500)
    float heightAtWorld(double wx, double wz) const;
};

// Continuous base-terrain height at ANY world position (infinite
// terrain). Same formula as the reference algorithm, but evaluated
// per point, so the plane is seamless and unbounded. The returned
// height already includes the RELIEF_SCALE (x100) amplification of
// the relief above the valley level.
double baseHeightAt(double wx, double wz);

// Relief amplifier: height' = VALLEY_TOP + (height-VALLEY_TOP)*100
// for height >= VALLEY_TOP+VALLEY_RAMP, smooth between the valley
// top and the ramp top, identity below the valley level.
double amplifyRelief(double h);

// Initial standing-water profile for the closed basins carved by
// baseHeightAt().  Water simulation uses this to start those basins as real
// ponds instead of waiting many minutes for drizzle to fill them.
double initialWaterDepthAt(double wx, double wz);

// Rounded dome shape used by the mountains (boulder-like hills)
double domeField(double x, double y, double scale, int octaves);

// ------------------------------------------------------------
// Pipeline (prints the same progress text as the reference)
// ------------------------------------------------------------

// Runs the whole reference pipeline:
// base -> hydraulic(45 000 droplets) -> anti spike -> thermal ->
// edges -> clip. Returns the final eroded field.
HeightField generateTerrain();

// Stage helpers (exposed for tests / custom pipelines)
void generateBaseHeightmap(HeightField& out);
void hydraulicErosion(HeightField& out);
void removeSpikes(HeightField& out);
void thermalErosion(HeightField& out);
void protectEdges(HeightField& out);

// Reference hydraulic droplets applied to a square tile of
// `size` columns (with a 1-column ring when used by the paged
// world). Writes only happen inside the tile's own domain, so
// independent tiles stay consistent. seed -> deterministic.
void erodeTile(std::vector<float>& grid, int size, int droplets,
               std::uint64_t seed);

} // namespace terrain
