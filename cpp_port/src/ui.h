// ============================================================
// UI: immediate-mode quad painter + menu controller
// (port of balloonwar/ui/menu.py and render/ui.py)
// ============================================================

#pragma once

#include <string>
#include <vector>

#include "game.h"

namespace bw {
namespace ui {

struct Quad {
    float x = 0, y = 0, w = 0, h = 0;
    float r = 1, g = 1, b = 1, a = 1;
    float u0 = 0, v0 = 0, u1 = 1, v1 = 1;
    bool textured = false;
};

class Painter {
  public:
    std::vector<Quad> solid;
    std::vector<Quad> text;

    void clear() {
        solid.clear();
        text.clear();
    }
    void rect(float x, float y, float w, float h, float r, float g, float b,
              float a = 1.0f);
    void outline(float x, float y, float w, float h, float r, float g, float b,
                 float a, float t);
    void textAt(float x, float y, const std::string& s, float r, float g,
                float b, float a, float scale);
    void textCentered(float cx, float y, const std::string& s, float r, float g,
                      float b, float a, float scale);
    float textWidth(const std::string& s, float scale) const;
    static float lineHeight(float scale) { return 32.0f * scale; }
};

struct MenuItem {
    std::string label;
    std::string action;
    bool enabled = true;
};

class MenuController {
  public:
    std::string screen = "main";
    int selected = 0;
    std::string activeField;
    bool inGame = false;
    int selectedCharacter = 1;
    bool musicEnabled = true;
    std::string username;
    std::string password;
    std::string roomCode;
    std::string roomName;
    std::string roomPassword;
    std::string roomGameMode;
    std::string seedText = "1337";
    double terrainFrequency = 0.018;
    double surfaceMinHeight = 32.0;
    double surfaceMaxHeight = 96.0;
    double terrainWarpStrength = 5.0;
    double terrainCurve = 0.7;
    double ridgeStrength = 0.8;
    double biomeFrequency = 0.0035;
    double treeDensity = 1.0;
    double reliefScale = 3.0;
    std::string saveLabel = "SALVEAZA JOC";
    bool editorMode = false;
    std::string editorName = "Structure";
    int editorBlocks = 0;
    int editorGrid = 15;
    std::string editorBlueprint = "NICIUNUL";
    std::string status;
    std::vector<std::string> roomPlayers;
    std::string loggedUser;

    void show(const std::string& s);
    std::vector<MenuItem> items(
        bool hasSave, bool loggedIn, bool inRoom, bool isHost,
        const std::vector<std::string>& rooms,
        const std::vector<std::string>& roomIds = {});
    void move(int delta, const std::vector<MenuItem>& list);
    // returns the action for main.cpp ("" = handled internally / no-op)
    std::string activate(const std::vector<MenuItem>& list);
    void inputText(const std::string& text);
    void backspace();
    bool adjustCreator(int delta, const std::vector<MenuItem>& list);
    WorldConfig creatorConfig() const;
    std::string selectedSingleplayerModeName() const;
    std::string selectedSingleplayerMode() const;
    void selectSingleplayerMode(const std::string& id);

  private:
    std::string prepare(const std::string& action);
    std::vector<std::string> singleplayerModes_{"classic", "balloon_vs_player",
                                                "sandbox"};
    std::vector<std::string> singleplayerNames_{"CLASSIC",
                                                "BALLOON VS PLAYER", "SANDBOX"};
    int selectedMode_ = 0;
};

} // namespace ui
} // namespace bw
