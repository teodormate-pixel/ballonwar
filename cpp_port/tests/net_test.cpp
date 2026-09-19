// ============================================================
// Network transport test: talks to tests/mock_ws_server.py
// (plain ws:// on 127.0.0.1:9876).
// ============================================================

#include <chrono>
#include <cstdio>
#include <thread>

#include "net.h"

int main() {
    const char* urlEnv = std::getenv("BW_NET_URL");
    const std::string url = urlEnv ? urlEnv : "ws://127.0.0.1:9876";
    bw::net::NetworkClient client(url);
    if (!client.connectAndAuth("probe", "secret", false)) {
        std::printf("connectAndAuth failed\n");
        return 1;
    }
    bool connected = false, authed = false, room = false, state = false,
         chat = false;
    const auto start = std::chrono::steady_clock::now();
    while (std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                         start)
               .count() < 8.0) {
        for (const auto& message : client.poll()) {
            const std::string type = message.value("type", "");
            if (type == "_connected")
                connected = true;
            if (type == "auth_ok")
                authed = true;
            if (type == "room_created")
                room = true;
            if (type == "state_update")
                state = true;
            if (type == "chat")
                chat = true;
        }
        if (authed && !room) {
            client.createRoom("Smoke", "T1", "", "classic");
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        } else if (room && !state) {
            const double pos[3] = {1.0, 2.0, 3.0};
            client.sendInput(pos, 0.5, 0, 0, 0, 0, 100.0, true);
            client.sendChat("salut");
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        } else if (state && chat) {
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    client.disconnect();

    std::printf("connected=%d authed=%d room=%d state=%d chat=%d\n",
                (int)connected, (int)authed, (int)room, (int)state, (int)chat);
    const bool ok = connected && authed && room && state && chat;
    std::printf("%s\n", ok ? "NET OK" : "NET FAIL");
    return ok ? 0 : 1;
}
