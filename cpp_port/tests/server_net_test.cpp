// ============================================================
// End-to-end test: the real C++ network client against the
// C++ game server (balloonwar-server).
//
//   BW_NET_URL=ws://127.0.0.1:9879 ./build/server_net_test
//
// Covers: auth, create room, start game, input/state updates,
// terrain changes, chat, player data and leaving the room.
// ============================================================

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

#include "net.h"

namespace {

bool waitType(bw::net::NetworkClient &client, const char *type,
              nlohmann::json *out = nullptr, double timeout = 8.0) {
    const auto start = std::chrono::steady_clock::now();
    while (std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                         start)
               .count() < timeout) {
        for (const auto &message : client.poll()) {
            if (message.value("type", "") == type) {
                if (out)
                    *out = message;
                return true;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    return false;
}

} // namespace

int main() {
    const char *urlEnv = std::getenv("BW_NET_URL");
    const std::string url = urlEnv ? urlEnv : "ws://127.0.0.1:9879";
    bw::net::NetworkClient client(url);

    int failures = 0;
    auto check = [&](const char *name, bool ok) {
        if (!ok) {
            ++failures;
            std::printf("FAIL  %s\n", name);
        }
    };

    check("connect+auth", client.connectAndAuth("cpp_e2e", "secret", false));
    check("auth_ok", waitType(client, "auth_ok"));

    client.createRoom("E2E", "E2E", "", "classic");
    check("room_created", waitType(client, "room_created"));

    client.startGame();
    check("game_starting", waitType(client, "game_starting"));
    check("game_started", waitType(client, "game_started", nullptr, 8.0));

    const double pos[3] = {4.0, 60.0, 4.0};
    client.sendInput(pos, 1.25, 1, 0, 5, 1, 88.0, true);
    // the input is applied on the next server tick: poll until the
    // broadcast state reflects it
    nlohmann::json state;
    bool foundSelf = false, synced = false;
    const auto start = std::chrono::steady_clock::now();
    while (!synced &&
           std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                         start)
                   .count() < 3.0) {
        nlohmann::json message;
        if (!waitType(client, "state_update", &message, 1.0))
            break;
        if (!message.contains("players"))
            continue;
        for (const auto &p : message["players"]) {
            if (p.value("id", 0) != client.state.playerId)
                continue;
            foundSelf = true;
            state = message;
            if (p.value("weapon", -1) == 1 &&
                std::abs(p.value("hp", 0.0) - 88.0) < 0.01)
                synced = true;
        }
    }
    check("state_update", !state.is_null());
    check("state has self", foundSelf);
    if (foundSelf && state.contains("players")) {
        for (const auto &p : state["players"]) {
            if (p.value("id", 0) == client.state.playerId) {
                check("state pos", p.contains("pos") && p["pos"].is_array());
                check("state hp", std::abs(p.value("hp", 0.0) - 88.0) < 0.01);
                check("state weapon", p.value("weapon", -1) == 1);
            }
        }
    }

    client.sendTerrainModify(3, 4, 5, "dig", 2);
    check("terrain_change", waitType(client, "terrain_change"));

    client.sendChat("salut e2e");
    check("chat", waitType(client, "chat"));

    client.savePlayerData({{"hp", 42}, {"seed", 99}});
    check("save_data_result", waitType(client, "save_data_result"));
    client.loadPlayerData();
    nlohmann::json loaded;
    check("load_data_result", waitType(client, "load_data_result", &loaded));
    check("player data roundtrip",
          loaded.value("data", nlohmann::json::object()).value("hp", 0) == 42);

    client.leaveRoom();
    client.disconnect();

    std::printf("%s\n", failures == 0 ? "SERVER NET OK" : "SERVER NET FAIL");
    return failures == 0 ? 0 : 1;
}
