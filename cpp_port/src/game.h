// ============================================================
// BalloonWar - C++ port (OpenGL / GLFW)
//
// Gameplay layer: world config, block inventory, characters,
// crafting, match rules, placed blocks, structures, balloons,
// arrows, player physics and combat, save/load.
//
// Terrain and water are the C++ implementations from the
// "23 august 1944" project (terrain.h/terrain.cpp,
// water.h/water.cpp, world.h/world.cpp).
// ============================================================

#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <glm/glm.hpp>

#include "model.h"
#include "terrain.h"
#include "water.h"
#include "world.h"

namespace bw {

// ------------------------------------------------------------
// blocks (identical ids to terrain.gd / inventar.gd)
// ------------------------------------------------------------

enum BlockType {
    AIR = 0,
    GRASS = 1,
    DIRT = 2,
    STONE = 3,
    COAL = 4,
    IRON = 5,
    COPPER = 6,
    GOLD = 7,
    DIAMOND = 8,
    WOOD = 9,
    LEAF = 10,
};

constexpr int kBlockTypeCount = 11;
constexpr int kInventorySlots = 10;
extern const int kBlockOrder[kInventorySlots];

const char* blockName(int type);
glm::vec3 blockColor(int type);

// ------------------------------------------------------------
// biomes (simplified for the continuous terrain)
// ------------------------------------------------------------

enum Biome {
    BIOME_PLAINS = 0,
    BIOME_FOREST = 1,
    BIOME_HILLS = 2,
    BIOME_DESERT = 3,
    BIOME_SWAMP = 4,
    BIOME_SNOW = 5,
    BIOME_MOUNTAINS = 6,
    BIOME_OCEAN = 7,
};

// water level of the world (metres); valleys/lakes sit below it
constexpr double WATER_LEVEL = -4.0;
constexpr double WORLD_BOTTOM = -90.0;

// invert the terrain "relief x100" amplifier (raw valley altitude)
double rawRelief(double h);
// biome at a world column (uses surface height + low frequency noise)
int biomeAt(const world::TerrainSurface& t, const struct WorldConfig& cfg,
            double wx, double wz);

// ------------------------------------------------------------
// world config (BalloonWar WorldConfig.gd values)
// ------------------------------------------------------------

struct WorldConfig {
    int world_seed = 0;
    double surface_min_height = 32.0;
    double surface_max_height = 96.0;
    double terrain_frequency = 0.018;
    double terrain_detail_frequency = 0.03;
    double terrain_warp_strength = 5.0;
    double terrain_curve = 0.7;
    double biome_frequency = 0.0035;
    double biome_amplitude = 3.0;
    double ridge_strength = 0.8;
    double ridge_mix = 0.05;
    double tree_density = 1.0;
    double relief_scale = 3.0; // natural mountains (1.0 = raw reference)
    bool cave_enabled = true;
    bool custom_range = false;
};

// ------------------------------------------------------------
// characters
// ------------------------------------------------------------

struct CharacterProfile {
    int id;
    const char* name;
    double base_speed;
    double base_health;
};
const CharacterProfile& characterById(int id);

// ------------------------------------------------------------
// game modes / match
// ------------------------------------------------------------

struct GameModeRules {
    std::string id;
    std::string name;
    std::string description;
    double duration_seconds; // <= 0 -> unlimited
    bool enemies_enabled;
    bool unlimited_blocks;
    int enemy_limit;
};

const GameModeRules& rulesFor(const std::string& id);
std::string normalizeGameMode(const std::string& value);
extern const char* const kGameModeIds[3];

struct MatchState {
    GameModeRules rules;
    double elapsed = 0.0;
    bool finished = false;

    static MatchState create(const std::string& mode);
    double timeRemaining() const;
    std::string clockText() const;
    bool update(double dt, bool active);
    void syncRemaining(double remaining);
    void finish();
};

// ------------------------------------------------------------
// crafting
// ------------------------------------------------------------

struct Recipe {
    std::string name;
    std::map<int, int> ingredients;
    int result_type = 0;
    int result_count = 1;
    std::string mode = "workbench";
};

class CraftingSystem {
  public:
    bool load(const std::string& path);
    const std::vector<Recipe>& recipes() const { return recipes_; }
    bool canCraft(const Recipe& r, const std::array<int, kBlockTypeCount>& inv) const;
    bool craft(const Recipe& r, std::array<int, kBlockTypeCount>& inv) const;

  private:
    std::vector<Recipe> recipes_;
};

// ------------------------------------------------------------
// inventory
// ------------------------------------------------------------

struct Inventory {
    std::array<int, kBlockTypeCount> counts{};
    int selected = 0;
    bool unlimited = false;

    Inventory();
    int selectedType() const;
    bool has(int type) const;
    void add(int type, int amount = 1);
    bool useSelected();
};

// ------------------------------------------------------------
// placed blocks (2 m lattice, same cells as the terrain columns)
// ------------------------------------------------------------

struct Cell {
    int64_t x = 0, y = 0, z = 0;
    bool operator==(const Cell& o) const {
        return x == o.x && y == o.y && z == o.z;
    }
    bool operator<(const Cell& o) const {
        if (x != o.x)
            return x < o.x;
        if (y != o.y)
            return y < o.y;
        return z < o.z;
    }
};

struct CellHash {
    size_t operator()(const Cell& c) const {
        uint64_t h = (uint64_t)(uint32_t)c.x * 0x9E3779B97F4A7C15ULL;
        h ^= (uint64_t)(uint32_t)c.y * 0xBF58476D1CE4E5B9ULL;
        h ^= (uint64_t)(uint32_t)c.z * 0x94D049BB133111EBULL;
        h ^= h >> 29;
        return (size_t)h;
    }
};

constexpr double BLOCK_CELL = world::CELL; // 2 m
inline int64_t blockCellOf(double w) {
    return (int64_t)std::floor(w / BLOCK_CELL);
}
inline double blockCellMin(int64_t c) { return (double)c * BLOCK_CELL; }
inline double blockCellMax(int64_t c) { return ((double)c + 1.0) * BLOCK_CELL; }

class Blocks {
  public:
    explicit Blocks(world::TerrainSurface& terrain) : terrain_(terrain) {}

    bool place(const Cell& c, uint8_t id, bool force = false);
    bool remove(const Cell& c);
    bool has(const Cell& c) const {
        return map_.find(c) != map_.end();
    }
    uint8_t idAt(const Cell& c) const {
        auto it = map_.find(c);
        return it == map_.end() ? (uint8_t)255 : it->second;
    }

    bool raycast(const glm::dvec3& origin, const glm::dvec3& dir,
                 double maxDist, Cell& outCell, Cell& outFace,
                 double& outDist) const;

    bool resolvePlayer(glm::dvec3& feet, double radius, double height,
                       glm::dvec3& vel, bool& grounded) const;
    double floorAt(double x, double z, double feetY) const;

    const std::unordered_map<Cell, uint8_t, CellHash>& map() const {
        return map_;
    }
    std::unordered_map<Cell, uint8_t, CellHash>& map() { return map_; }
    size_t count() const { return map_.size(); }
    uint64_t version() const { return version_; }
    void clear() {
        map_.clear();
        ++version_;
    }

  private:
    double groundAt(const Cell& c) const;
    bool embedded(const Cell& c) const;
    bool supported(const Cell& c) const;

    world::TerrainSurface& terrain_;
    std::unordered_map<Cell, uint8_t, CellHash> map_;
    uint64_t version_ = 0;
};

// ------------------------------------------------------------
// structures (deterministic per 16 m chunk)
// ------------------------------------------------------------

void generateStructuresForChunk(world::TerrainSurface& terrain,
                                const WorldConfig& cfg, Blocks& blocks,
                                int cx, int cz);

// ------------------------------------------------------------
// structure editor + blueprints
// ------------------------------------------------------------

struct StructureEditorState {
    int grid = 15;
    std::string name = "Structure";
    std::map<Cell, uint8_t> blocks;
    std::vector<std::map<Cell, uint8_t>> undoStack;
    std::vector<std::map<Cell, uint8_t>> redoStack;
    Cell cursor{0, 0, 0};
    int selectedType = STONE;

    void pushUndo();
    void undo();
    void redo();
    void setBlock(const Cell& c, uint8_t type);
    void eraseBlock(const Cell& c);
    void clear();
    bool save(const std::string& path) const;
    bool load(const std::string& path);
};

struct BlueprintInfo {
    std::string name;
    std::string path;
};

class BlueprintLibrary {
  public:
    void scan(const std::vector<std::string>& dirs);
    bool load(const BlueprintInfo& info, std::map<Cell, uint8_t>& out) const;
    const std::vector<BlueprintInfo>& list() const { return list_; }
    const std::string& lastDir() const { return lastDir_; }

  private:
    std::vector<BlueprintInfo> list_;
    std::string lastDir_;
};

// ------------------------------------------------------------
// combat entities
// ------------------------------------------------------------

struct Arrow;
struct Balloon;

struct Balloon {
    glm::dvec3 pos{0.0};
    int type = 0; // 0 normal, 1 rapid, 2 mare
    double speed = 3.2;
    double hp = 100.0;
    double maxHp = 100.0;
    double points = 10.0;
    double attackTimer = 0.0;
    double hitFlash = 0.0;
    bool dead = false;
    std::vector<Arrow*> stuck;
};

struct Arrow {
    glm::dvec3 pos{0.0};
    glm::dvec3 dir{0.0, 0.0, 1.0};
    double speed = 30.0;
    double life = 0.0;
    bool stuck = false;
    bool impactPending = false;
    Balloon* hitBalloon = nullptr;

    // returns true when the arrow must be removed
    bool update(double dt, world::TerrainSurface& terrain,
                std::vector<Balloon>& balloons);
    void release(std::mt19937_64& rng);
    void detach();
};

struct Spawner {
    glm::dvec3 pos{0.0};
    double timer = 5.0;
};

class EnemyManager {
  public:
    EnemyManager(world::TerrainSurface& terrain, const WorldConfig& cfg,
                 int maxBalloons);

    void setMaxBalloons(int n) { maxBalloons_ = n; }
    int maxBalloons() const { return maxBalloons_; }

    void update(double dt, struct Player& player, const glm::dvec3& target,
                bool spawnEnabled);
    void clear();

    std::vector<Balloon>& balloons() { return balloons_; }
    const std::vector<Balloon>& balloons() const { return balloons_; }
    std::vector<std::unique_ptr<Arrow>>& arrows() { return arrows_; }
    const std::vector<std::unique_ptr<Arrow>>& arrows() const { return arrows_; }
    std::map<std::pair<int, int>, std::vector<Spawner>>& spawners() {
        return spawners_;
    }

    // event queue: "pop" (balloon burst), "arrow_hit"
    std::vector<std::pair<std::string, glm::dvec3>>& events() {
        return events_;
    }
    void drainEvents() { events_.clear(); }

    void addArrow(std::unique_ptr<Arrow> a) { arrows_.push_back(std::move(a)); }

    int balloonsPopped() const { return balloonsPopped_; }

  private:
    void maintainSpawners(double dt, Player& player, bool spawnEnabled);
    std::vector<Spawner> spawnersForChunk(int cx, int cz) const;
    void spawnBalloon(const Spawner& s);
    void cleanupDead(Player& player);

    world::TerrainSurface& terrain_;
    WorldConfig cfg_;
    int maxBalloons_ = 50;
    std::mt19937_64 rng_;
    std::vector<Balloon> balloons_;
    std::vector<std::unique_ptr<Arrow>> arrows_;
    std::map<std::pair<int, int>, std::vector<Spawner>> spawners_;
    std::vector<std::pair<std::string, glm::dvec3>> events_;
    int balloonsPopped_ = 0;
};

// ------------------------------------------------------------
// player
// ------------------------------------------------------------

enum CameraMode {
    CAMERA_FIRST_PERSON = 0,
    CAMERA_THIRD_PERSON = 1,
    CAMERA_FREECAM = 2,
};
enum InteractionMode {
    INTERACT_DIG = 0,
    INTERACT_BUILD = 1,
    INTERACT_COMBAT = 2,
};
enum DigMode { DIG_MODE_CUBE = 0, DIG_MODE_SPHERE = 1 };
enum Weapon { WEAPON_CROSSBOW = 0, WEAPON_SWORD = 1 };

struct PlayerInput {
    bool forward = false;
    bool back = false;
    bool left = false;
    bool right = false;
    bool jump = false;
    bool down = false;
    bool jumpPressed = false;
};

class Player {
  public:
    static constexpr double EYE = 1.65;
    static constexpr double RADIUS = 0.45;
    static constexpr double HEIGHT = 1.8;
    static constexpr double GRAVITY = 9.8;
    static constexpr double JUMP_SPEED = 5.5;
    static constexpr double SWIM_SPEED = 5.0;
    static constexpr double REACH = 12.0;
    static constexpr double MOUSE_SENSITIVITY = 0.0022;
    static constexpr double MAX_CLIMB_SLOPE = 1.6;
    static constexpr double ATTACK_DISTANCE = 3.5;
    static constexpr double ATTACK_DAMAGE = 50.0;
    static constexpr double INVINCIBLE_HIT = 0.5;
    static constexpr double INVINCIBLE_RESPAWN = 3.0;
    static constexpr double RESPAWN_DELAY = 2.0;

    glm::dvec3 pos{0.0};     // feet
    glm::dvec3 velocity{0.0};
    double yaw = 0.0;        // radians; forward = (sin, 0, -cos) at pitch 0
    double pitch = 0.0;
    bool onFloor = false;
    bool inWater = false;
    bool freecam = false;
    glm::dvec3 freecamPos{0.0};

    int cameraMode = CAMERA_FIRST_PERSON;
    int interactionMode = INTERACT_DIG;
    int digMode = DIG_MODE_CUBE;
    int weapon = WEAPON_CROSSBOW;
    double cameraDistance = 3.5;
    double fov = 75.0;
    double clickTimer = 0.0;
    double swordTimer = 0.0;

    Inventory inventory;
    double moveSpeed = 7.0;
    double maxHealth = 100.0;
    double health = 100.0;
    double invincible = 0.0;
    int score = 0;
    int balloonsPopped = 0;
    bool dead = false;
    double respawnTimer = 0.0;
    glm::dvec3 spawnPos{0.0};

    void spawnOnTerrain(world::TerrainSurface& terrain, double wx, double wz);
    void update(double dt, const PlayerInput& in, world::TerrainSurface& terrain,
                const water::Sim& water, Blocks& blocks);
    void mouseMove(double dxPixels, double dyPixels);
    glm::dvec3 forward() const;
    glm::dvec3 eye() const;
    glm::dvec3 cameraPosition() const;

    void setMove(bool f, bool b, bool l, bool r) {
        keyF_ = f;
        keyB_ = b;
        keyL_ = l;
        keyR_ = r;
    }
    void setJump(bool on) { jump_ = on; }
    void setDown(bool on) { down_ = on; }
    void setRun(bool on) { run_ = on; }
    bool run() const { return run_; }

    // terrain/block interaction
    struct PickResult {
        bool hit = false;
        bool isBlock = false;
        Cell cell;
        Cell placement;
        glm::dvec3 point{0.0};
    };
    PickResult rayPick(Blocks& blocks, world::TerrainSurface& terrain);
    bool tryDig(Blocks& blocks, world::TerrainSurface& terrain);
    bool tryBuild(Blocks& blocks, world::TerrainSurface& terrain);

    void attackSword(EnemyManager& enemies);
    std::unique_ptr<Arrow> shootArrow();

    void damage(double amount);
    void respawn();
    void addBlock(int type, int amount = 1) { inventory.add(type, amount); }
    void addScore(int points, int balloons);

  private:
    bool keyF_ = false, keyB_ = false, keyL_ = false, keyR_ = false;
    bool jump_ = false;
    bool down_ = false;
    bool run_ = false;
};

// ------------------------------------------------------------
// the game (no GL): world + player + enemies + rules
// ------------------------------------------------------------

class Game {
  public:
    Game(const WorldConfig& cfg, const std::string& mode, int characterId,
         unsigned int seed);

    WorldConfig config;
    std::string sessionMode; // singleplayer / multiplayer / creator / structure_editor
    std::string matchMode;
    MatchState match;

    world::TerrainSurface terrain;
    water::Sim water;
    Blocks blocks;
    Player player;
    EnemyManager enemies;
    CraftingSystem crafting;

    std::unordered_set<int64_t> generatedChunks;

    void update(double dt, const PlayerInput& in, bool active);
    void generateChunksAround(const glm::dvec3& eye, int radiusChunks);

    bool save(const std::string& path) const;
    bool load(const std::string& path);

    // apply a remote terrain modification (multiplayer)
    void applyTerrainChange(int64_t x, int64_t y, int64_t z, int block);

    std::vector<std::pair<std::string, glm::dvec3>>& events() {
        return enemies.events();
    }
};

std::string defaultSavePath();
std::string defaultCredentialsPath();
std::string findAssetRoot();
std::string findProjectRoot();

// model matrix for an arrow: the mesh tip points along -X, so it is
// mapped onto the flight direction (up is kept stable for near-vertical
// shots); the model is scaled to ~1.2 m and centred on `pos`
glm::mat4 arrowModelMatrix(const model::Scene& scene, const glm::dvec3& pos,
                           const glm::dvec3& dir);

} // namespace bw
