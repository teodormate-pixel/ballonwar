// ============================================================
// BalloonWar game server (C++ port of signaling_server/server.js)
//
// Same JSON protocol as the Node server so the C++/Python
// clients work unchanged: auth, rooms, ready/start, 20 Hz state
// updates, terrain modifications, chat and player data.
//
// Accounts use bcrypt (libcrypt, $2b$ - compatible with
// bcryptjs hashes) and persist to a JSON file; without MySQL
// headers available the DB-backed room/terrain tables are kept
// in memory (the Node server did the same when the DB was down).
// ============================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

#include "wsserver.h"

namespace gamesrv {

struct GameMode {
    std::string id;
    std::string name;
    std::string desc;
    int timeLimit = 0;
    int minPlayers = 1;
    int maxPlayers = 8;
};

struct Config {
    std::string bind = "0.0.0.0";
    int port = 8765;
    std::string tlsCert;
    std::string tlsKey;
    int tickRate = 20;
    int bcryptRounds = 10;
    int maxPlayersPerRoom = 8;
    int roomCodeLength = 4;
    std::string usersFile;
    std::vector<GameMode> gameModes;

    static Config fromEnv();
};

class Server {
  public:
    explicit Server(Config config);
    ~Server();

    bool start(std::string &error);
    void run(); // blocks until stop() / interrupted
    void stop();
    // set from a signal handler; the run loop exits as soon as possible
    std::atomic<bool> interrupted{false};

    // exposed for tests
    size_t roomCount() const { return rooms_.size(); }
    size_t userCount() const { return users_.size(); }

  private:
    struct User {
        int id = 0;
        std::string username;
        std::string hash;
        nlohmann::json playerData;
    };
    struct Client {
        int playerId = 0;
        std::string username;
        std::string roomId;
    };
    struct Player {
        int id = 0;
        std::string name;
        double x = 0, y = 50, z = 0;
        double rot = 0, hp = 100;
        int weapon = 0;
        bool alive = true;
        int characterId = 0;
        bool ready = false;
        int kills = 0, deaths = 0, score = 0;
        bool hasInput = false;
        nlohmann::json pendingInput;
    };
    struct TerrainMod {
        int x = 0, y = 0, z = 0;
        int blockType = 0;
        std::string action;
    };
    struct Room {
        std::string id;
        std::string name;
        ws::Server::ConnId host = 0;
        int hostId = 0;
        std::string password;
        nlohmann::json settings;
        uint32_t seed = 0;
        std::string status = "lobby"; // lobby | countdown | playing | finished
        std::unordered_map<ws::Server::ConnId, Player> players;
        std::vector<TerrainMod> terrain;
        int64_t startedAt = 0;
        int64_t endsAt = 0;
        int64_t countdownAt = 0;
        int64_t created = 0;
    };

    // transport callbacks
    void onOpen(ws::Server::ConnId id);
    void onMessage(ws::Server::ConnId id, const std::string &raw);
    void onClose(ws::Server::ConnId id);

    // message handlers
    void handleAuth(ws::Server::ConnId id, const nlohmann::json &msg);
    void handleRegister(ws::Server::ConnId id, const nlohmann::json &msg);
    void handleCreateRoom(ws::Server::ConnId id, Client &client,
                          const nlohmann::json &msg);
    void handleJoinRoom(ws::Server::ConnId id, Client &client,
                        const nlohmann::json &msg);
    void handleLeaveRoom(ws::Server::ConnId id, Client &client);
    void handleListRooms(ws::Server::ConnId id);
    void handlePlayerReady(ws::Server::ConnId id, Client &client,
                           const nlohmann::json &msg);
    void handleStartGame(ws::Server::ConnId id, Client &client);
    void handlePlayerInput(ws::Server::ConnId id, Client &client,
                           const nlohmann::json &msg);
    void handleTerrainModify(ws::Server::ConnId id, Client &client,
                             const nlohmann::json &msg);
    void handleChat(ws::Server::ConnId id, Client &client,
                    const nlohmann::json &msg);
    void handleSaveData(ws::Server::ConnId id, Client &client,
                        const nlohmann::json &msg);
    void handleLoadData(ws::Server::ConnId id, Client &client);
    void handleDeleteAccount(ws::Server::ConnId id, Client &client);

    // rooms / game loop
    Room *findRoomByConn(ws::Server::ConnId id);
    void broadcast(Room &room, const nlohmann::json &message,
                   ws::Server::ConnId exclude = 0);
    void tick(int64_t nowMs);
    void expireRooms(int64_t nowMs);
    nlohmann::json serializePlayers(const Room &room) const;
    nlohmann::json roomList() const;
    std::string createRoomId();

    // users / storage
    User *findUser(const std::string &username);
    int createUser(const std::string &username, const std::string &hash);
    void loadUsers();
    void saveUsers();
    static std::string bcryptHash(const std::string &password, int rounds);
    static bool bcryptVerify(const std::string &password,
                             const std::string &hash);
    static int64_t nowMs();
    static int64_t steadyMs();

    Config config_;
    ws::Server ws_;
    std::unordered_map<ws::Server::ConnId, Client> clients_;
    std::unordered_map<std::string, User> users_;
    std::unordered_map<std::string, Room> rooms_;
    int nextUserId_ = 1;
    bool dirty_ = false;
    int64_t lastSave_ = 0;
    bool running_ = false;
};

} // namespace gamesrv
