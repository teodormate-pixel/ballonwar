// ============================================================
// BalloonWar C++ port - smoke test (no OpenGL)
//
// Covers terrain/water/world, blocks, structures, player,
// balloons, arrows, match rules, crafting, saves and the
// structure editor.
// ============================================================

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

#include <glm/gtc/matrix_transform.hpp>

#include "anim.h"
#include "bake.h"
#include "terraintex.h"
#include "game.h"
#include "model.h"

namespace {

int gChecks = 0;
int gFailures = 0;

// portable temp directory (Windows has no /tmp)
std::string tempDir() {
#ifdef _WIN32
    const char* tmp = std::getenv("TEMP");
    return tmp && *tmp ? std::string(tmp) : std::string(".");
#else
    const char* tmp = std::getenv("TMPDIR");
    return tmp && *tmp ? std::string(tmp) : std::string("/tmp");
#endif
}

void setEnv(const char* name, const char* value) {
#ifdef _WIN32
    _putenv_s(name, value);
#else
    setenv(name, value, 1);
#endif
}

void unsetEnv(const char* name) {
#ifdef _WIN32
    _putenv_s(name, "");
#else
    unsetenv(name);
#endif
}

#define CHECK(cond)                                                       \
    do {                                                                  \
        ++gChecks;                                                        \
        if (!(cond)) {                                                    \
            ++gFailures;                                                  \
            std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                 \
    } while (0)

void testTerrain() {
    terrain::SEED = 4242;
    terrain::TERRAIN_SCALE = 1.0;
    terrain::WARP_STRENGTH = 250.0;
    terrain::LAND_CURVE = 1.0;
    terrain::RIDGE_FACTOR = 1.0;
    terrain::CUSTOM_MIN = -1e9;
    terrain::CUSTOM_MAX = 1e9;
    terrain::HeightField field = terrain::generateTerrain();
    CHECK(field.size == terrain::RESOLUTION);
    CHECK((int)field.h.size() == field.size * field.size);
    float mn = 1e30f, mx = -1e30f;
    for (float v : field.h) {
        mn = std::min(mn, v);
        mx = std::max(mx, v);
    }
    CHECK(std::isfinite(mn) && std::isfinite(mx));
    CHECK(mx > mn);
    CHECK(mx > 25.0f); // relief amplification produces mountains

    const double h = terrain::baseHeightAt(12.0, -7.0);
    CHECK(std::isfinite(h));
    // rawRelief inverts the relief ramp
    const double raw = bw::rawRelief(h);
    CHECK(std::isfinite(raw));
    CHECK(raw <= h + 1e-6);
}

void testWorldAndBlocks() {
    terrain::SEED = 777;
    world::TerrainSurface terrain(terrain::generateTerrain());
    const double h0 = terrain.heightAt(4.0, 4.0);
    CHECK(std::isfinite(h0));
    terrain.ensureBuilt(0, 0);
    CHECK(terrain.pages().size() >= 1);

    bw::Blocks blocks(terrain);
    const double g = terrain.heightAt(20.0, 20.0);
    bw::Cell c{bw::blockCellOf(20.0), bw::blockCellOf(g + 1.0),
               bw::blockCellOf(20.0)};
    CHECK(blocks.place(c, bw::STONE, true));
    CHECK(blocks.has(c));
    CHECK(blocks.idAt(c) == bw::STONE);
    CHECK(blocks.count() == 1);

    bw::Cell hit, face;
    double dist = 0.0;
    const bool ray =
        blocks.raycast({bw::blockCellMin(c.x) + 1.0, g + 5.0,
                        bw::blockCellMin(c.z) + 1.0},
                       {0.0, -1.0, 0.0}, 20.0, hit, face, dist);
    CHECK(ray);
    CHECK(hit == c);

    CHECK(blocks.remove(c));
    CHECK(!blocks.has(c));
    CHECK(blocks.count() == 0);

    // carve lowers the surface
    const double before = terrain.heightAt(50.0, 50.0);
    terrain.carveTo(50.0, 50.0, before - 3.0);
    const double after = terrain.heightAt(50.0, 50.0);
    CHECK(after < before);
}

void testBiomes() {
    terrain::SEED = 99;
    world::TerrainSurface terrain(terrain::generateTerrain());
    bw::WorldConfig cfg;
    cfg.world_seed = 99;
    for (double x = -200; x <= 200; x += 37.0) {
        const int b = bw::biomeAt(terrain, cfg, x, x * 0.5);
        CHECK(b >= bw::BIOME_PLAINS && b <= bw::BIOME_OCEAN);
    }
}

void testStructures() {
    terrain::SEED = 2024;
    world::TerrainSurface terrain(terrain::generateTerrain());
    bw::WorldConfig cfg;
    cfg.world_seed = 2024;
    cfg.tree_density = 2.0;
    bw::Blocks blocks(terrain);
    for (int cx = -3; cx <= 3; ++cx)
        for (int cz = -3; cz <= 3; ++cz)
            bw::generateStructuresForChunk(terrain, cfg, blocks, cx, cz);
    CHECK(blocks.count() > 0);
}

void testInventoryAndCrafting() {
    bw::Inventory inv;
    CHECK(inv.counts[bw::GRASS] == 64);
    CHECK(inv.counts[bw::DIRT] == 64);
    CHECK(inv.counts[bw::STONE] == 32);
    CHECK(inv.selectedType() == bw::GRASS);
    inv.selected = 2;
    CHECK(inv.selectedType() == bw::STONE);
    CHECK(inv.has(bw::STONE));
    CHECK(inv.useSelected());
    CHECK(inv.counts[bw::STONE] == 31);

    bw::CraftingSystem crafting;
    const std::string path = bw::findProjectRoot() +
                             "/src/balloonwar/data/recipes.json";
    CHECK(crafting.load(path));
    CHECK(!crafting.recipes().empty());
    std::array<int, bw::kBlockTypeCount> counts{};
    counts[bw::DIRT] = 8;
    const auto& r = crafting.recipes()[0];
    CHECK(crafting.craft(r, counts));
    CHECK(counts[bw::DIRT] < 8);
}

void testMatch() {
    bw::MatchState classic = bw::MatchState::create("classic");
    CHECK(classic.rules.duration_seconds == 300.0);
    CHECK(classic.timeRemaining() == 300.0);
    for (int i = 0; i < 400; ++i)
        classic.update(1.0, true);
    CHECK(classic.finished);
    CHECK(classic.clockText() == "00:00");

    bw::MatchState sandbox = bw::MatchState::create("sandbox");
    CHECK(sandbox.rules.duration_seconds <= 0.0);
    CHECK(sandbox.timeRemaining() < 0.0);
    CHECK(sandbox.clockText() == "--:--");
    CHECK(!sandbox.rules.enemies_enabled);
    CHECK(sandbox.rules.unlimited_blocks);

    CHECK(bw::normalizeGameMode("free_for_all") == "classic");
    CHECK(bw::normalizeGameMode("balloon_hunt") == "balloon_vs_player");
    CHECK(bw::normalizeGameMode("nonsense") == "classic");
}

void testBalloonsAndArrows() {
    terrain::SEED = 5150;
    world::TerrainSurface terrain(terrain::generateTerrain());
    bw::WorldConfig cfg;
    cfg.world_seed = 5150;
    bw::Blocks blocks(terrain);
    bw::EnemyManager enemies(terrain, cfg, 10);

    double ymax = 0.0;
    for (double z = -1.0; z <= 6.0; z += 0.5)
        ymax = std::max(ymax, terrain.heightAt(0.0, z));
    bw::Balloon b;
    b.pos = {0.0, ymax + 12.0, 0.0};
    b.hp = b.maxHp = 100.0;
    enemies.balloons().push_back(b);
    CHECK(enemies.balloons().size() == 1);

    bw::Player dummy;
    dummy.maxHealth = 100.0;
    dummy.health = 100.0;

    auto arrow = std::make_unique<bw::Arrow>();
    arrow->pos = {0.0, b.pos.y, 5.0};
    arrow->dir = {0.0, 0.0, -1.0};
    arrow->speed = 30.0;
    bw::Arrow* arrowPtr = arrow.get();
    enemies.addArrow(std::move(arrow));
    CHECK(enemies.arrows().size() == 1);
    for (int i = 0; i < 40 && enemies.balloons()[0].hp >= 100.0; ++i)
        arrowPtr->update(0.05, terrain, enemies.balloons());
    // arrow hit the balloon: it is stuck and the balloon lost HP
    CHECK(enemies.balloons()[0].hp <= 75.0);
    CHECK(arrowPtr->stuck);
    CHECK(arrowPtr->hitBalloon == &enemies.balloons()[0]);

    // balloon death via direct damage
    enemies.balloons()[0].hp = 1.0;
    enemies.balloons()[0].dead = true;
    enemies.drainEvents();
    // process cleanup through a normal update (spawners disabled)
    enemies.update(0.016, dummy, {0.0, 0.0, 0.0}, false);
    CHECK(enemies.balloons().empty());
    CHECK(dummy.score > 0);
    CHECK(dummy.balloonsPopped > 0);
}

void testPlayerPhysics() {
    terrain::SEED = 606;
    world::TerrainSurface terrain(terrain::generateTerrain());
    water::Sim water(terrain);
    bw::Blocks blocks(terrain);
    bw::Player player;
    player.spawnOnTerrain(terrain, 8.0, 8.0);
    const double startY = player.pos.y;
    CHECK(startY > bw::WORLD_BOTTOM);

    bw::PlayerInput in;
    in.forward = true;
    for (int i = 0; i < 60; ++i)
        player.update(1.0 / 60.0, in, terrain, water, blocks);
    CHECK(std::isfinite(player.pos.x) && std::isfinite(player.pos.y) &&
          std::isfinite(player.pos.z));
    CHECK(player.onFloor);
    CHECK((std::abs(player.pos.y -
                    terrain.heightAt(player.pos.x, player.pos.z)) < 2.5));

    // damage / invincibility / respawn
    player.damage(25.0);
    CHECK(player.health == 75.0);
    player.damage(25.0); // blocked by invincibility
    CHECK(player.health == 75.0);
    player.invincible = 0.0;
    player.damage(500.0);
    CHECK(player.dead);
    player.respawn();
    CHECK(!player.dead);
    CHECK(player.health == player.maxHealth);
}

void testSaveLoad() {
    terrain::SEED = 8080;
    bw::WorldConfig cfg;
    cfg.world_seed = 8080;
    bw::Game game(cfg, "classic", 2, 8080);
    game.player.score = 42;
    game.player.balloonsPopped = 7;
    game.player.inventory.counts[bw::GOLD] = 5;
    const double g = game.terrain.heightAt(12.0, 12.0);
    bw::Cell c{bw::blockCellOf(12.0), bw::blockCellOf(g + 1.0),
               bw::blockCellOf(12.0)};
    game.blocks.place(c, bw::DIAMOND, true);
    const size_t blocksBefore = game.blocks.count();

    const std::string path = tempDir() + "/balloonwar_smoke_save.json";
    CHECK(game.save(path));

    terrain::SEED = 1111;
    bw::WorldConfig cfg2;
    cfg2.world_seed = 1111;
    bw::Game loaded(cfg2, "classic", 1, 1111);
    CHECK(loaded.load(path));
    CHECK(loaded.player.score == 42);
    CHECK(loaded.player.balloonsPopped == 7);
    CHECK(loaded.player.inventory.counts[bw::GOLD] == 5);
    CHECK(loaded.blocks.count() == blocksBefore);
    CHECK(loaded.blocks.has(c));
    CHECK(loaded.blocks.idAt(c) == bw::DIAMOND);
    std::remove(path.c_str());
}

void testEditor() {
    bw::StructureEditorState editor;
    editor.setBlock({0, 0, 0}, bw::STONE);
    editor.setBlock({1, 0, 0}, bw::WOOD);
    editor.pushUndo();
    editor.setBlock({2, 0, 0}, bw::GRASS);
    CHECK(editor.blocks.size() == 3);
    editor.undo();
    CHECK(editor.blocks.size() == 2);
    editor.redo();
    CHECK(editor.blocks.size() == 3);

    const std::string path = tempDir() + "/balloonwar_smoke_struct.json";
    editor.name = "Smoke";
    CHECK(editor.save(path));
    bw::StructureEditorState other;
    CHECK(other.load(path));
    CHECK(other.blocks.size() == 3);
    CHECK(other.name == "Smoke");
    std::remove(path.c_str());
}

void testCharacterRig() {
    const std::string path =
        bw::findProjectRoot() + "/models/characters/baiaat.glb";
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        std::printf("skip character rig (model missing)\n");
        return;
    }
    std::fclose(f);
    model::Scene sc;
    CHECK(model::loadGLBScene(path, sc, nullptr));
    CHECK(sc.skinned());
    CHECK(!sc.skins.empty());
    CHECK(sc.skins[0].joints.size() >= 20);
    CHECK(sc.skins[0].inverseBind.size() == sc.skins[0].joints.size());
    const int thigh = model::findNode(sc, "thigh.L");
    const int foot = model::findNode(sc, "foot.L");
    CHECK(thigh >= 0);
    CHECK(foot >= 0);

    std::vector<glm::mat4> globals, bones;
    model::computeNodeGlobals(sc, sc.nodeLocal, globals);
    model::computeSkinMatrices(sc, globals, 0, bones);
    CHECK(!bones.empty());
    const glm::vec3 restFoot(globals[foot][3]);

    // rotate the left thigh: the foot must move, and stay finite
    std::vector<glm::mat4> locals = sc.nodeLocal;
    locals[thigh] = locals[thigh] *
                    glm::rotate(glm::mat4(1.0f), 0.7f, glm::vec3(1, 0, 0));
    model::computeNodeGlobals(sc, locals, globals);
    model::computeSkinMatrices(sc, globals, 0, bones);
    const glm::vec3 posedFoot(globals[foot][3]);
    CHECK(glm::length(posedFoot - restFoot) > 0.05f);
    CHECK(glm::length(posedFoot - restFoot) < 3.0f);
    for (const auto& m : bones)
        for (int c = 0; c < 4; ++c)
            for (int r = 0; r < 4; ++r)
                CHECK(std::isfinite(m[c][r]));
}

void testTextureBake() {
    const std::string root = bw::findProjectRoot();
    // character: procedural albedo atlas
    {
        const std::string path = root + "/models/characters/baiaat.glb";
        std::FILE* f = std::fopen(path.c_str(), "rb");
        if (!f) {
            std::printf("skip character texture (model missing)\n");
            return;
        }
        std::fclose(f);
        model::Scene sc;
        if (!model::loadGLBScene(path, sc, nullptr))
            return;
        const glm::vec2 before(sc.geoms[0].verts[6], sc.geoms[0].verts[7]);
        bake::repackSceneUVs(sc);
        bool moved = false;
        for (size_t i = 0; i + 7 < sc.geoms[0].verts.size(); i += 8) {
            const glm::vec2 uv(sc.geoms[0].verts[i + 6], sc.geoms[0].verts[i + 7]);
            CHECK(uv.x >= -0.001f && uv.x <= 1.001f);
            CHECK(uv.y >= -0.001f && uv.y <= 1.001f);
            if (glm::distance(uv, before) > 0.01f)
                moved = true;
        }
        CHECK(moved);

        const bake::Image img = bake::characterTexture(sc, 256);
        CHECK(img.ok());
        CHECK(img.w == 256 && img.h == 256);
        const bake::Image img2 = bake::characterTexture(sc, 256);
        CHECK(img.rgba == img2.rgba); // deterministic

        int skin = 0, blue = 0, brown = 0, dark = 0;
        for (size_t i = 0; i < (size_t)img.w * img.h; ++i) {
            const float r = img.rgba[i * 4] / 255.0f;
            const float g = img.rgba[i * 4 + 1] / 255.0f;
            const float b = img.rgba[i * 4 + 2] / 255.0f;
            if (r > 0.80f && g > 0.55f && g < 0.95f && b < g && r > g)
                ++skin;
            else if (b > r + 0.12f && b > 0.35f)
                ++blue;
            else if (r > 0.25f && r < 0.70f && g < r && b < g)
                ++brown;
            else if (r < 0.20f && g < 0.20f && b < 0.25f)
                ++dark;
            CHECK(img.rgba[i * 4 + 3] == 255);
        }
        CHECK(skin > 40);   // face
        CHECK(blue > 500);  // hood + jacket
        CHECK(brown > 200); // boots + gloves
        CHECK(dark > 3);    // eyes
    }
    // arrow: wood shaft, metal tip, feathers
    {
        const std::string path = root + "/models/arrow/arrow.glb";
        model::Scene sc;
        if (!model::loadGLBScene(path, sc, nullptr))
            return;
        bake::repackSceneUVs(sc);
        const bake::Image img = bake::arrowTexture(sc, 128);
        CHECK(img.ok());
        int metal = 0, wood = 0, feather = 0;
        for (size_t i = 0; i < (size_t)img.w * img.h; ++i) {
            const float r = img.rgba[i * 4] / 255.0f;
            const float g = img.rgba[i * 4 + 1] / 255.0f;
            const float b = img.rgba[i * 4 + 2] / 255.0f;
            if (std::abs(r - g) < 0.08f && std::abs(g - b) < 0.08f && r > 0.4f)
                ++metal;
            else if (r > g && g > b && r < 0.7f)
                ++wood;
            else if (r > 0.45f && g < 0.4f && b < 0.4f)
                ++feather;
        }
        CHECK(metal > 20);
        CHECK(wood > 100);
        CHECK(feather > 20);
    }
}

void testTerrainTextures() {
    const auto layers = terraintex::generate(64, "");
    CHECK(layers.size() == 6);
    CHECK(layers[terraintex::GRASS].name == "grass");
    CHECK(layers[terraintex::SNOW].name == "snow");

    for (const auto& l : layers) {
        CHECK(l.albedoRough.ok());
        CHECK(l.normal.ok());
        CHECK(l.albedoRough.w == 64 && l.albedoRough.h == 64);

        // tileability: the seam between opposite edges must not be a
        // bigger jump than the average neighbouring difference
        double seam = 0.0, inner = 0.0;
        for (int y = 0; y < 64; ++y) {
            const size_t a = ((size_t)y * 64 + 0) * 4;
            const size_t b = ((size_t)y * 64 + 63) * 4;
            const size_t c = ((size_t)y * 64 + 32) * 4;
            const size_t d = ((size_t)y * 64 + 33) * 4;
            for (int k = 0; k < 3; ++k) {
                seam += std::abs((int)l.albedoRough.rgba[a + k] -
                                 (int)l.albedoRough.rgba[b + k]);
                inner += std::abs((int)l.albedoRough.rgba[c + k] -
                                  (int)l.albedoRough.rgba[d + k]);
            }
        }
        CHECK(seam <= inner * 2.0 + 64.0);

        // roughness in range and normals mostly pointing up
        double rough = 0.0, nz = 0.0, nx = 0.0, ny = 0.0;
        for (size_t i = 0; i < 64u * 64u; ++i) {
            rough += l.albedoRough.rgba[i * 4 + 3] / 255.0;
            nx += l.normal.rgba[i * 4 + 0] / 255.0 - 0.5;
            ny += l.normal.rgba[i * 4 + 1] / 255.0 - 0.5;
            nz += l.normal.rgba[i * 4 + 2] / 255.0 - 0.5;
        }
        const double n = 64.0 * 64.0;
        rough /= n;
        nx /= n;
        ny /= n;
        nz /= n;
        CHECK(rough > 0.15 && rough < 1.0);
        CHECK(nz > 0.3);
        CHECK(std::abs(nx) < 0.12 && std::abs(ny) < 0.12);
    }

    // per-material character
    auto meanRough = [&](int idx) {
        const auto& img = layers[idx].albedoRough;
        double r = 0.0;
        for (size_t i = 0; i < (size_t)img.w * img.h; ++i)
            r += img.rgba[i * 4 + 3] / 255.0;
        return r / (double)(img.w * img.h);
    };
    CHECK(meanRough(terraintex::SNOW) < 0.6);
    CHECK(meanRough(terraintex::GRASS) > 0.75);
    CHECK(meanRough(terraintex::ROCK) > 0.4);
    CHECK(meanRough(terraintex::ROCK) < 0.85);

    // deterministic
    const auto again = terraintex::generate(64, "");
    CHECK(again[terraintex::GRASS].albedoRough.rgba ==
          layers[terraintex::GRASS].albedoRough.rgba);
    CHECK(again[terraintex::ROCK].normal.rgba ==
          layers[terraintex::ROCK].normal.rgba);

    // project texture sets are used when present
    const std::string cachePath = tempDir() + "/bw_test_terrain_cache.bin";
    setEnv("BW_TERRAIN_CACHE", cachePath.c_str());
    const std::string root = bw::findProjectRoot();
    const std::string sandFile =
        root + "/assets/textures/GroundSand005/GroundSand005_COL_2K.jpg";
    if (std::FILE* f = std::fopen(sandFile.c_str(), "rb")) {
        std::fclose(f);
        const auto real = terraintex::generate(64, root);
        CHECK(real.size() == 6);
        CHECK(real[terraintex::SAND].source == "file");
        CHECK(real[terraintex::GRASS].source == "file");
        CHECK(real[terraintex::DIRT].source == "file");
        CHECK(real[terraintex::SNOW].source == "file");
        auto meanColor = [&](int idx, float& r, float& g, float& b) {
            const auto& img = real[idx].albedoRough;
            r = g = b = 0.0f;
            for (size_t i = 0; i < (size_t)img.w * img.h; ++i) {
                r += img.rgba[i * 4 + 0] / 255.0f;
                g += img.rgba[i * 4 + 1] / 255.0f;
                b += img.rgba[i * 4 + 2] / 255.0f;
            }
            const float n = (float)(img.w * img.h);
            r /= n;
            g /= n;
            b /= n;
        };
        float r = 0, g = 0, b = 0;
        meanColor(terraintex::SAND, r, g, b);
        CHECK(r > g && g > b && r > 0.6f);
        meanColor(terraintex::GRASS, r, g, b);
        CHECK(g > r && g > b);
        meanColor(terraintex::SNOW, r, g, b);
        CHECK(r > 0.7f && g > 0.7f && b > 0.7f);

        // every map is used: AO in normal.a, metallic/height/refl in extra
        auto channelStats = [&](int idx, const bake::Image& img, int channel,
                                double& mean, double& sd) {
            const size_t n = (size_t)img.w * img.h;
            mean = 0.0;
            for (size_t i = 0; i < n; ++i)
                mean += img.rgba[i * 4 + channel] / 255.0;
            mean /= (double)n;
            sd = 0.0;
            for (size_t i = 0; i < n; ++i) {
                const double d = img.rgba[i * 4 + channel] / 255.0 - mean;
                sd += d * d;
            }
            sd = std::sqrt(sd / (double)n);
            (void)idx;
        };
        double mean = 0, sd = 0;
        channelStats(terraintex::SAND, real[terraintex::SAND].normal, 3, mean,
                     sd);
        CHECK(mean > 0.5 && mean < 0.999); // AO map, not the 1.0 default
        CHECK(sd > 0.003);
        channelStats(terraintex::DIRT, real[terraintex::DIRT].normal, 3, mean,
                     sd);
        CHECK(mean < 0.99 && sd > 0.01);
        channelStats(terraintex::SNOW, real[terraintex::SNOW].extra, 1, mean,
                     sd);
        CHECK(sd > 0.05); // displacement map drives the parallax
        channelStats(terraintex::SAND, real[terraintex::SAND].extra, 2, mean,
                     sd);
        CHECK(mean < 0.45); // reflectance map (default is 0.5)
        std::remove(cachePath.c_str());
    }
    unsetEnv("BW_TERRAIN_CACHE");
}

void testArrowOrientation() {
    const std::string path =
        bw::findProjectRoot() + "/models/arrow/arrow.glb";
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        std::printf("skip arrow orientation (model missing)\n");
        return;
    }
    std::fclose(f);
    model::Scene sc;
    if (!model::loadGLBScene(path, sc, nullptr))
        return;
    CHECK(sc.ok);

    // the arrow head is the extreme of the model along -X
    const glm::vec3 tipLocal(sc.bmin.x, (sc.bmin.y + sc.bmax.y) * 0.5f,
                             (sc.bmin.z + sc.bmax.z) * 0.5f);
    const glm::dvec3 dirs[] = {{1, 0, 0},  {-1, 0, 0}, {0, 0, 1},
                               {0, 0, -1}, {0, 1, 0},  {0, -1, 0},
                               {0.577, 0.577, 0.577}};
    for (const glm::dvec3& d : dirs) {
        const glm::mat4 m = bw::arrowModelMatrix(sc, glm::dvec3(0.0), d);
        const glm::vec3 tip = glm::vec3(m * glm::vec4(tipLocal, 1.0f));
        CHECK(glm::length(tip) > 0.1f);
        CHECK(glm::dot(glm::normalize(tip), glm::normalize(glm::vec3(d))) >
              0.99f);
    }
}

void testCharacterAnimation() {
    const std::string path =
        bw::findProjectRoot() + "/models/characters/baiaat.glb";
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        std::printf("skip character animation (model missing)\n");
        return;
    }
    std::fclose(f);
    model::Scene sc;
    if (!model::loadGLBScene(path, sc, nullptr))
        return;
    const anim::Rig rig = anim::Rig::map(sc);
    CHECK(rig.valid);
    CHECK(rig.head >= 0);
    CHECK(rig.handR >= 0);
    CHECK(rig.toeL >= 0);

    anim::Driver driver;
    driver.reset(0.0f);
    std::vector<glm::mat4> locals, globals, bones;
    auto pose = [&](const anim::Input& in) {
        locals = sc.nodeLocal;
        driver.overlay(sc, rig, locals, in);
        model::computeNodeGlobals(sc, locals, globals);
        model::computeSkinMatrices(sc, globals, 0, bones);
        for (const auto& m : bones)
            for (int c = 0; c < 4; ++c)
                for (int r = 0; r < 4; ++r)
                    CHECK(std::isfinite(m[c][r]));
    };
    anim::Input in;
    in.dt = 1.0f / 60.0f;
    in.maxSpeed = 7.0f;
    in.onFloor = true;
    for (int i = 0; i < 30; ++i) {
        driver.update(in);
        pose(in);
    }
    CHECK(driver.state == anim::GROUND);
    const glm::vec3 standHead(globals[rig.head][3]);

    // running on the ground
    in.speed = 7.0f;
    in.running = true;
    for (int i = 0; i < 60; ++i) {
        driver.update(in);
        pose(in);
    }
    CHECK(driver.state == anim::GROUND);
    CHECK(driver.speedSmooth > 0.8f);
    CHECK(driver.leanFwd > 0.05f);

    // jump: leaves the ground
    in.onFloor = false;
    in.vy = 5.0f;
    for (int i = 0; i < 20; ++i) {
        driver.update(in);
        pose(in);
    }
    CHECK(driver.state == anim::AIR);
    CHECK(driver.airBlend > 0.5f);

    // landing: crouch impulse, back on the ground
    in.onFloor = true;
    in.vy = -6.0f;
    driver.update(in);
    CHECK(driver.state == anim::GROUND);
    CHECK(driver.landTime > 0.0f);
    CHECK(driver.landStrength > 0.5f);
    pose(in);
    CHECK(std::abs(driver.crouch) > 0.1f);

    // swim: prone pose, head drops towards the water
    in.inWater = true;
    in.onFloor = false;
    in.speed = 4.0f;
    in.vy = 0.0f;
    for (int i = 0; i < 90; ++i) {
        driver.update(in);
        pose(in);
    }
    CHECK(driver.state == anim::SWIM);
    CHECK(driver.swimBlend > 0.9f);
    const glm::vec3 swimHead(globals[rig.head][3]);
    CHECK(swimHead.y < standHead.y - 0.05f);

    // death: collapses towards the ground
    in.inWater = false;
    in.onFloor = true;
    in.dead = true;
    in.speed = 0.0f;
    for (int i = 0; i < 180; ++i) {
        driver.update(in);
        pose(in);
    }
    CHECK(driver.state == anim::DEAD);
    CHECK(driver.deathBlend > 0.95f);
    CHECK(globals[rig.head][3].y < standHead.y - 0.1f);

    // procedural fallback base (no baked clips) still animates
    anim::Driver proc;
    proc.reset(0.0f);
    anim::Input pin;
    pin.dt = 1.0f / 60.0f;
    pin.maxSpeed = 7.0f;
    pin.onFloor = true;
    pin.speed = 5.0f;
    pin.proceduralBase = true;
    std::vector<glm::mat4> a, b;
    locals = sc.nodeLocal;
    proc.update(pin);
    proc.overlay(sc, rig, locals, pin);
    a = locals;
    for (int i = 0; i < 20; ++i) {
        proc.update(pin);
        locals = sc.nodeLocal;
        proc.overlay(sc, rig, locals, pin);
    }
    b = locals;
    CHECK(proc.walkPhase > 1.0f);
    CHECK(glm::length(glm::vec3(a[rig.thighL][1]) -
                      glm::vec3(b[rig.thighL][1])) > 0.01f);
}

void testGameLoop() {
    terrain::SEED = 1337;
    bw::WorldConfig cfg;
    cfg.world_seed = 1337;
    bw::Game game(cfg, "balloon_vs_player", 1, 1337);
    bw::PlayerInput in;
    for (int i = 0; i < 30; ++i)
        game.update(1.0 / 60.0, in, true);
    CHECK(std::isfinite(game.player.pos.y));
    CHECK(game.match.rules.enemies_enabled);
    CHECK(!game.match.finished);
    // structures were generated around the spawn
    CHECK(game.blocks.count() > 0);
}

} // namespace

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0); // keep output on crash
    std::printf("BalloonWar C++ smoke test\n");
    std::printf("[test] testTerrain\n");
    testTerrain();
    std::printf("[test] testWorldAndBlocks\n");
    testWorldAndBlocks();
    std::printf("[test] testBiomes\n");
    testBiomes();
    std::printf("[test] testStructures\n");
    testStructures();
    std::printf("[test] testInventoryAndCrafting\n");
    testInventoryAndCrafting();
    std::printf("[test] testMatch\n");
    testMatch();
    std::printf("[test] testBalloonsAndArrows\n");
    testBalloonsAndArrows();
    std::printf("[test] testPlayerPhysics\n");
    testPlayerPhysics();
    std::printf("[test] testSaveLoad\n");
    testSaveLoad();
    std::printf("[test] testEditor\n");
    testEditor();
    std::printf("[test] testCharacterRig\n");
    testCharacterRig();
    std::printf("[test] testArrowOrientation\n");
    testArrowOrientation();
    std::printf("[test] testTextureBake\n");
    testTextureBake();
    std::printf("[test] testTerrainTextures\n");
    testTerrainTextures();
    std::printf("[test] testCharacterAnimation\n");
    testCharacterAnimation();
    std::printf("[test] testGameLoop\n");
    testGameLoop();
    std::printf("%d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
