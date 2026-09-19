// ============================================================
// BalloonWar game server - entry point
//
//   ./balloonwar-server
//
// Environment: PORT, BIND, TLS_CERT, TLS_KEY, BW_TICK_RATE,
// BW_BCRYPT_ROUNDS, BW_MAX_PLAYERS, BW_USERS_FILE.
// ============================================================

#include <csignal>
#include <cstdio>
#include <cstdlib>

#include "gameserver.h"

namespace {

gamesrv::Server *g_server = nullptr;

void onSignal(int) {
    if (g_server)
        g_server->interrupted.store(true);
}

} // namespace

int main() {
    gamesrv::Config cfg = gamesrv::Config::fromEnv();

    if (std::getenv("DB_HOST"))
        std::fprintf(stderr,
                     "[db] MySQL support not compiled in; using the "
                     "in-memory/JSON store (%s)\n",
                     cfg.usersFile.c_str());

    gamesrv::Server server(cfg);
    g_server = &server;
    std::signal(SIGINT, onSignal);
    std::signal(SIGTERM, onSignal);

    std::string error;
    if (!server.start(error)) {
        std::fprintf(stderr, "server start failed: %s\n", error.c_str());
        return 1;
    }
    server.run();
    std::printf("server stopped\n");
    return 0;
}
