#include "game.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <glm/gtc/matrix_transform.hpp>
#include <nlohmann/json.hpp>
#include <random>

namespace bw {

using nlohmann::json;
namespace fs = std::filesystem;

// ============================================================
// blocks
// ============================================================

const int kBlockOrder[kInventorySlots] = {GRASS, DIRT, STONE, COAL, IRON,
                                          COPPER, GOLD, DIAMOND, WOOD, LEAF};

const char* blockName(int type) {
    switch (type) {
        case GRASS: return "GRASS";
        case DIRT: return "DIRT";
        case STONE: return "STONE";
        case COAL: return "COAL";
        case IRON: return "IRON";
        case COPPER: return "COPPER";
        case GOLD: return "GOLD";
        case DIAMOND: return "DIAMOND";
        case WOOD: return "WOOD";
        case LEAF: return "LEAF";
        default: return "AIR";
    }
}

glm::vec3 blockColor(int type) {
    switch (type) {
        case GRASS: return {0.28f, 0.70f, 0.24f};
        case DIRT: return {0.58f, 0.40f, 0.24f};
        case STONE: return {0.52f, 0.52f, 0.52f};
        case COAL: return {0.12f, 0.12f, 0.12f};
        case IRON: return {0.72f, 0.72f, 0.78f};
        case COPPER: return {0.78f, 0.48f, 0.30f};
        case GOLD: return {0.90f, 0.78f, 0.18f};
        case DIAMOND: return {0.35f, 0.85f, 0.95f};
        case WOOD: return {0.50f, 0.30f, 0.15f};
        case LEAF: return {0.15f, 0.55f, 0.15f};
        default: return {0.52f, 0.52f, 0.52f};
    }
}

// ============================================================
// terrain helpers
// ============================================================

double rawRelief(double h) {
    const double VTOP = 25.0;
    const double RAMP = 40.0;
    const double TOP = VTOP + RAMP;
    const double FULL = VTOP + RAMP * terrain::RELIEF_SCALE;
    if (h <= VTOP)
        return h;
    if (h >= FULL)
        return VTOP + (h - VTOP) / terrain::RELIEF_SCALE;
    // invert the smooth ramp with a few Newton steps
    double r = VTOP + (h - VTOP) / terrain::RELIEF_SCALE;
    for (int i = 0; i < 8; ++i) {
        r = std::max(r, VTOP);
        double t = std::clamp((r - VTOP) / RAMP, 0.0, 1.0);
        double s = t * t * (3.0 - 2.0 * t);
        double f = r + (r - VTOP) * (terrain::RELIEF_SCALE - 1.0) * s;
        double df = 1.0 + (terrain::RELIEF_SCALE - 1.0) *
                              (s + (r - VTOP) * 6.0 * t * (1.0 - t) / RAMP);
        r -= (f - h) / df;
    }
    (void)TOP;
    return r;
}

namespace {

inline double hash01(int64_t x, int64_t y, int seed) {
    uint64_t n = (uint64_t)x * 374761393ULL + (uint64_t)y * 668265263ULL +
                 (uint64_t)(uint32_t)seed * 1442695041ULL;
    n ^= n >> 13;
    n *= 1274126177ULL;
    n ^= n >> 16;
    return (double)(n & 0xffffffffULL) / 4294967295.0;
}

inline double valueNoise(double x, double y, int seed) {
    const int64_t ix = (int64_t)std::floor(x);
    const int64_t iy = (int64_t)std::floor(y);
    const double fx = x - (double)ix;
    const double fy = y - (double)iy;
    const double u = fx * fx * (3.0 - 2.0 * fx);
    const double v = fy * fy * (3.0 - 2.0 * fy);
    const double a = hash01(ix, iy, seed);
    const double b = hash01(ix + 1, iy, seed);
    const double c = hash01(ix, iy + 1, seed);
    const double d = hash01(ix + 1, iy + 1, seed);
    const double top = a + (b - a) * u;
    const double bot = c + (d - c) * u;
    return top + (bot - top) * v;
}

} // namespace

int biomeAt(const world::TerrainSurface& t, const WorldConfig& cfg, double wx,
            double wz) {
    const double h = t.heightAt(wx, wz);
    if (h < WATER_LEVEL)
        return BIOME_OCEAN;
    const double raw = rawRelief(h);
    // slope from finite differences on the surface
    const double d = 4.0;
    const double hx = t.heightAt(wx + d, wz) - t.heightAt(wx - d, wz);
    const double hz = t.heightAt(wx, wz + d) - t.heightAt(wx, wz - d);
    const double slope = std::sqrt(hx * hx + hz * hz) / (2.0 * d);

    if (raw > 330.0)
        return BIOME_SNOW;
    if (raw > 150.0 || slope > 1.2)
        return BIOME_MOUNTAINS;

    const double f = std::max(cfg.biome_frequency, 0.0001) / 0.0035;
    const double n = valueNoise(wx * f * 0.02, wz * f * 0.02, cfg.world_seed + 7);
    if (raw < 4.0 && slope < 0.12)
        return BIOME_SWAMP;
    if (n < 0.30)
        return BIOME_DESERT;
    if (n < 0.58)
        return BIOME_FOREST;
    if (slope > 0.45)
        return BIOME_HILLS;
    return BIOME_PLAINS;
}

// ============================================================
// characters
// ============================================================

namespace {
const CharacterProfile kCharacters[4] = {
    {1, "Bombardier", 10.0, 100.0},
    {2, "Scout", 14.0, 80.0},
    {3, "Tank", 7.0, 150.0},
    {4, "Engineer", 9.0, 90.0},
};
} // namespace

const CharacterProfile& characterById(int id) {
    for (const auto& c : kCharacters)
        if (c.id == id)
            return c;
    return kCharacters[0];
}

// ============================================================
// game modes / match
// ============================================================

const char* const kGameModeIds[3] = {"classic", "balloon_vs_player", "sandbox"};

namespace {
const GameModeRules kModes[3] = {
    {"classic", "Classic", "Ai 5 minute sa spargi cat mai multe baloane.",
     300.0, true, false, 50},
    {"balloon_vs_player", "Balloon vs Player",
     "Survival fara limita de timp impotriva baloanelor AI.", 0.0, true, false,
     75},
    {"sandbox", "Sandbox",
     "Construiesti liber, cu blocuri nelimitate si fara atacuri AI.", 0.0,
     false, true, 0},
};
} // namespace

std::string normalizeGameMode(const std::string& value) {
    std::string v;
    for (char c : value)
        v.push_back((char)std::tolower((unsigned char)c));
    if (v == "free_for_all" || v == "singleplayer" || v.empty())
        return "classic";
    if (v == "balloon_hunt")
        return "balloon_vs_player";
    for (const char* id : kGameModeIds)
        if (v == id)
            return v;
    return "classic";
}

const GameModeRules& rulesFor(const std::string& id) {
    const std::string norm = normalizeGameMode(id);
    for (const auto& m : kModes)
        if (norm == m.id)
            return m;
    return kModes[0];
}

MatchState MatchState::create(const std::string& mode) {
    MatchState s;
    s.rules = rulesFor(mode);
    return s;
}

double MatchState::timeRemaining() const {
    if (rules.duration_seconds <= 0.0)
        return -1.0;
    return std::max(0.0, rules.duration_seconds - elapsed);
}

std::string MatchState::clockText() const {
    const double rem = timeRemaining();
    if (rem < 0.0)
        return "--:--";
    int total = (int)std::max(0.0, rem + 0.999);
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%02d:%02d", total / 60, total % 60);
    return buf;
}

bool MatchState::update(double dt, bool active) {
    if (finished || !active || rules.duration_seconds <= 0.0)
        return false;
    elapsed = std::min(rules.duration_seconds,
                       elapsed + std::max(0.0, dt));
    if (elapsed >= rules.duration_seconds) {
        finished = true;
        return true;
    }
    return false;
}

void MatchState::syncRemaining(double remaining) {
    if (rules.duration_seconds <= 0.0)
        return;
    remaining = std::clamp(remaining, 0.0, rules.duration_seconds);
    elapsed = rules.duration_seconds - remaining;
    if (remaining <= 0.0)
        finished = true;
}

void MatchState::finish() {
    if (rules.duration_seconds > 0.0)
        elapsed = rules.duration_seconds;
    finished = true;
}

// ============================================================
// crafting
// ============================================================

bool CraftingSystem::load(const std::string& path) {
    std::ifstream f(path);
    if (!f)
        return false;
    json j;
    try {
        f >> j;
    } catch (...) {
        return false;
    }
    recipes_.clear();
    for (const auto& item : j.value("recipes", json::array())) {
        Recipe r;
        r.name = item.value("name", "Recipe");
        r.mode = item.value("mode", "workbench");
        if (item.contains("ingredients")) {
            for (auto it = item["ingredients"].begin();
                 it != item["ingredients"].end(); ++it) {
                const int value = it.value().get<int>();
                if (value > 0)
                    r.ingredients[std::atoi(it.key().c_str())] = value;
            }
        }
        if (item.contains("result")) {
            r.result_type = item["result"].value("type", 0);
            r.result_count = std::max(1, item["result"].value("count", 1));
        }
        recipes_.push_back(std::move(r));
    }
    return true;
}

bool CraftingSystem::canCraft(
    const Recipe& r, const std::array<int, kBlockTypeCount>& inv) const {
    for (const auto& [type, needed] : r.ingredients)
        if (type < 0 || type >= kBlockTypeCount || inv[type] < needed)
            return false;
    return true;
}

bool CraftingSystem::craft(const Recipe& r,
                           std::array<int, kBlockTypeCount>& inv) const {
    if (!canCraft(r, inv))
        return false;
    for (const auto& [type, needed] : r.ingredients)
        inv[type] -= needed;
    if (r.result_type >= 0 && r.result_type < kBlockTypeCount)
        inv[r.result_type] += r.result_count;
    return true;
}

// ============================================================
// inventory
// ============================================================

Inventory::Inventory() {
    counts.fill(0);
    counts[GRASS] = 64;
    counts[DIRT] = 64;
    counts[STONE] = 32;
}

int Inventory::selectedType() const {
    if (selected < 0 || selected >= kInventorySlots)
        return kBlockOrder[0];
    return kBlockOrder[selected];
}

bool Inventory::has(int type) const {
    if (unlimited)
        return true;
    return type >= 0 && type < kBlockTypeCount && counts[type] > 0;
}

void Inventory::add(int type, int amount) {
    if (type <= 0 || type >= kBlockTypeCount)
        return;
    counts[type] += amount;
}

bool Inventory::useSelected() {
    const int type = selectedType();
    if (!has(type))
        return false;
    if (!unlimited)
        counts[type] -= 1;
    return true;
}

// ============================================================
// placed blocks
// ============================================================

double Blocks::groundAt(const Cell& c) const {
    return terrain_.heightAt(blockCellMin(c.x) + BLOCK_CELL * 0.5,
                             blockCellMin(c.z) + BLOCK_CELL * 0.5);
}

bool Blocks::embedded(const Cell& c) const {
    return groundAt(c) > blockCellMax(c.y) - 0.05;
}

bool Blocks::supported(const Cell& c) const {
    if (groundAt(c) >= blockCellMin(c.y) - 1.2)
        return true;
    for (int dz = -1; dz <= 1; ++dz)
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx) {
                if (std::abs(dx) + std::abs(dy) + std::abs(dz) != 1)
                    continue;
                if (has({c.x + dx, c.y + dy, c.z + dz}))
                    return true;
            }
    return false;
}

bool Blocks::place(const Cell& c, uint8_t id, bool force) {
    if (map_.find(c) != map_.end())
        return false;
    if (id == AIR)
        return false;
    // BalloonWar allows floating blocks (the 23-augus support rule is
    // deliberately not enforced); structures pass force=true anyway.
    if (!force && embedded(c))
        return false;
    map_.emplace(c, id);
    ++version_;
    return true;
}

bool Blocks::remove(const Cell& c) {
    if (map_.erase(c) > 0) {
        ++version_;
        return true;
    }
    return false;
}

bool Blocks::raycast(const glm::dvec3& origin, const glm::dvec3& dir,
                     double maxDist, Cell& outCell, Cell& outFace,
                     double& outDist) const {
    bool found = false;
    double best = maxDist;
    for (const auto& [c, b] : map_) {
        (void)b;
        const double mnx = blockCellMin(c.x), mny = blockCellMin(c.y);
        const double mnz = blockCellMin(c.z);
        const double mxx = blockCellMax(c.x), mxy = blockCellMax(c.y);
        const double mxz = blockCellMax(c.z);

        double tmin = -1e18, tmax = 1e18;
        int axis = -1;
        bool skip = false;
        for (int a = 0; a < 3 && !skip; ++a) {
            const double o = a == 0 ? origin.x : (a == 1 ? origin.y : origin.z);
            const double d = a == 0 ? dir.x : (a == 1 ? dir.y : dir.z);
            const double lo = a == 0 ? mnx : (a == 1 ? mny : mnz);
            const double hi = a == 0 ? mxx : (a == 1 ? mxy : mxz);
            if (std::abs(d) < 1e-12) {
                if (o < lo || o > hi)
                    skip = true;
            } else {
                double t1 = (lo - o) / d;
                double t2 = (hi - o) / d;
                if (t1 > t2)
                    std::swap(t1, t2);
                if (t1 > tmin) {
                    tmin = t1;
                    axis = a;
                }
                if (t2 < tmax)
                    tmax = t2;
                if (tmin > tmax)
                    skip = true;
            }
        }
        if (skip)
            continue;
        if (tmin >= 0.0 && tmin < best) {
            best = tmin;
            outCell = c;
            outFace = {0, 0, 0};
            if (axis == 0)
                outFace.x = dir.x > 0 ? -1 : 1;
            else if (axis == 1)
                outFace.y = dir.y > 0 ? -1 : 1;
            else
                outFace.z = dir.z > 0 ? -1 : 1;
            found = true;
        }
    }
    outDist = best;
    return found;
}

bool Blocks::resolvePlayer(glm::dvec3& feet, double radius, double height,
                           glm::dvec3& vel, bool& grounded) const {
    bool touched = false;
    for (const auto& [c, b] : map_) {
        (void)b;
        const double mnx = blockCellMin(c.x), mny = blockCellMin(c.y);
        const double mnz = blockCellMin(c.z);
        const double mxx = blockCellMax(c.x), mxy = blockCellMax(c.y);
        const double mxz = blockCellMax(c.z);

        const double x0 = feet.x - radius, x1 = feet.x + radius;
        const double y0 = feet.y, y1 = feet.y + height;
        const double z0 = feet.z - radius, z1 = feet.z + radius;

        const double ox = std::min(x1, mxx) - std::max(x0, mnx);
        const double oy = std::min(y1, mxy) - std::max(y0, mny);
        const double oz = std::min(z1, mxz) - std::max(z0, mnz);
        if (ox <= 0 || oy <= 0 || oz <= 0)
            continue;

        touched = true;
        if (ox <= oy && ox <= oz) {
            if (feet.x > (mnx + mxx) * 0.5)
                feet.x = mxx + radius + 1e-4;
            else
                feet.x = mnx - radius - 1e-4;
            vel.x = 0;
        } else if (oy <= oz) {
            if (feet.y > (mny + mxy) * 0.5) {
                feet.y = mxy;
                vel.y = 0;
                grounded = true;
            } else {
                feet.y = mny - height - 1e-4;
                vel.y = 0;
            }
        } else {
            if (feet.z > (mnz + mxz) * 0.5)
                feet.z = mxz + radius + 1e-4;
            else
                feet.z = mnz - radius - 1e-4;
            vel.z = 0;
        }
    }
    return touched;
}

double Blocks::floorAt(double x, double z, double feetY) const {
    double best = -1e30;
    const int64_t cx = blockCellOf(x);
    const int64_t cz = blockCellOf(z);
    for (const auto& [c, block] : map_) {
        (void)block;
        if (c.x != cx || c.z != cz)
            continue;
        const double top = blockCellMax(c.y);
        if (top <= feetY + 0.45)
            best = std::max(best, top);
    }
    return best;
}

// ============================================================
// structures
// ============================================================

namespace {
constexpr int64_t kChunkPrimeX = 73856093;
constexpr int64_t kChunkPrimeZ = 19349663;

void putBlock(Blocks& blocks, double x, double y, double z, int type) {
    blocks.place({blockCellOf(x), blockCellOf(y), blockCellOf(z)},
                 (uint8_t)type, true);
}

void genTree(Blocks& blocks, double wx, double wz, double h,
             std::mt19937_64& rng) {
    const int trunk = 3 + (int)(rng() % 3);
    for (int i = 0; i < trunk; ++i)
        putBlock(blocks, wx, h + 0.5 + i, wz, WOOD);
    const double topY = h + 0.5 + trunk - 1;
    putBlock(blocks, wx, topY + 1.0, wz, LEAF);
    putBlock(blocks, wx + 1.0, topY, wz, LEAF);
    putBlock(blocks, wx - 1.0, topY, wz, LEAF);
    putBlock(blocks, wx, topY, wz + 1.0, LEAF);
    putBlock(blocks, wx, topY, wz - 1.0, LEAF);
}

void genRock(Blocks& blocks, double wx, double wz, double h,
             std::mt19937_64& rng) {
    const int n = 1 + (int)(rng() % 2);
    for (int i = 0; i < n; ++i) {
        const double ox = (double)((int)(rng() % 3) - 1) * 0.5;
        const double oz = (double)((int)(rng() % 3) - 1) * 0.5;
        putBlock(blocks, wx + ox, h + 0.5, wz + oz, STONE);
    }
}

void genHouse(Blocks& blocks, double wx, double wz, double h,
              std::mt19937_64& rng) {
    (void)rng;
    for (int dx = -1; dx <= 1; ++dx)
        for (int dz = -1; dz <= 1; ++dz)
            putBlock(blocks, wx + dx, h + 0.5, wz + dz, WOOD);
    for (int dx = -1; dx <= 1; ++dx)
        for (int dz = -1; dz <= 1; ++dz) {
            if (dx == 0 && dz == 0)
                continue;
            putBlock(blocks, wx + dx, h + 1.5, wz + dz, WOOD);
            putBlock(blocks, wx + dx, h + 2.5, wz + dz, WOOD);
        }
    for (int dx = -1; dx <= 1; ++dx)
        for (int dz = -1; dz <= 1; ++dz)
            putBlock(blocks, wx + dx, h + 3.5, wz + dz, STONE);
}

int naturalCount(int biome, double treeDensity) {
    double base = 1;
    switch (biome) {
        case BIOME_FOREST: base = 4; break;
        case BIOME_SWAMP: base = 3; break;
        case BIOME_HILLS:
        case BIOME_PLAINS: base = 2; break;
        case BIOME_MOUNTAINS:
        case BIOME_DESERT: base = 1; break;
        case BIOME_OCEAN: base = 0; break;
        default: base = 1; break;
    }
    return std::max(0, (int)std::lround(base * treeDensity));
}

double constructionChance(int biome) {
    if (biome == BIOME_PLAINS)
        return 0.5;
    if (biome == BIOME_HILLS)
        return 0.3;
    return 0.0;
}
} // namespace

void generateStructuresForChunk(world::TerrainSurface& terrain,
                                const WorldConfig& cfg, Blocks& blocks, int cx,
                                int cz) {
    const int biome = biomeAt(terrain, cfg, cx * 16.0 + 8.0, cz * 16.0 + 8.0);
    const uint64_t seed =
        ((uint64_t)(int64_t)(cx * kChunkPrimeX) ^
         (uint64_t)(int64_t)(cz * kChunkPrimeZ)) +
        (uint64_t)(int64_t)cfg.world_seed;
    std::mt19937_64 rng(seed);

    const int count = naturalCount(biome, cfg.tree_density);
    for (int i = 0; i < count; ++i) {
        const double wx = (double)(cx * 16 + (int)(rng() % 16)) + 0.5;
        const double wz = (double)(cz * 16 + (int)(rng() % 16)) + 0.5;
        const double h = terrain.heightAt(wx, wz);
        if (h <= WATER_LEVEL + 0.5)
            continue;
        if (rng() % 3 < 2)
            genTree(blocks, wx, wz, h, rng);
        else
            genRock(blocks, wx, wz, h, rng);
    }

    if ((rng() % 1000) / 1000.0 < constructionChance(biome)) {
        const double wx = (double)(cx * 16 + (int)(rng() % 16)) + 0.5;
        const double wz = (double)(cz * 16 + (int)(rng() % 16)) + 0.5;
        const double h = terrain.heightAt(wx, wz);
        if (h > WATER_LEVEL + 0.5)
            genHouse(blocks, wx, wz, h, rng);
    }
}

// ============================================================
// structure editor + blueprints
// ============================================================

void StructureEditorState::pushUndo() {
    undoStack.push_back(blocks);
    if (undoStack.size() > 64)
        undoStack.erase(undoStack.begin());
    redoStack.clear();
}

void StructureEditorState::undo() {
    if (undoStack.empty())
        return;
    redoStack.push_back(blocks);
    blocks = undoStack.back();
    undoStack.pop_back();
}

void StructureEditorState::redo() {
    if (redoStack.empty())
        return;
    undoStack.push_back(blocks);
    blocks = redoStack.back();
    redoStack.pop_back();
}

void StructureEditorState::setBlock(const Cell& c, uint8_t type) {
    if (type == AIR)
        blocks.erase(c);
    else
        blocks[c] = type;
}

void StructureEditorState::eraseBlock(const Cell& c) { blocks.erase(c); }

void StructureEditorState::clear() {
    pushUndo();
    blocks.clear();
}

bool StructureEditorState::save(const std::string& path) const {
    json j;
    j["name"] = name;
    json arr = json::array();
    for (const auto& [c, t] : blocks)
        arr.push_back({{"x", c.x}, {"y", c.y}, {"z", c.z}, {"type", (int)t}});
    j["blocks"] = std::move(arr);
    std::error_code ec;
    fs::create_directories(fs::path(path).parent_path(), ec);
    std::ofstream f(path);
    if (!f)
        return false;
    f << j.dump(1, '\t');
    return (bool)f;
}

bool StructureEditorState::load(const std::string& path) {
    std::ifstream f(path);
    if (!f)
        return false;
    json j;
    try {
        f >> j;
    } catch (...) {
        return false;
    }
    std::map<Cell, uint8_t> next;
    for (const auto& b : j.value("blocks", json::array())) {
        Cell c{b.value("x", (int64_t)0), b.value("y", (int64_t)0),
               b.value("z", (int64_t)0)};
        next[c] = (uint8_t)b.value("type", 3);
    }
    pushUndo();
    blocks = std::move(next);
    name = j.value("name", name);
    return true;
}

void BlueprintLibrary::scan(const std::vector<std::string>& dirs) {
    list_.clear();
    for (const auto& dir : dirs) {
        std::error_code ec;
        if (!fs::is_directory(dir, ec))
            continue;
        if (lastDir_.empty())
            lastDir_ = dir;
        for (const auto& entry : fs::directory_iterator(dir, ec)) {
            if (entry.path().extension() != ".json")
                continue;
            BlueprintInfo info;
            info.path = entry.path().string();
            info.name = entry.path().stem().string();
            list_.push_back(std::move(info));
        }
    }
    std::sort(list_.begin(), list_.end(),
              [](const BlueprintInfo& a, const BlueprintInfo& b) {
                  return a.name < b.name;
              });
}

bool BlueprintLibrary::load(const BlueprintInfo& info,
                            std::map<Cell, uint8_t>& out) const {
    std::ifstream f(info.path);
    if (!f)
        return false;
    json j;
    try {
        f >> j;
    } catch (...) {
        return false;
    }
    out.clear();
    for (const auto& b : j.value("blocks", json::array())) {
        Cell c{b.value("x", (int64_t)0), b.value("y", (int64_t)0),
               b.value("z", (int64_t)0)};
        out[c] = (uint8_t)b.value("type", 3);
    }
    return true;
}

// ============================================================
// arrows
// ============================================================

bool Arrow::update(double dt, world::TerrainSurface& terrain,
                   std::vector<Balloon>& balloons) {
    if (stuck) {
        if (hitBalloon && !hitBalloon->dead)
            pos = hitBalloon->pos;
        life += dt;
        return life > 15.0;
    }
    life += dt;
    if (life > 5.0)
        return true;
    pos += dir * speed * dt;

    const double ground = terrain.heightAt(pos.x, pos.z);
    if (pos.y <= ground + 0.1) {
        stuck = true;
        impactPending = true;
        return false;
    }
    for (auto& b : balloons) {
        if (b.dead)
            continue;
        const glm::dvec3 d = b.pos - pos;
        if (glm::length(d) <= 0.95 + 0.3) {
            b.hp -= 25.0;
            b.hitFlash = 0.15;
            if (b.hp <= 0.0)
                b.dead = true;
            stuck = true;
            impactPending = true;
            hitBalloon = &b;
            b.stuck.push_back(this);
            return false;
        }
    }
    return false;
}

void Arrow::detach() {
    if (hitBalloon) {
        auto& v = hitBalloon->stuck;
        v.erase(std::remove(v.begin(), v.end(), this), v.end());
        hitBalloon = nullptr;
    }
}

void Arrow::release(std::mt19937_64& rng) {
    detach();
    stuck = false;
    std::uniform_real_distribution<double> uni(-1.0, 1.0);
    std::uniform_real_distribution<double> up(0.2, 1.0);
    glm::dvec3 d(uni(rng), up(rng), uni(rng));
    const double n = glm::length(d);
    if (n > 1e-6)
        d = d / n * 0.5;
    dir = d;
    speed = 15.0;
    life = 0.0;
}

// ============================================================
// enemy manager
// ============================================================

EnemyManager::EnemyManager(world::TerrainSurface& terrain,
                           const WorldConfig& cfg, int maxBalloons)
    : terrain_(terrain),
      cfg_(cfg),
      maxBalloons_(maxBalloons),
      rng_((uint64_t)(int64_t)cfg.world_seed * 0x9E3779B97F4A7C15ULL + 1u) {}

void EnemyManager::clear() {
    for (auto& a : arrows_)
        a->detach();
    arrows_.clear();
    balloons_.clear();
    spawners_.clear();
    events_.clear();
}

void EnemyManager::update(double dt, Player& player, const glm::dvec3& target,
                          bool spawnEnabled) {
    maintainSpawners(dt, player, spawnEnabled);

    double damage = 0.0;
    for (auto& b : balloons_) {
        b.attackTimer = std::max(0.0, b.attackTimer - dt);
        b.hitFlash = std::max(0.0, b.hitFlash - dt);
        if (b.dead)
            continue;
        const glm::dvec3 to = target - b.pos;
        const double dist = glm::length(to);
        if (dist > 3.0) {
            if (dist > 1e-9)
                b.pos += (to / dist) * b.speed * dt;
        } else if (b.attackTimer <= 0.0) {
            damage += 10.0;
            b.attackTimer = 1.2;
        }
        b.pos.x = std::clamp(b.pos.x, -5000.0, 5000.0);
        b.pos.z = std::clamp(b.pos.z, -5000.0, 5000.0);
    }
    if (damage > 0.0)
        player.damage(damage);

    for (auto& a : arrows_) {
        const bool expired = a->update(dt, terrain_, balloons_);
        if (a->impactPending) {
            events_.emplace_back("arrow_hit", a->pos);
            a->impactPending = false;
        }
        if (expired)
            a->detach();
    }
    arrows_.erase(
        std::remove_if(arrows_.begin(), arrows_.end(),
                       [](const std::unique_ptr<Arrow>& a) {
                           return a->life > (a->stuck ? 15.0 : 5.0) &&
                                  !a->hitBalloon;
                       }),
        arrows_.end());

    cleanupDead(player);
}

void EnemyManager::maintainSpawners(double dt, Player& player,
                                    bool spawnEnabled) {
    const int pcx = (int)std::floor(player.pos.x / 16.0);
    const int pcz = (int)std::floor(player.pos.z / 16.0);
    constexpr int R = 4;

    if (spawnEnabled) {
        for (auto it = spawners_.begin(); it != spawners_.end();) {
            if (std::abs(it->first.first - pcx) > R ||
                std::abs(it->first.second - pcz) > R)
                it = spawners_.erase(it);
            else
                ++it;
        }
        for (int cx = pcx - R; cx <= pcx + R; ++cx)
            for (int cz = pcz - R; cz <= pcz + R; ++cz) {
                const auto key = std::make_pair(cx, cz);
                if (spawners_.find(key) == spawners_.end()) {
                    auto list = spawnersForChunk(cx, cz);
                    if (!list.empty())
                        spawners_[key] = std::move(list);
                }
            }
    }

    for (auto& [key, list] : spawners_) {
        (void)key;
        for (auto& s : list) {
            s.timer -= dt;
            if (s.timer <= 0.0) {
                std::uniform_real_distribution<double> uni(15.0, 30.0);
                s.timer = uni(rng_);
                if (spawnEnabled && (int)balloons_.size() < maxBalloons_)
                    spawnBalloon(s);
            }
        }
    }
}

std::vector<Spawner> EnemyManager::spawnersForChunk(int cx, int cz) const {
    std::vector<Spawner> out;
    const int biome = biomeAt(terrain_, cfg_, cx * 16.0 + 8.0, cz * 16.0 + 8.0);
    int count = 0;
    if (biome == BIOME_SWAMP)
        count = 3;
    else if (biome == BIOME_FOREST || biome == BIOME_MOUNTAINS)
        count = 2;
    if (count == 0)
        return out;

    std::mt19937_64 rng(((uint64_t)(int64_t)(cx * kChunkPrimeX) ^
                         (uint64_t)(int64_t)(cz * kChunkPrimeZ)) +
                        (uint64_t)(int64_t)cfg_.world_seed);
    std::uniform_real_distribution<double> uni(0.0, 15.0);
    for (int i = 0; i < count; ++i) {
        const double wx = (double)(cx * 16) + uni(rng);
        const double wz = (double)(cz * 16) + uni(rng);
        const double h = terrain_.heightAt(wx, wz);
        if (h <= WATER_LEVEL + 0.5)
            continue;
        Spawner s;
        s.pos = {wx, h + 0.5, wz};
        out.push_back(s);
    }
    return out;
}

void EnemyManager::spawnBalloon(const Spawner& s) {
    Balloon b;
    b.pos = s.pos + glm::dvec3(0.0, 15.0, 0.0);
    const int roll = (int)(rng_() % 100);
    if (roll < 15) {
        b.type = 1; // rapid
        b.speed = 5.5;
        b.hp = b.maxHp = 60.0;
        b.points = 15.0;
    } else if (roll < 30) {
        b.type = 2; // mare
        b.speed = 2.0;
        b.hp = b.maxHp = 200.0;
        b.points = 30.0;
    } else {
        b.type = 0; // normal
        b.speed = 3.2;
        b.hp = b.maxHp = 100.0;
        b.points = 10.0;
    }
    balloons_.push_back(std::move(b));
}

void EnemyManager::cleanupDead(Player& player) {
    std::vector<Balloon> alive;
    alive.reserve(balloons_.size());
    for (auto& b : balloons_) {
        if (!b.dead) {
            alive.push_back(std::move(b));
            continue;
        }
        events_.emplace_back("pop", b.pos);
        for (Arrow* a : b.stuck) {
            a->hitBalloon = nullptr;
            a->release(rng_);
        }
        b.stuck.clear();
        player.addScore((int)b.points, 1);
        balloonsPopped_ += 1;
        // loot table (InamicBalon.gd)
        auto drop = [&](int type, int minC, int maxC, double chance) {
            std::uniform_real_distribution<double> c(0.0, 1.0);
            if (c(rng_) < chance) {
                std::uniform_int_distribution<int> q(minC, maxC);
                player.addBlock(type, q(rng_));
            }
        };
        if (b.type == 0)
            drop(STONE, 1, 3, 0.6);
        else if (b.type == 1)
            drop(COAL, 1, 2, 0.5);
        else {
            drop(IRON, 1, 4, 0.7);
            drop(GOLD, 1, 1, 0.2);
        }
    }
    balloons_ = std::move(alive);
}

// ============================================================
// player
// ============================================================

void Player::spawnOnTerrain(world::TerrainSurface& terrain, double wx,
                            double wz) {
    pos = {wx, terrain.heightAt(wx, wz) + 0.2, wz};
    velocity = {0.0, 0.0, 0.0};
    spawnPos = pos;
    onFloor = true;
}

glm::dvec3 Player::forward() const {
    const double cp = std::cos(pitch);
    return glm::normalize(
        glm::dvec3(std::sin(yaw) * cp, std::sin(pitch), -std::cos(yaw) * cp));
}

glm::dvec3 Player::eye() const {
    if (cameraMode == CAMERA_THIRD_PERSON)
        return pos + glm::dvec3(0.0, EYE, 0.0);
    return pos + glm::dvec3(0.0, EYE, 0.0);
}

glm::dvec3 Player::cameraPosition() const {
    if (cameraMode == CAMERA_THIRD_PERSON) {
        const glm::dvec3 f = forward();
        return pos + glm::dvec3(0.0, EYE, 0.0) - f * cameraDistance;
    }
    return pos + glm::dvec3(0.0, EYE, 0.0);
}

void Player::mouseMove(double dxPixels, double dyPixels) {
    yaw += dxPixels * MOUSE_SENSITIVITY;
    pitch -= dyPixels * MOUSE_SENSITIVITY;
    const double limit = 1.5533; // ~89 deg
    pitch = std::clamp(pitch, -limit, limit);
}

void Player::update(double dt, const PlayerInput& in,
                    world::TerrainSurface& terrain, const water::Sim& water,
                    Blocks& blocks) {
    dt = std::min(dt, 1.0 / 30.0);
    clickTimer = std::max(0.0, clickTimer - dt);
    swordTimer = std::max(0.0, swordTimer - dt);
    invincible = std::max(0.0, invincible - dt);
    if (dead) {
        respawnTimer -= dt;
        if (respawnTimer <= 0.0)
            respawn();
        return;
    }

    if (pos.y < WORLD_BOTTOM) {
        damage(50.0);
        pos.y = terrain.heightAt(pos.x, pos.z) + 20.0;
        velocity = {0.0, 0.0, 0.0};
    }

    float depth = 0.0f;
    water.surfaceAt(pos.x, pos.z, depth);
    const bool wet = depth > 0.06f;
    inWater = wet || pos.y < WATER_LEVEL;


    // freecam: fly with the camera, ignore physics
    if (cameraMode == CAMERA_FREECAM) {
        const double speed = run_ ? 60.0 : 24.0;
        const glm::dvec3 f = forward();
        glm::dvec3 right = glm::normalize(glm::cross(f, glm::dvec3(0, 1, 0)));
        if (glm::length(right) < 1e-5)
            right = {1, 0, 0};
        glm::dvec3 wish(0.0);
        if (keyF_) wish += f;
        if (keyB_) wish -= f;
        if (keyR_) wish += right;
        if (keyL_) wish -= right;
        if (glm::length(wish) > 1e-6)
            freecamPos += glm::normalize(wish) * speed * dt;
        if (jump_)
            freecamPos.y += speed * dt;
        if (down_)
            freecamPos.y -= speed * dt;
        return;
    }

    // horizontal wish direction (camera relative, only yaw on land)
    const double sy = std::sin(yaw), cy = std::cos(yaw);
    glm::dvec2 wish(0.0);
    if (keyF_) wish += glm::dvec2(sy, -cy);
    if (keyB_) wish -= glm::dvec2(sy, -cy);
    if (keyL_) wish -= glm::dvec2(cy, sy);
    if (keyR_) wish += glm::dvec2(cy, sy);

    if (inWater) {
        glm::dvec3 dir(0.0);
        if (glm::length(wish) > 0.001) {
            wish = glm::normalize(wish);
            dir = glm::dvec3(wish.x, 0.0, wish.y);
            dir.y += std::sin(pitch);
            const double n = glm::length(dir);
            if (n > 1e-6)
                dir /= n;
        }
        const double buoyancy = GRAVITY * 0.7;
        velocity.y -= (GRAVITY - buoyancy) * dt;
        if (in.jump)
            velocity.y = SWIM_SPEED;
        if (in.down)
            velocity.y = -SWIM_SPEED;
        velocity.x = dir.x * SWIM_SPEED;
        velocity.z = dir.z * SWIM_SPEED;
        velocity.y += dir.y * SWIM_SPEED * dt * 6.0;
    } else {
        if (!onFloor)
            velocity.y -= GRAVITY * dt;
        else
            velocity.y = -0.1;
        if (glm::length(wish) > 0.001) {
            wish = glm::normalize(wish);
            const double speed =
                (onFloor && run_) ? moveSpeed * 1.6 : moveSpeed;
            velocity.x = wish.x * speed;
            velocity.z = wish.y * speed;
        } else {
            velocity.x = 0.0;
            velocity.z = 0.0;
        }
        if (onFloor && (in.jumpPressed || in.jump))
            velocity.y = JUMP_SPEED;
    }

    // horizontal movement + wall/step check
    const double nx = pos.x + velocity.x * dt;
    const double nz = pos.z + velocity.z * dt;
    if (!inWater) {
        const double feet = pos.y;
        const double ground = terrain.heightAt(nx, nz);
        double floorTop = blocks.floorAt(nx, nz, feet + 0.45);
        const double support = std::max(ground, floorTop);
        const double hLen = std::hypot(nx - pos.x, nz - pos.z);
        const double rise = support - feet;
        if (rise > 0.02 && hLen > 1e-5 &&
            rise / hLen > MAX_CLIMB_SLOPE) {
            velocity.x = 0.0;
            velocity.z = 0.0;
        } else {
            pos.x = nx;
            pos.z = nz;
        }
    } else {
        pos.x = nx;
        pos.z = nz;
    }

    // vertical
    pos.y += velocity.y * dt;
    double ground = terrain.heightAt(pos.x, pos.z);
    const double blockFloor = blocks.floorAt(pos.x, pos.z, pos.y + 0.45);
    ground = std::max(ground, blockFloor);
    if (pos.y <= ground) {
        pos.y = ground;
        velocity.y = std::max(velocity.y, 0.0);
        onFloor = true;
    } else {
        onFloor = false;
    }

    // collide with placed blocks (push out)
    glm::dvec3 p = pos;
    glm::dvec3 vel = velocity;
    bool grounded = onFloor;
    if (blocks.resolvePlayer(p, RADIUS, HEIGHT, vel, grounded)) {
        pos = p;
        velocity = vel;
        onFloor = grounded;
    }

    jump_ = false;
}

Player::PickResult Player::rayPick(Blocks& blocks,
                                   world::TerrainSurface& terrain) {
    PickResult out;
    const glm::dvec3 start = cameraPosition();
    const glm::dvec3 dir = forward();
    const double norm = glm::length(dir);
    if (norm < 1e-9)
        return out;
    const glm::dvec3 d = dir / norm;

    Cell bc, bf;
    double bd = 0.0;
    const bool blockHit =
        blocks.raycast(start, d, REACH, bc, bf, bd);

    const world::HitPoint hp = terrain.raycast(
        glm::vec3(start.x, start.y, start.z),
        glm::vec3(d.x, d.y, d.z), REACH);
    const double terrainDist =
        hp.hit ? glm::length(glm::dvec3(hp.x, hp.y, hp.z) - start) : 1e30;

    if (blockHit && bd <= terrainDist) {
        out.hit = true;
        out.isBlock = true;
        out.cell = bc;
        out.placement = {bc.x + bf.x, bc.y + bf.y, bc.z + bf.z};
        out.point = start + d * bd;
        return out;
    }
    if (hp.hit) {
        out.hit = true;
        out.isBlock = false;
        out.point = {hp.x, hp.y, hp.z};
        out.cell = {blockCellOf(hp.x), blockCellOf(hp.y), blockCellOf(hp.z)};
        const glm::dvec3 back = out.point - d * 0.25;
        out.placement = {blockCellOf(back.x), blockCellOf(back.y),
                         blockCellOf(back.z)};
    }
    return out;
}

bool Player::tryDig(Blocks& blocks, world::TerrainSurface& terrain) {
    const PickResult pick = rayPick(blocks, terrain);
    if (!pick.hit)
        return false;

    if (pick.isBlock) {
        const uint8_t id = blocks.idAt(pick.cell);
        if (id != 255 && blocks.remove(pick.cell)) {
            inventory.add(id);
            return true;
        }
        return false;
    }

    if (digMode == DIG_MODE_CUBE) {
        terrain.digAt(pick.point.x, pick.point.z);
        const double depth = terrain.heightAt(pick.point.x, pick.point.z);
        const double raw = rawRelief(depth);
        int type = STONE;
        if (raw > 120.0)
            type = STONE;
        else if (raw < 8.0)
            type = GRASS;
        else if (raw < 20.0)
            type = DIRT;
        inventory.add(type);
        return true;
    }

    // sphere dig: carve a bowl and collect a few blocks
    const double radius = 3.0;
    const int64_t cx = world::colIndex(pick.point.x);
    const int64_t cz = world::colIndex(pick.point.z);
    const int rc = (int)std::ceil(radius / world::CELL) + 1;
    for (int dz = -rc; dz <= rc; ++dz)
        for (int dx = -rc; dx <= rc; ++dx) {
            const double wx = world::colWorld(cx + dx);
            const double wz = world::colWorld(cz + dz);
            const double dd =
                std::hypot(wx - pick.point.x, wz - pick.point.z);
            if (dd > radius)
                continue;
            const double bottom =
                pick.point.y - std::sqrt(std::max(0.0, radius * radius - dd * dd));
            terrain.carveTo(wx, wz, bottom);
        }
    inventory.add(STONE, 3);
    return true;
}

bool Player::tryBuild(Blocks& blocks, world::TerrainSurface& terrain) {
    if (!inventory.useSelected())
        return false;
    const int type = inventory.selectedType();
    const PickResult pick = rayPick(blocks, terrain);
    if (!pick.hit) {
        inventory.add(type); // nothing to attach to: give the block back
        return false;
    }
    Cell target = pick.placement;
    if (blocks.has(target))
        target.y += 1;
    if (blocks.has(target) || !blocks.place(target, (uint8_t)type)) {
        inventory.add(type);
        return false;
    }
    return true;
}

void Player::attackSword(EnemyManager& enemies) {
    const glm::dvec3 start = cameraPosition();
    const glm::dvec3 dir = glm::normalize(forward());
    Balloon* best = nullptr;
    double bestDist = ATTACK_DISTANCE;
    for (auto& b : enemies.balloons()) {
        if (b.dead)
            continue;
        const glm::dvec3 to = b.pos - start;
        const double d = glm::length(to);
        if (d > ATTACK_DISTANCE + 0.95)
            continue;
        const double proj = glm::dot(to, dir);
        const double lateral = glm::length(to - dir * proj);
        if (proj >= 0.0 && proj <= ATTACK_DISTANCE && lateral <= 0.95 &&
            d < bestDist) {
            bestDist = d;
            best = &b;
        }
    }
    if (best) {
        best->hp -= ATTACK_DAMAGE;
        best->hitFlash = 0.15;
        if (best->hp <= 0.0)
            best->dead = true;
        swordTimer = 0.35;
    }
}

std::unique_ptr<Arrow> Player::shootArrow() {
    auto a = std::make_unique<Arrow>();
    a->pos = cameraPosition() + forward() * 0.5;
    a->dir = glm::normalize(forward());
    a->speed = 30.0;
    return a;
}

void Player::damage(double amount) {
    if (dead || invincible > 0.0)
        return;
    health = std::max(0.0, health - amount);
    invincible = INVINCIBLE_HIT;
    if (health <= 0.0) {
        dead = true;
        respawnTimer = RESPAWN_DELAY;
    }
}

void Player::respawn() {
    pos = spawnPos;
    velocity = {0.0, 0.0, 0.0};
    onFloor = true;
    health = maxHealth;
    dead = false;
    respawnTimer = 0.0;
    invincible = INVINCIBLE_RESPAWN;
}

void Player::addScore(int points, int balloons) {
    score += std::max(0, points);
    balloonsPopped += std::max(0, balloons);
}

// ============================================================
// game
// ============================================================

Game::Game(const WorldConfig& cfg, const std::string& mode, int characterId,
           unsigned int seed)
    : config(cfg),
      sessionMode("singleplayer"),
      matchMode(normalizeGameMode(mode)),
      match(MatchState::create(mode)),
      terrain(::terrain::generateTerrain()),
      water(terrain),
      blocks(terrain),
      enemies(terrain, cfg, match.rules.enemy_limit) {
    const CharacterProfile& ch = characterById(characterId);
    player.moveSpeed = ch.base_speed * 0.7; // 23-augus metres, keep it walkable
    player.maxHealth = ch.base_health;
    player.health = ch.base_health;
    player.inventory.unlimited = match.rules.unlimited_blocks;
    if (match.rules.unlimited_blocks)
        for (auto& c : player.inventory.counts)
            c = 9999;
    (void)seed;

    // find a dry spawn near the origin
    double sx = 8.0, sz = 8.0;
    for (int r = 0; r < 200; ++r) {
        const double t = r * 4.0;
        for (int k = 0; k < 16; ++k) {
            const double a = (double)k / 16.0 * 6.2831853;
            const double x = std::cos(a) * t + 8.0;
            const double z = std::sin(a) * t + 8.0;
            if (terrain.heightAt(x, z) > WATER_LEVEL + 2.0) {
                sx = x;
                sz = z;
                r = 1000;
                break;
            }
        }
    }
    player.spawnOnTerrain(terrain, sx, sz);
    player.yaw = -0.5;
    player.pitch = -0.2;

    // crafting recipes (optional)
    const std::string root = findProjectRoot();
    const std::string candidates[] = {
        root + "/resources/recipes.json",
        root + "/src/balloonwar/data/recipes.json",
    };
    for (const auto& path : candidates)
        if (crafting.load(path))
            break;

    generateChunksAround(player.pos, 2);
}

void Game::update(double dt, const PlayerInput& in, bool active) {
    if (active)
        player.update(dt, in, terrain, water, blocks);

    if (active) {
        const glm::dvec3 target =
            player.cameraMode == CAMERA_FREECAM ? player.freecamPos
                                                : player.cameraPosition();
        enemies.update(dt, player, target,
                       match.rules.enemies_enabled && active);
    }

    // water simulation around the player
    water.maintainAround(glm::dvec3(player.pos.x, player.pos.y, player.pos.z),
                         5.0 * world::PAGE_SIZE);
    water.step(dt);

    match.update(dt, active);
}

void Game::generateChunksAround(const glm::dvec3& eye, int radiusChunks) {
    const int pcx = (int)std::floor(eye.x / 16.0);
    const int pcz = (int)std::floor(eye.z / 16.0);
    for (int cx = pcx - radiusChunks; cx <= pcx + radiusChunks; ++cx)
        for (int cz = pcz - radiusChunks; cz <= pcz + radiusChunks; ++cz) {
            const int64_t key =
                ((int64_t)(uint32_t)cx << 32) | (uint32_t)cz;
            if (generatedChunks.count(key))
                continue;
            generatedChunks.insert(key);
            generateStructuresForChunk(terrain, config, blocks, cx, cz);
        }
}

void Game::applyTerrainChange(int64_t x, int64_t y, int64_t z, int block) {
    if (block == AIR)
        blocks.remove({x, y, z});
    else
        blocks.place({x, y, z}, (uint8_t)block, true);
}

// ============================================================
// save / load
// ============================================================

bool Game::save(const std::string& path) const {
    json j;
    j["version"] = 1;
    j["mode"] = matchMode;
    j["seed"] = config.world_seed;
    j["config"] = {
        {"surface_min_height", config.surface_min_height},
        {"surface_max_height", config.surface_max_height},
        {"terrain_frequency", config.terrain_frequency},
        {"terrain_detail_frequency", config.terrain_detail_frequency},
        {"terrain_warp_strength", config.terrain_warp_strength},
        {"terrain_curve", config.terrain_curve},
        {"biome_frequency", config.biome_frequency},
        {"biome_amplitude", config.biome_amplitude},
        {"ridge_strength", config.ridge_strength},
        {"ridge_mix", config.ridge_mix},
        {"tree_density", config.tree_density},
        {"relief_scale", config.relief_scale},
        {"cave_enabled", config.cave_enabled},
        {"custom_range", config.custom_range},
    };
    j["player"] = {
        {"x", player.pos.x},   {"y", player.pos.y},     {"z", player.pos.z},
        {"yaw", player.yaw},   {"pitch", player.pitch},
        {"health", player.health},
        {"max_health", player.maxHealth},
        {"move_speed", player.moveSpeed},
        {"score", player.score},
        {"balloons", player.balloonsPopped},
        {"weapon", player.weapon},
        {"camera_mode", player.cameraMode},
        {"dig_mode", player.digMode},
        {"selected", player.inventory.selected},
    };
    j["inventory"] = player.inventory.counts;
    j["elapsed"] = match.elapsed;
    j["finished"] = match.finished;

    json blocksJson = json::array();
    for (const auto& [c, id] : blocks.map())
        blocksJson.push_back({c.x, c.y, c.z, (int)id});
    j["blocks"] = std::move(blocksJson);

    std::error_code ec;
    fs::create_directories(fs::path(path).parent_path(), ec);
    std::ofstream f(path);
    if (!f)
        return false;
    f << j.dump();
    return (bool)f;
}

bool Game::load(const std::string& path) {
    std::ifstream f(path);
    if (!f)
        return false;
    json j;
    try {
        f >> j;
    } catch (...) {
        return false;
    }
    if (!j.is_object())
        return false;
    try {
        if (j.contains("config")) {
            const auto& c = j["config"];
            config.surface_min_height = c.value("surface_min_height", 32.0);
            config.surface_max_height = c.value("surface_max_height", 96.0);
            config.terrain_frequency = c.value("terrain_frequency", 0.018);
            config.terrain_detail_frequency =
                c.value("terrain_detail_frequency", 0.03);
            config.terrain_warp_strength =
                c.value("terrain_warp_strength", 5.0);
            config.terrain_curve = c.value("terrain_curve", 0.7);
            config.biome_frequency = c.value("biome_frequency", 0.0035);
            config.biome_amplitude = c.value("biome_amplitude", 3.0);
            config.ridge_strength = c.value("ridge_strength", 0.8);
            config.ridge_mix = c.value("ridge_mix", 0.05);
            config.tree_density = c.value("tree_density", 1.0);
            config.relief_scale = c.value("relief_scale", 3.0);
            config.cave_enabled = c.value("cave_enabled", true);
            config.custom_range = c.value("custom_range", false);
        }
        if (j.contains("player")) {
            const auto& p = j["player"];
            player.pos = {p.value("x", 0.0), p.value("y", 0.0),
                          p.value("z", 0.0)};
            player.spawnPos = player.pos;
            player.yaw = p.value("yaw", 0.0);
            player.pitch = p.value("pitch", 0.0);
            player.maxHealth = p.value("max_health", 100.0);
            player.health = std::clamp(p.value("health", player.maxHealth),
                                       0.0, player.maxHealth);
            player.moveSpeed = p.value("move_speed", 7.0);
            player.score = p.value("score", 0);
            player.balloonsPopped = p.value("balloons", 0);
            player.weapon = p.value("weapon", 0);
            player.cameraMode = p.value("camera_mode", 0);
            player.digMode = p.value("dig_mode", 0);
            player.inventory.selected = p.value("selected", 0);
            player.velocity = {0.0, 0.0, 0.0};
            player.dead = false;
        }
        if (j.contains("inventory") && j["inventory"].is_array()) {
            for (int i = 0; i < kBlockTypeCount &&
                            i < (int)j["inventory"].size();
                 ++i)
                player.inventory.counts[i] = j["inventory"][i].get<int>();
        }
        match.elapsed = j.value("elapsed", 0.0);
        match.finished = j.value("finished", false);
        if (j.contains("blocks") && j["blocks"].is_array()) {
            blocks.clear();
            for (const auto& b : j["blocks"]) {
                if (!b.is_array() || b.size() < 4)
                    continue;
                blocks.place({b[0].get<int64_t>(), b[1].get<int64_t>(),
                              b[2].get<int64_t>()},
                             (uint8_t)b[3].get<int>(), true);
            }
        }
    } catch (...) {
        return false;
    }
    return true;
}

// ============================================================
// paths
// ============================================================

glm::mat4 arrowModelMatrix(const model::Scene& scene, const glm::dvec3& pos,
                           const glm::dvec3& dir) {
    const glm::vec3 centre = (scene.bmin + scene.bmax) * 0.5f;
    const glm::vec3 sz = scene.bmax - scene.bmin;
    const float diag = glm::length(sz);
    const float scale = diag > 1e-3f ? 1.2f / diag : 1.0f;
    const glm::dvec3 d =
        glm::length(dir) > 1e-6 ? glm::normalize(dir) : glm::dvec3(0, 0, 1);
    glm::dvec3 up(0, 1, 0);
    if (std::abs(glm::dot(d, up)) > 0.99)
        up = glm::dvec3(1, 0, 0);
    const glm::dvec3 x = glm::normalize(glm::cross(up, d));
    const glm::dvec3 y = glm::cross(d, x);
    glm::mat4 basis(glm::vec4(glm::vec3(x), 0.0f),
                    glm::vec4(glm::vec3(y), 0.0f),
                    glm::vec4(glm::vec3(d), 0.0f),
                    glm::vec4(glm::vec3(pos), 1.0f));
    // the mesh's tip points along -X: rotate it onto +Z (the flight axis)
    const glm::mat4 rot =
        glm::rotate(glm::mat4(1.0f), 1.5707963f, glm::vec3(0, 1, 0));
    glm::mat4 m = basis * rot;
    m = glm::scale(m, glm::vec3(scale));
    m = m * glm::translate(glm::mat4(1.0f), -centre);
    return m;
}

std::string findProjectRoot() {
    const char* env = std::getenv("BALLOONWAR_ASSET_ROOT");
    std::vector<fs::path> candidates;
    if (env)
        candidates.emplace_back(env);
    fs::path cwd = fs::current_path();
    candidates.push_back(cwd);
    candidates.push_back(cwd / "..");
    candidates.push_back(cwd / "../..");
    candidates.push_back(cwd / "../../..");
    for (const auto& c : candidates) {
        std::error_code ec;
        if (fs::exists(c / "assets" / "textures", ec))
            return fs::weakly_canonical(c, ec).string();
        if (fs::exists(c / "models" / "balloon" / "ballon.glb", ec))
            return fs::weakly_canonical(c, ec).string();
    }
    return cwd.string();
}

std::string findAssetRoot() {
    const std::string root = findProjectRoot();
    if (fs::exists(fs::path(root) / "assets" / "textures"))
        return root;
    return root;
}

std::string defaultSavePath() {
    const char* home = std::getenv("HOME");
    if (!home)
        return "balloonwar_save.json";
    return std::string(home) + "/.local/share/balloonwar/save.json";
}

std::string defaultCredentialsPath() {
    const char* home = std::getenv("HOME");
    if (!home)
        return "balloonwar_credentials.json";
    return std::string(home) + "/.local/share/balloonwar/credentials.json";
}

} // namespace bw
