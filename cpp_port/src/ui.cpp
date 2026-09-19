#include "ui.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "font_data.h"

namespace bw {
namespace ui {

// ------------------------------------------------------------
// painter
// ------------------------------------------------------------

void Painter::rect(float x, float y, float w, float h, float r, float g,
                   float b, float a) {
    Quad q;
    q.x = x;
    q.y = y;
    q.w = w;
    q.h = h;
    q.r = r;
    q.g = g;
    q.b = b;
    q.a = a;
    solid.push_back(q);
}

void Painter::outline(float x, float y, float w, float h, float r, float g,
                      float b, float a, float t) {
    rect(x, y, w, t, r, g, b, a);
    rect(x, y + h - t, w, t, r, g, b, a);
    rect(x, y, t, h, r, g, b, a);
    rect(x + w - t, y, t, h, r, g, b, a);
}

float Painter::textWidth(const std::string& s, float scale) const {
    float w = 0.0f;
    for (unsigned char ch : s) {
        if (ch < kFontFirst || ch >= kFontFirst + kFontCount) {
            w += 8.0f * scale;
            continue;
        }
        w += (float)kFontAdvance[ch - kFontFirst] * scale;
    }
    return w;
}

void Painter::textAt(float x, float y, const std::string& s, float r, float g,
                     float b, float a, float scale) {
    float cx = x;
    for (unsigned char ch : s) {
        if (ch < kFontFirst || ch >= kFontFirst + kFontCount) {
            cx += 8.0f * scale;
            continue;
        }
        const int index = ch - kFontFirst;
        const int col = index % kFontCols;
        const int row = index / kFontCols;
        Quad q;
        q.x = cx;
        q.y = y;
        q.w = (float)kFontCellW * scale;
        q.h = (float)kFontCellH * scale;
        q.r = r;
        q.g = g;
        q.b = b;
        q.a = a;
        q.u0 = (float)(col * kFontCellW) / (float)kFontAtlasW;
        q.v0 = (float)(row * kFontCellH) / (float)kFontAtlasH;
        q.u1 = (float)((col + 1) * kFontCellW) / (float)kFontAtlasW;
        q.v1 = (float)((row + 1) * kFontCellH) / (float)kFontAtlasH;
        q.textured = true;
        text.push_back(q);
        cx += (float)kFontAdvance[index] * scale;
    }
}

void Painter::textCentered(float cx, float y, const std::string& s, float r,
                           float g, float b, float a, float scale) {
    textAt(cx - textWidth(s, scale) * 0.5f, y, s, r, g, b, a, scale);
}

// ------------------------------------------------------------
// menu controller (port of menu.py)
// ------------------------------------------------------------

void MenuController::show(const std::string& s) {
    screen = s;
    selected = 0;
    activeField.clear();
}

std::vector<MenuItem> MenuController::items(
    bool hasSave, bool loggedIn, bool inRoom, bool isHost,
    const std::vector<std::string>& rooms,
    const std::vector<std::string>& roomIds) {
    std::vector<MenuItem> out;
    char buf[256];
    if (screen == "main") {
        if (editorMode) {
            out.push_back({"CONTINUA", "resume"});
            std::snprintf(buf, sizeof(buf), "NUME: %s", editorName.c_str());
            out.push_back({buf, "field:editor_name"});
            std::snprintf(buf, sizeof(buf), "BLUEPRINT: %s",
                          editorBlueprint.c_str());
            out.push_back({buf, "editor_cycle"});
            out.push_back({"INCARCA BLUEPRINT", "editor_load"});
            out.push_back({saveLabel, "save_game"});
            out.push_back({"UNDO", "editor_undo"});
            out.push_back({"REDO", "editor_redo"});
            std::snprintf(buf, sizeof(buf), "GRILA: %dx%d", editorGrid,
                          editorGrid);
            out.push_back({buf, "editor_grid"});
            std::snprintf(buf, sizeof(buf), "GOLESTE (%d BLOCURI)",
                          editorBlocks);
            out.push_back({buf, "editor_clear"});
            out.push_back({"SCHIMBA MODUL", "play_options"});
            out.push_back({"IESIRE", "quit"});
            return out;
        }
        out.push_back({inGame ? "CONTINUA" : "JOACA",
                       inGame ? "resume" : "play_options"});
        out.push_back({"INCARCA JOC", "load_game", hasSave});
        if (loggedIn)
            out.push_back({"INCARCA ONLINE", "load_online"});
        out.push_back({"ALEGE PERSONAJ", "characters"});
        out.push_back({"MULTIPLAYER", "multiplayer"});
        out.push_back({"SETARI", "settings"});
        out.push_back({saveLabel, "save_game", inGame});
        out.push_back({"IESIRE", "quit"});
        return out;
    }
    if (screen == "play") {
        std::snprintf(buf, sizeof(buf), "SEED: %s",
                      seedText.empty() ? "ALEATOR" : seedText.c_str());
        out.push_back({buf, "field:seed_text"});
        std::snprintf(buf, sizeof(buf), "MOD JOC: %s",
                      selectedSingleplayerModeName().c_str());
        out.push_back({buf, "cycle_singleplayer_game_mode"});
        out.push_back({"PORNESTE SINGLEPLAYER", "start_singleplayer"});
        out.push_back({"MOD CREATOR", "start_creator"});
        out.push_back({"EDITOR STRUCTURI", "start_structure_editor"});
        out.push_back({"INAPOI", "main"});
        return out;
    }
    if (screen == "creator") {
        std::snprintf(buf, sizeof(buf), "SEED: %s",
                      seedText.empty() ? "ALEATOR" : seedText.c_str());
        out.push_back({buf, "field:seed_text"});
        std::snprintf(buf, sizeof(buf), "FRECVENTA TEREN: %.3f",
                      terrainFrequency);
        out.push_back({buf, "creator_value:terrain_frequency"});
        std::snprintf(buf, sizeof(buf), "INALTIME MINIMA: %.0f",
                      surfaceMinHeight);
        out.push_back({buf, "creator_value:surface_min_height"});
        std::snprintf(buf, sizeof(buf), "INALTIME MAXIMA: %.0f",
                      surfaceMaxHeight);
        out.push_back({buf, "creator_value:surface_max_height"});
        std::snprintf(buf, sizeof(buf), "DOMAIN WARP: %.1f",
                      terrainWarpStrength);
        out.push_back({buf, "creator_value:terrain_warp_strength"});
        std::snprintf(buf, sizeof(buf), "CURBA TEREN: %.2f", terrainCurve);
        out.push_back({buf, "creator_value:terrain_curve"});
        std::snprintf(buf, sizeof(buf), "RIDGE: %.2f", ridgeStrength);
        out.push_back({buf, "creator_value:ridge_strength"});
        std::snprintf(buf, sizeof(buf), "FRECVENTA BIOME: %.4f",
                      biomeFrequency);
        out.push_back({buf, "creator_value:biome_frequency"});
        std::snprintf(buf, sizeof(buf), "DENSITATE COPACI: %.1f", treeDensity);
        out.push_back({buf, "creator_value:tree_density"});
        std::snprintf(buf, sizeof(buf), "RELIEF MUNTI: %.1f", reliefScale);
        out.push_back({buf, "creator_value:relief_scale"});
        out.push_back({"PORNESTE LUMEA", "start_creator_world"});
        out.push_back({"EDITOR STRUCTURI", "start_structure_editor"});
        out.push_back({"INAPOI", "play"});
        return out;
    }
    if (screen == "characters") {
        for (int id = 1; id <= 4; ++id) {
            const CharacterProfile& c = characterById(id);
            std::snprintf(buf, sizeof(buf), "%s%s  HP %.0f  VITEZA %.0f",
                          id == selectedCharacter ? "[ " : "", c.name,
                          c.base_health, c.base_speed);
            std::string label = buf;
            if (id == selectedCharacter)
                label += " ]";
            out.push_back({label, "character:" + std::to_string(id)});
        }
        out.push_back({"CONFIRMA", "confirm_character"});
        out.push_back({"INAPOI", "main"});
        return out;
    }
    if (screen == "settings") {
        out.push_back({musicEnabled ? "MUZICA: PORNITA" : "MUZICA: OPRITA",
                       "toggle_music"});
        if (loggedIn) {
            out.push_back({"LOGOUT", "logout"});
            out.push_back({"STERGE CONTUL", "delete_account_screen"});
        }
        out.push_back({"INAPOI", "main"});
        return out;
    }
    if (screen == "confirm_delete") {
        out.push_back({"CONFIRMA STERGEREA", "delete_account"});
        out.push_back({"ANULEAZA", "settings"});
        return out;
    }
    if (screen == "login") {
        std::snprintf(buf, sizeof(buf), "UTILIZATOR: %s", username.c_str());
        out.push_back({buf, "field:username"});
        std::string stars(password.size(), '*');
        std::snprintf(buf, sizeof(buf), "PAROLA: %s", stars.c_str());
        out.push_back({buf, "field:password"});
        out.push_back({"LOGIN / CONT NOU", "login"});
        out.push_back({"INAPOI", "multiplayer"});
        return out;
    }
    if (screen == "multiplayer") {
        if (!loggedIn) {
            out.push_back({"AUTENTIFICARE", "login_screen"});
            out.push_back({"INAPOI", "main"});
            return out;
        }
        if (inRoom) {
            std::snprintf(buf, sizeof(buf), "SALA: %s", roomCode.c_str());
            out.push_back({buf, "noop", false});
            std::snprintf(buf, sizeof(buf), "MOD: %s",
                          roomGameMode.empty() ? "NECUNOSCUT"
                                               : roomGameMode.c_str());
            out.push_back({buf, "noop", false});
            std::snprintf(buf, sizeof(buf), "PERSONAJ: %d",
                          selectedCharacter);
            out.push_back({buf, "characters"});
            for (const auto& p : roomPlayers)
                out.push_back({p, "noop", false});
            out.push_back({"READY", "ready"});
            if (isHost)
                out.push_back({"START JOC", "start_network_game"});
            out.push_back({"PARASESTE SALA", "leave_room"});
            out.push_back({"INAPOI", "main"});
            return out;
        }
        std::snprintf(buf, sizeof(buf), "NUME SALA: %s", roomName.c_str());
        out.push_back({buf, "field:room_name"});
        std::snprintf(buf, sizeof(buf), "COD SALA: %s", roomCode.c_str());
        out.push_back({buf, "field:room_code"});
        std::string stars(roomPassword.size(), '*');
        std::snprintf(buf, sizeof(buf), "PAROLA: %s", stars.c_str());
        out.push_back({buf, "field:room_password"});
        out.push_back({"MOD JOC: " + (roomGameMode.empty() ? std::string("CLASSIC")
                                                          : roomGameMode),
                       "cycle_game_mode"});
        out.push_back({"CREEAZA SALA", "create_room"});
        out.push_back({"INTRA IN SALA", "join_room"});
        out.push_back({"ACTUALIZEAZA LISTA", "refresh_rooms"});
        for (size_t i = 0; i < rooms.size(); ++i) {
            const std::string id =
                i < roomIds.size() ? roomIds[i] : std::string();
            out.push_back({rooms[i], "select_room:" + id});
        }
        out.push_back({"INAPOI", "main"});
        return out;
    }
    out.push_back({"INAPOI", "main"});
    return out;
}

void MenuController::move(int delta, const std::vector<MenuItem>& list) {
    if (list.empty()) {
        selected = 0;
        return;
    }
    activeField.clear();
    int index = selected;
    for (size_t i = 0; i < list.size(); ++i) {
        index = (index + delta + (int)list.size()) % (int)list.size();
        if (list[index].enabled) {
            selected = index;
            return;
        }
    }
}

std::string MenuController::prepare(const std::string& action) {
    if (action.rfind("field:", 0) == 0) {
        activeField = action.substr(6);
        return "";
    }
    activeField.clear();
    if (action.rfind("character:", 0) == 0) {
        selectedCharacter = std::atoi(action.substr(10).c_str());
        return "";
    }
    if (action.rfind("select_room:", 0) == 0) {
        const std::string id = action.substr(12);
        if (!id.empty())
            roomCode = id;
        status = "Sala selectata: " + roomCode;
        return "";
    }
    if (action == "main" || action == "characters" || action == "settings" ||
        action == "multiplayer" || action == "confirm_delete") {
        show(action);
        return "";
    }
    if (action == "play_options") {
        show("play");
        return "";
    }
    if (action == "login_screen") {
        show("login");
        return "";
    }
    if (action == "delete_account_screen") {
        show("confirm_delete");
        return "";
    }
    if (action == "toggle_music") {
        musicEnabled = !musicEnabled;
        return action;
    }
    if (action == "start_creator") {
        show("creator");
        return "";
    }
    if (action == "play") {
        show("play");
        return "";
    }
    if (action == "cycle_game_mode") {
        roomGameMode = (roomGameMode == "balloon_vs_player")
                           ? "sandbox"
                           : (roomGameMode == "sandbox" ? "classic"
                                                        : "balloon_vs_player");
        return "";
    }
    if (action == "cycle_singleplayer_game_mode") {
        selectedMode_ =
            (selectedMode_ + 1) % (int)singleplayerModes_.size();
        status = std::string("Mod: ") + selectedSingleplayerModeName();
        return "";
    }
    if (action.rfind("creator_value:", 0) == 0)
        return action;
    return action == "noop" ? "" : action;
}

std::string MenuController::activate(const std::vector<MenuItem>& list) {
    if (list.empty())
        return "";
    selected = std::max(0, std::min(selected, (int)list.size() - 1));
    if (!list[selected].enabled)
        return "";
    return prepare(list[selected].action);
}

void MenuController::inputText(const std::string& text) {
    if (activeField.empty())
        return;
    std::string* field = nullptr;
    if (activeField == "seed_text")
        field = &seedText;
    else if (activeField == "username")
        field = &username;
    else if (activeField == "password")
        field = &password;
    else if (activeField == "room_name")
        field = &roomName;
    else if (activeField == "room_code")
        field = &roomCode;
    else if (activeField == "room_password")
        field = &roomPassword;
    else if (activeField == "editor_name")
        field = &editorName;
    if (!field)
        return;
    for (char c : text)
        if (c >= 32 && c < 127)
            field->push_back(c);
    const size_t limit = activeField == "room_code" ? 12 : 50;
    if (field->size() > limit)
        field->resize(limit);
}

void MenuController::backspace() {
    if (activeField.empty())
        return;
    std::string* field = nullptr;
    if (activeField == "seed_text")
        field = &seedText;
    else if (activeField == "username")
        field = &username;
    else if (activeField == "password")
        field = &password;
    else if (activeField == "room_name")
        field = &roomName;
    else if (activeField == "room_code")
        field = &roomCode;
    else if (activeField == "room_password")
        field = &roomPassword;
    else if (activeField == "editor_name")
        field = &editorName;
    if (field && !field->empty())
        field->pop_back();
}

bool MenuController::adjustCreator(int delta,
                                   const std::vector<MenuItem>& list) {
    if (screen != "creator" || list.empty())
        return false;
    const int idx = std::max(0, std::min(selected, (int)list.size() - 1));
    const std::string& action = list[idx].action;
    if (action.rfind("creator_value:", 0) != 0)
        return false;
    const std::string field = action.substr(14);
    double* value = nullptr;
    double mn = 0, mx = 0, step = 0;
    if (field == "terrain_frequency") {
        value = &terrainFrequency;
        mn = 0.005, mx = 0.05, step = 0.001;
    } else if (field == "surface_min_height") {
        value = &surfaceMinHeight;
        mn = 4, mx = 100, step = 1;
    } else if (field == "surface_max_height") {
        value = &surfaceMaxHeight;
        mn = 40, mx = 127, step = 1;
    } else if (field == "terrain_warp_strength") {
        value = &terrainWarpStrength;
        mn = 0, mx = 15, step = 0.5;
    } else if (field == "terrain_curve") {
        value = &terrainCurve;
        mn = 0.3, mx = 1.0, step = 0.05;
    } else if (field == "ridge_strength") {
        value = &ridgeStrength;
        mn = 0, mx = 1.5, step = 0.05;
    } else if (field == "biome_frequency") {
        value = &biomeFrequency;
        mn = 0.002, mx = 0.02, step = 0.001;
    } else if (field == "tree_density") {
        value = &treeDensity;
        mn = 0, mx = 3.0, step = 0.1;
    } else if (field == "relief_scale") {
        value = &reliefScale;
        mn = 1.0, mx = 20.0, step = 0.5;
    }
    if (!value)
        return false;
    *value = std::clamp(*value + delta * step, mn, mx);
    if (surfaceMaxHeight <= surfaceMinHeight)
        surfaceMaxHeight = surfaceMinHeight + 1.0;
    return true;
}

WorldConfig MenuController::creatorConfig() const {
    WorldConfig cfg;
    cfg.world_seed = seedText.empty() ? 1337 : std::atoi(seedText.c_str());
    cfg.terrain_frequency = terrainFrequency;
    cfg.surface_min_height = surfaceMinHeight;
    cfg.surface_max_height = surfaceMaxHeight;
    cfg.terrain_warp_strength = terrainWarpStrength;
    cfg.terrain_curve = terrainCurve;
    cfg.ridge_strength = ridgeStrength;
    cfg.biome_frequency = biomeFrequency;
    cfg.tree_density = treeDensity;
    cfg.relief_scale = reliefScale;
    cfg.custom_range = surfaceMinHeight != 32.0 || surfaceMaxHeight != 96.0;
    return cfg;
}

std::string MenuController::selectedSingleplayerModeName() const {
    if (singleplayerModes_.empty())
        return "CLASSIC";
    return singleplayerNames_[selectedMode_ % singleplayerNames_.size()];
}

std::string MenuController::selectedSingleplayerMode() const {
    if (singleplayerModes_.empty())
        return "classic";
    return singleplayerModes_[selectedMode_ % singleplayerModes_.size()];
}

void MenuController::selectSingleplayerMode(const std::string& id) {
    const std::string norm = normalizeGameMode(id);
    for (size_t i = 0; i < singleplayerModes_.size(); ++i)
        if (singleplayerModes_[i] == norm) {
            selectedMode_ = (int)i;
            status = std::string("Mod: ") + selectedSingleplayerModeName();
            return;
        }
}

} // namespace ui
} // namespace bw
