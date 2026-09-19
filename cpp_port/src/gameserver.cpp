#include "gameserver.h"

#include "bcrypt_portable.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>

namespace gamesrv {

namespace {

constexpr double WORLD_BOTTOM = -80.0;
constexpr double RESPAWN_Y = 150.0;
constexpr double MAX_MOVE = 2.0;
constexpr int64_t COUNTDOWN_MS = 3000;
constexpr int64_t ROOM_EXPIRE_MS = 3600000;   // 1 h, empty lobbies
constexpr int64_t SAVE_INTERVAL_MS = 5000;
constexpr int64_t EXPIRE_CHECK_MS = 300000;   // 5 min

struct CharacterInfo {
    int id;
    const char *name;
    int baseHealth;
};

const CharacterInfo kCharacters[] = {
    {1, "Bombardier", 100},
    {2, "Scout", 80},
    {3, "Tank", 150},
    {4, "Engineer", 90},
};

const CharacterInfo *characterById(int id) {
    for (const auto &c : kCharacters)
        if (c.id == id)
            return &c;
    return nullptr;
}

std::string homeDir() {
    const char *home = std::getenv("HOME");
    return home ? home : ".";
}

std::mt19937_64 &rng() {
    static std::mt19937_64 engine(std::random_device{}());
    return engine;
}

} // namespace

Config Config::fromEnv() {
    Config cfg;
    if (const char *v = std::getenv("PORT"))
        cfg.port = std::atoi(v);
    if (const char *v = std::getenv("BIND"))
        cfg.bind = v;
    if (const char *v = std::getenv("TLS_CERT"))
        cfg.tlsCert = v;
    if (const char *v = std::getenv("TLS_KEY"))
        cfg.tlsKey = v;
    if (const char *v = std::getenv("BW_TICK_RATE"))
        cfg.tickRate = std::max(1, std::atoi(v));
    if (const char *v = std::getenv("BW_BCRYPT_ROUNDS"))
        cfg.bcryptRounds = std::clamp(std::atoi(v), 4, 15);
    if (const char *v = std::getenv("BW_MAX_PLAYERS"))
        cfg.maxPlayersPerRoom = std::max(1, std::atoi(v));
    cfg.usersFile = homeDir() + "/.local/share/balloonwar/server_users.json";
    if (const char *v = std::getenv("BW_USERS_FILE"))
        cfg.usersFile = v;
    cfg.gameModes = {
        {"classic", "Classic", "5 minute: sparge cat mai multe baloane", 300,
         1, 8},
        {"balloon_vs_player", "Balloon vs Player",
         "Survival solo/co-op impotriva baloanelor AI", 0, 1, 8},
        {"sandbox", "Sandbox", "Constructie libera fara atacuri AI", 0, 1, 8},
    };
    return cfg;
}

namespace {
ws::Options wsOptions(const Config &cfg) {
    ws::Options opts;
    opts.bind = cfg.bind;
    opts.port = cfg.port;
    opts.tlsCert = cfg.tlsCert;
    opts.tlsKey = cfg.tlsKey;
    return opts;
}
} // namespace

Server::Server(Config config)
    : config_(std::move(config)), ws_(wsOptions(config_)) {}

Server::~Server() { stop(); }

int64_t Server::nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

int64_t Server::steadyMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

// ------------------------------------------------------------
// bcrypt (libcrypt; $2b$ hashes are compatible with bcryptjs)
// ------------------------------------------------------------

std::string Server::bcryptHash(const std::string &password, int rounds) {
    return bcrypt::hash(password, rounds);
}

bool Server::bcryptVerify(const std::string &password,
                          const std::string &hash) {
    if (hash.empty())
        return false;
    return bcrypt::verify(password, hash);
}

// ------------------------------------------------------------
// users / persistence
// ------------------------------------------------------------

Server::User *Server::findUser(const std::string &username) {
    auto it = users_.find(username);
    return it == users_.end() ? nullptr : &it->second;
}

int Server::createUser(const std::string &username,
                       const std::string &hash) {
    User user;
    user.id = nextUserId_++;
    user.username = username;
    user.hash = hash;
    users_[username] = user;
    dirty_ = true;
    return user.id;
}

void Server::loadUsers() {
    std::ifstream f(config_.usersFile);
    if (!f)
        return;
    nlohmann::json j;
    try {
        f >> j;
    } catch (...) {
        std::fprintf(stderr, "[db] cannot parse %s\n",
                     config_.usersFile.c_str());
        return;
    }
    nextUserId_ = j.value("next_id", 1);
    for (const auto &u : j.value("users", nlohmann::json::array())) {
        User user;
        user.id = u.value("id", 0);
        user.username = u.value("username", "");
        user.hash = u.value("password_hash", "");
        if (u.contains("player_data"))
            user.playerData = u["player_data"];
        if (user.id > 0 && !user.username.empty()) {
            nextUserId_ = std::max(nextUserId_, user.id + 1);
            users_[user.username] = user;
        }
    }
    std::printf("[db] %zu accounts loaded from %s\n", users_.size(),
                config_.usersFile.c_str());
}

void Server::saveUsers() {
    if (!dirty_)
        return;
    nlohmann::json j;
    j["next_id"] = nextUserId_;
    j["users"] = nlohmann::json::array();
    for (const auto &[name, user] : users_) {
        (void)name;
        nlohmann::json u{{"id", user.id},
                         {"username", user.username},
                         {"password_hash", user.hash}};
        if (!user.playerData.is_null())
            u["player_data"] = user.playerData;
        j["users"].push_back(std::move(u));
    }
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(config_.usersFile).parent_path(), ec);
    const std::string tmp = config_.usersFile + ".tmp";
    {
        std::ofstream f(tmp, std::ios::trunc);
        if (!f) {
            std::fprintf(stderr, "[db] cannot write %s\n", tmp.c_str());
            return;
        }
        f << j.dump();
    }
    std::filesystem::rename(tmp, config_.usersFile, ec);
    dirty_ = false;
    lastSave_ = steadyMs();
}

// ------------------------------------------------------------
// lifecycle
// ------------------------------------------------------------

bool Server::start(std::string &error) {
    loadUsers();
    ws_.onOpen = [this](ws::Server::ConnId id) { onOpen(id); };
    ws_.onMessage = [this](ws::Server::ConnId id, const std::string &raw) {
        onMessage(id, raw);
    };
    ws_.onClose = [this](ws::Server::ConnId id) { onClose(id); };
    if (!ws_.start(error))
        return false;
    std::printf("Balloon War C++ server on %s:%d%s (tick %d Hz)\n",
                config_.bind.c_str(), config_.port,
                config_.tlsCert.empty() ? "" : " tls", config_.tickRate);
    return true;
}

void Server::stop() {
    running_ = false;
    saveUsers();
    ws_.stop();
}

void Server::run() {
    running_ = true;
    const int64_t tickMs = std::max<int64_t>(1, 1000 / config_.tickRate);
    int64_t nextTick = steadyMs();
    int64_t nextExpire = steadyMs() + EXPIRE_CHECK_MS;
    while (running_ && !interrupted.load()) {
        int timeout = (int)std::max<int64_t>(0, nextTick - steadyMs());
        if (timeout > 50)
            timeout = 50;
        ws_.poll(timeout);
        const int64_t after = steadyMs();
        if (after >= nextTick) {
            nextTick += tickMs;
            if (nextTick <= after)
                nextTick = after + tickMs;
            tick(nowMs());
        }
        if (after >= nextExpire) {
            nextExpire = after + EXPIRE_CHECK_MS;
            expireRooms(nowMs());
        }
        if (dirty_ && after - lastSave_ >= SAVE_INTERVAL_MS)
            saveUsers();
    }
    saveUsers();
}

// ------------------------------------------------------------
// transport callbacks
// ------------------------------------------------------------

void Server::onOpen(ws::Server::ConnId id) {
    std::printf("[net] connect %s (conn %llu)\n", ws_.peerAddress(id).c_str(),
                (unsigned long long)id);
}

void Server::onClose(ws::Server::ConnId id) {
    auto it = clients_.find(id);
    if (it != clients_.end()) {
        handleLeaveRoom(id, it->second);
        std::printf("[net] disconnect %s (id=%d)\n", it->second.username.c_str(),
                    it->second.playerId);
        clients_.erase(it);
    }
}

void Server::onMessage(ws::Server::ConnId id, const std::string &raw) {
    nlohmann::json msg;
    try {
        msg = nlohmann::json::parse(raw);
    } catch (...) {
        return;
    }
    if (!msg.is_object())
        return;
    const std::string type = msg.value("type", "");

    if (type == "ping") {
        ws_.send(id, nlohmann::json{{"type", "pong"}}.dump());
        return;
    }
    if (type == "auth")
        return handleAuth(id, msg);
    if (type == "register_user")
        return handleRegister(id, msg);

    auto it = clients_.find(id);
    if (it == clients_.end()) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Not authenticated"}}
                         .dump());
        return;
    }
    Client &client = it->second;

    if (type == "create_room")
        return handleCreateRoom(id, client, msg);
    if (type == "join_room")
        return handleJoinRoom(id, client, msg);
    if (type == "leave_room")
        return handleLeaveRoom(id, client);
    if (type == "list_rooms")
        return handleListRooms(id);
    if (type == "player_ready")
        return handlePlayerReady(id, client, msg);
    if (type == "start_game")
        return handleStartGame(id, client);
    if (type == "player_input")
        return handlePlayerInput(id, client, msg);
    if (type == "terrain_modify")
        return handleTerrainModify(id, client, msg);
    if (type == "chat")
        return handleChat(id, client, msg);
    if (type == "save_data")
        return handleSaveData(id, client, msg);
    if (type == "load_data")
        return handleLoadData(id, client);
    if (type == "delete_account")
        return handleDeleteAccount(id, client);

    ws_.send(id, nlohmann::json{{"type", "error"},
                                {"message", "Unknown message type: " + type}}
                     .dump());
}

// ------------------------------------------------------------
// auth
// ------------------------------------------------------------

void Server::handleAuth(ws::Server::ConnId id, const nlohmann::json &msg) {
    const std::string username = msg.value("username", "");
    const std::string password = msg.value("password", "");
    if (username.empty() || password.empty()) {
        ws_.send(id, nlohmann::json{{"type", "auth_error"},
                                    {"message", "Username and password required"}}
                         .dump());
        return;
    }
    if (username.size() > 50) {
        ws_.send(id, nlohmann::json{{"type", "auth_error"},
                                    {"message", "Username too long"}}
                         .dump());
        return;
    }

    User *user = findUser(username);
    if (user) {
        if (!bcryptVerify(password, user->hash)) {
            std::printf("[auth] FAIL %s (wrong password) from %s\n",
                        username.c_str(), ws_.peerAddress(id).c_str());
            ws_.send(id, nlohmann::json{{"type", "auth_error"},
                                        {"message", "Wrong password"}}
                             .dump());
            return;
        }
    } else {
        const std::string hash = bcryptHash(password, config_.bcryptRounds);
        if (hash.empty()) {
            ws_.send(id, nlohmann::json{{"type", "auth_error"},
                                        {"message", "Server error"}}
                             .dump());
            return;
        }
        createUser(username, hash);
        user = findUser(username);
    }

    Client client;
    client.playerId = user->id;
    client.username = user->username;
    clients_[id] = client;

    nlohmann::json modes = nlohmann::json::array();
    for (const auto &m : config_.gameModes)
        modes.push_back({{"id", m.id},
                         {"name", m.name},
                         {"desc", m.desc},
                         {"time_limit", m.timeLimit},
                         {"min_players", m.minPlayers},
                         {"max_players", m.maxPlayers}});
    ws_.send(id, nlohmann::json{{"type", "auth_ok"},
                                {"player_id", user->id},
                                {"username", user->username},
                                {"game_modes", modes}}
                     .dump());
    std::printf("[auth] OK %s (id=%d)\n", user->username.c_str(), user->id);
}

void Server::handleRegister(ws::Server::ConnId id,
                            const nlohmann::json &msg) {
    const std::string username = msg.value("username", "");
    const std::string password = msg.value("password", "");
    if (username.empty() || password.empty()) {
        ws_.send(id, nlohmann::json{{"type", "register_result"},
                                    {"success", false},
                                    {"message", "Username and password required"}}
                         .dump());
        return;
    }
    if (findUser(username)) {
        ws_.send(id, nlohmann::json{{"type", "register_result"},
                                    {"success", false},
                                    {"message", "Username already exists"}}
                         .dump());
        return;
    }
    const std::string hash = bcryptHash(password, config_.bcryptRounds);
    if (hash.empty()) {
        ws_.send(id, nlohmann::json{{"type", "register_result"},
                                    {"success", false},
                                    {"message", "Server error"}}
                         .dump());
        return;
    }
    createUser(username, hash);
    ws_.send(id, nlohmann::json{{"type", "register_result"},
                                {"success", true},
                                {"message", "Account created"}}
                     .dump());
}

// ------------------------------------------------------------
// rooms
// ------------------------------------------------------------

std::string Server::createRoomId() {
    static const char *chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    std::uniform_int_distribution<int> dist(0, 31);
    for (;;) {
        std::string id;
        for (int i = 0; i < config_.roomCodeLength; ++i)
            id.push_back(chars[dist(rng())]);
        if (!rooms_.count(id))
            return id;
    }
}

Server::Room *Server::findRoomByConn(ws::Server::ConnId id) {
    for (auto &[rid, room] : rooms_) {
        (void)rid;
        if (room.host == id || room.players.count(id))
            return &room;
    }
    return nullptr;
}

void Server::broadcast(Room &room, const nlohmann::json &message,
                       ws::Server::ConnId exclude) {
    const std::string data = message.dump();
    bool hostSent = false;
    for (const auto &[conn, player] : room.players) {
        (void)player;
        if (conn == exclude)
            continue;
        if (ws_.send(conn, data) && conn == room.host)
            hostSent = true;
    }
    if (!hostSent && room.host != exclude)
        ws_.send(room.host, data);
}

void Server::handleCreateRoom(ws::Server::ConnId id, Client &client,
                              const nlohmann::json &msg) {
    if (findRoomByConn(id)) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Already in a room"}}
                         .dump());
        return;
    }

    Room room;
    room.id = createRoomId();
    room.name = msg.value("name", client.username + "'s Game");
    room.host = id;
    room.hostId = client.playerId;
    room.password = msg.value("password", "");
    room.created = nowMs();

    const nlohmann::json settings =
        msg.contains("settings") && msg["settings"].is_object()
            ? msg["settings"]
            : nlohmann::json::object();
    std::string gameMode = settings.value("game_mode", "classic");
    const GameMode *mode = nullptr;
    for (const auto &m : config_.gameModes)
        if (m.id == gameMode)
            mode = &m;
    if (!mode) {
        gameMode = "classic";
        for (const auto &m : config_.gameModes)
            if (m.id == gameMode)
                mode = &m;
    }
    uint32_t seed = msg.value("seed", 0u);
    if (seed == 0)
        seed = (uint32_t)(rng()() % 2147483647u);
    room.seed = seed;
    room.settings = {
        {"seed", seed},
        {"max_players",
         settings.value("max_players", config_.maxPlayersPerRoom)},
        {"terrain_type", settings.value("terrain_type", "default")},
        {"game_mode", gameMode},
        {"time_limit",
         settings.contains("time_limit") && settings["time_limit"].is_number()
             ? settings["time_limit"].get<int>()
             : (mode ? mode->timeLimit : 0)},
        {"kill_limit", settings.value("kill_limit", 20)},
        {"allow_chat", settings.value("allow_chat", true)},
    };

    Player host;
    host.id = client.playerId;
    host.name = client.username;
    host.characterId = 1;
    room.players[id] = host;
    client.roomId = room.id;
    rooms_[room.id] = std::move(room);
    std::printf("[room] %s created by %s\n", client.roomId.c_str(),
                client.username.c_str());

    ws_.send(id, nlohmann::json{
                     {"type", "room_created"},
                     {"room_id", client.roomId},
                     {"player_id", client.playerId},
                     {"settings", rooms_[client.roomId].settings},
                     {"players", nlohmann::json::array(
                                     {{{"id", client.playerId},
                                       {"name", client.username},
                                       {"characterId", 1}}})}}
                     .dump());
}

void Server::handleJoinRoom(ws::Server::ConnId id, Client &client,
                            const nlohmann::json &msg) {
    if (findRoomByConn(id)) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Already in a room"}}
                         .dump());
        return;
    }
    const std::string roomId = msg.value("room_id", "");
    auto it = rooms_.find(roomId);
    if (it == rooms_.end()) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Room not found"}}
                         .dump());
        return;
    }
    Room &room = it->second;
    if (room.status != "lobby") {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Game already started"}}
                         .dump());
        return;
    }
    const std::string password = msg.value("password", "");
    if (!room.password.empty() && password != room.password) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Wrong password"}}
                         .dump());
        return;
    }
    const int maxPlayers = room.settings.value("max_players", 8);
    if ((int)room.players.size() >= maxPlayers) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Room is full"}}
                         .dump());
        return;
    }

    Player player;
    player.id = client.playerId;
    player.name = client.username;
    player.characterId = 0;
    room.players[id] = player;
    client.roomId = room.id;

    nlohmann::json players = nlohmann::json::array();
    players.push_back({{"id", client.playerId},
                       {"name", client.username},
                       {"characterId", nullptr}});
    for (const auto &[conn, p] : room.players) {
        if (conn == id)
            continue;
        players.push_back({{"id", p.id},
                           {"name", p.name},
                           {"characterId", p.characterId == 0
                                               ? nlohmann::json(nullptr)
                                               : nlohmann::json(p.characterId)}});
    }
    ws_.send(id, nlohmann::json{{"type", "joined"},
                                {"room_id", room.id},
                                {"player_id", client.playerId},
                                {"players", players},
                                {"settings", room.settings},
                                {"seed", room.seed}}
                     .dump());
    broadcast(room,
              nlohmann::json{{"type", "player_joined"},
                             {"player_id", client.playerId},
                             {"name", client.username}},
              id);
    std::printf("[room] %s joined %s\n", client.username.c_str(),
                room.id.c_str());
}

void Server::handleLeaveRoom(ws::Server::ConnId id, Client &client) {
    Room *room = findRoomByConn(id);
    if (!room)
        return;
    client.roomId.clear();

    if (room->host == id) {
        broadcast(*room, nlohmann::json{{"type", "room_closed"},
                                        {"message", "Host left"}});
        std::printf("[room] %s closed (host left)\n", room->id.c_str());
        rooms_.erase(room->id);
        return;
    }
    auto pit = room->players.find(id);
    if (pit != room->players.end()) {
        const Player player = pit->second;
        room->players.erase(pit);
        broadcast(*room, nlohmann::json{{"type", "player_left"},
                                        {"player_id", player.id}});
        std::printf("[room] %s left %s\n", player.name.c_str(),
                    room->id.c_str());
        if (room->players.empty()) {
            rooms_.erase(room->id);
            std::printf("[room] %s empty -> deleted\n", room->id.c_str());
        }
    }
}

void Server::handleListRooms(ws::Server::ConnId id) {
    ws_.send(id, nlohmann::json{{"type", "room_list"}, {"rooms", roomList()}}
                     .dump());
}

nlohmann::json Server::roomList() const {
    nlohmann::json list = nlohmann::json::array();
    for (const auto &[rid, room] : rooms_) {
        if (room.status != "lobby")
            continue;
        std::string modeName = room.settings.value("game_mode", "classic");
        for (const auto &m : config_.gameModes)
            if (m.id == modeName)
                modeName = m.name;
        list.push_back({{"room_id", rid},
                        {"name", room.name},
                        {"player_count", (int)room.players.size()},
                        {"max_players", room.settings.value("max_players", 8)},
                        {"has_password", !room.password.empty()},
                        {"terrain_type", room.settings.value("terrain_type",
                                                             "default")},
                        {"game_mode", room.settings.value("game_mode",
                                                          "classic")},
                        {"game_mode_name", modeName}});
    }
    return list;
}

void Server::handlePlayerReady(ws::Server::ConnId id, Client &client,
                               const nlohmann::json &msg) {
    (void)client;
    Room *room = findRoomByConn(id);
    if (!room) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Not in a room"}}
                         .dump());
        return;
    }
    const int charId = msg.value("character_id", 1);
    const CharacterInfo *character = characterById(charId);
    if (!character) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Invalid character"}}
                         .dump());
        return;
    }
    auto pit = room->players.find(id);
    if (pit != room->players.end()) {
        pit->second.characterId = charId;
        pit->second.ready = true;
        pit->second.hp = character->baseHealth;
    }
    broadcast(*room, nlohmann::json{{"type", "player_ready"},
                                    {"player_id", pit != room->players.end()
                                                      ? pit->second.id
                                                      : 0},
                                    {"character_id", charId},
                                    {"name", pit != room->players.end()
                                                 ? pit->second.name
                                                 : std::string()}});
}

void Server::handleStartGame(ws::Server::ConnId id, Client &client) {
    (void)client;
    Room *room = findRoomByConn(id);
    if (!room) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Not in a room"}}
                         .dump());
        return;
    }
    if (room->host != id) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Only host can start"}}
                         .dump());
        return;
    }
    if (room->players.size() < 1) {
        ws_.send(id, nlohmann::json{{"type", "error"},
                                    {"message", "Need at least 1 other player"}}
                         .dump());
        return;
    }

    const double pi = 3.14159265358979323846;
    int spawnIndex = 0;
    const int count = (int)room->players.size();
    for (auto &[conn, player] : room->players) {
        (void)conn;
        const double angle = (count > 0 ? (double)spawnIndex / count : 0.0) *
                             pi * 2.0;
        player.x = std::cos(angle) * 10.0;
        player.z = std::sin(angle) * 10.0;
        player.y = 50.0;
        if (player.characterId == 0)
            player.characterId = 1;
        ++spawnIndex;
    }
    room->status = "countdown";
    room->countdownAt = nowMs() + COUNTDOWN_MS;
    broadcast(*room, nlohmann::json{{"type", "game_starting"},
                                    {"countdown", 3}});
    std::printf("[game] room %s starting in 3s\n", room->id.c_str());
}

nlohmann::json Server::serializePlayers(const Room &room) const {
    nlohmann::json list = nlohmann::json::array();
    for (const auto &[conn, p] : room.players) {
        (void)conn;
        list.push_back(
            {{"id", p.id},
             {"name", p.name},
             {"pos", {std::round(p.x * 100.0) / 100.0,
                      std::round(p.y * 100.0) / 100.0,
                      std::round(p.z * 100.0) / 100.0}},
             {"rot", p.rot},
             {"hp", p.hp},
             {"weapon", p.weapon},
             {"alive", p.alive},
             {"characterId", p.characterId},
             {"kills", p.kills},
             {"deaths", p.deaths},
             {"score", p.score}});
    }
    return list;
}

void Server::tick(int64_t now) {
    for (auto &[rid, room] : rooms_) {
        (void)rid;
        if (room.status == "countdown" && now >= room.countdownAt) {
            const int timeLimit =
                std::max(0, room.settings.value("time_limit", 0));
            room.startedAt = now;
            room.endsAt = timeLimit > 0 ? now + (int64_t)timeLimit * 1000 : 0;
            for (auto &[conn, player] : room.players) {
                (void)conn;
                player.kills = 0;
                player.deaths = 0;
                player.score = 0;
                player.alive = true;
            }
            room.status = "playing";
            nlohmann::json terrain = nlohmann::json::array();
            for (const auto &t : room.terrain)
                terrain.push_back({{"pos", {t.x, t.y, t.z}},
                                   {"block_type", t.blockType},
                                   {"action_type", t.action}});
            broadcast(room, nlohmann::json{{"type", "game_started"},
                                           {"seed", room.seed},
                                           {"game_mode",
                                            room.settings.value("game_mode",
                                                                "classic")},
                                           {"time_limit", timeLimit},
                                           {"started_at", room.startedAt},
                                           {"ends_at", room.endsAt},
                                           {"terrain_modifications", terrain}});
            std::printf("[game] room %s started\n", room.id.c_str());
            continue;
        }
        if (room.status != "playing")
            continue;
        if (room.endsAt != 0 && now >= room.endsAt) {
            room.status = "finished";
            broadcast(room, nlohmann::json{
                                {"type", "match_ended"},
                                {"game_mode",
                                 room.settings.value("game_mode", "classic")},
                                {"time_remaining", 0},
                                {"players", serializePlayers(room)}});
            continue;
        }
        for (auto &[conn, player] : room.players) {
            (void)conn;
            player.hasInput = false;
            player.pendingInput = nlohmann::json();
        }
        broadcast(room,
                  nlohmann::json{{"type", "state_update"},
                                 {"tick", now},
                                 {"game_mode",
                                  room.settings.value("game_mode", "classic")},
                                 {"time_remaining",
                                  room.endsAt == 0
                                      ? nlohmann::json(nullptr)
                                      : nlohmann::json(std::max(
                                            0.0, (double)(room.endsAt - now) /
                                                     1000.0))},
                                 {"match_finished", false},
                                 {"players", serializePlayers(room)}});
    }
}

void Server::expireRooms(int64_t now) {
    for (auto it = rooms_.begin(); it != rooms_.end();) {
        Room &room = it->second;
        if (room.status == "lobby" && now - room.created > ROOM_EXPIRE_MS &&
            room.players.empty()) {
            std::printf("[room] %s expired\n", room.id.c_str());
            it = rooms_.erase(it);
        } else {
            ++it;
        }
    }
}

// ------------------------------------------------------------
// gameplay messages
// ------------------------------------------------------------

void Server::handlePlayerInput(ws::Server::ConnId id, Client &client,
                               const nlohmann::json &msg) {
    (void)client;
    Room *room = findRoomByConn(id);
    if (!room || room->status != "playing")
        return;
    auto pit = room->players.find(id);
    if (pit == room->players.end())
        return;
    Player &player = pit->second;

    if ((msg.contains("keys") && msg["keys"].is_object()) ||
        msg.contains("rot_x") || msg.contains("actions"))
        player.pendingInput = msg;

    if (msg.contains("pos") && msg["pos"].is_array() &&
        msg["pos"].size() == 3) {
        const double px = msg["pos"][0].get<double>();
        const double pyRaw = msg["pos"][1].get<double>();
        const double pz = msg["pos"][2].get<double>();
        const double py = pyRaw < WORLD_BOTTOM ? RESPAWN_Y : pyRaw;
        const double dx = px - player.x;
        const double dz = pz - player.z;
        const double dy = py - player.y;
        const double dist = std::sqrt(dx * dx + dz * dz);
        if (dist <= MAX_MOVE) {
            player.x = px;
            player.y = py;
            player.z = pz;
        } else {
            const double ratio = MAX_MOVE / dist;
            player.x += dx * ratio;
            player.z += dz * ratio;
            player.y += dy * ratio;
        }
    }
    if (msg.contains("actions") && msg["actions"].is_object() &&
        msg["actions"].contains("weapon"))
        player.weapon = msg["actions"]["weapon"].get<int>();
    if (msg.contains("rot_x") && msg["rot_x"].is_number())
        player.rot = msg["rot_x"].get<double>();
    if (msg.contains("score") && msg["score"].is_number_integer()) {
        const int score = msg["score"].get<int>();
        if (score >= player.score && score <= player.score + 1000)
            player.score = score;
    }
    if (msg.contains("kills") && msg["kills"].is_number_integer()) {
        const int kills = msg["kills"].get<int>();
        if (kills >= player.kills && kills <= player.kills + 50)
            player.kills = kills;
    }
    if (msg.contains("hp") && msg["hp"].is_number()) {
        const double hp = msg["hp"].get<double>();
        player.hp = std::max(0.0, std::min(1000.0, hp));
    }
    if (msg.contains("alive") && msg["alive"].is_boolean()) {
        const bool alive = msg["alive"].get<bool>();
        if (player.alive && !alive)
            player.deaths += 1;
        player.alive = alive;
    }
}

void Server::handleTerrainModify(ws::Server::ConnId id, Client &client,
                                 const nlohmann::json &msg) {
    Room *room = findRoomByConn(id);
    if (!room || room->status != "playing")
        return;
    if (!msg.contains("pos") || !msg["pos"].is_array() ||
        msg["pos"].size() != 3)
        return;
    TerrainMod mod;
    mod.x = (int)msg["pos"][0].get<double>();
    mod.y = (int)msg["pos"][1].get<double>();
    mod.z = (int)msg["pos"][2].get<double>();
    mod.blockType = msg.value("block_type", 0);
    mod.action = msg.value("action_type", "dig");
    room->terrain.push_back(mod);
    broadcast(*room, nlohmann::json{{"type", "terrain_change"},
                                    {"player_id", client.playerId},
                                    {"pos", {mod.x, mod.y, mod.z}},
                                    {"block_type", mod.blockType},
                                    {"action_type", mod.action}});
}

void Server::handleChat(ws::Server::ConnId id, Client &client,
                        const nlohmann::json &msg) {
    Room *room = findRoomByConn(id);
    if (!room || !room->settings.value("allow_chat", true))
        return;
    broadcast(*room, nlohmann::json{{"type", "chat"},
                                    {"player_id", client.playerId},
                                    {"name", client.username},
                                    {"message", msg.value("message", "")}});
}

// ------------------------------------------------------------
// account data
// ------------------------------------------------------------

void Server::handleSaveData(ws::Server::ConnId id, Client &client,
                            const nlohmann::json &msg) {
    User *user = nullptr;
    for (auto &[name, u] : users_)
        if (u.id == client.playerId) {
            user = &u;
            break;
        }
    if (!user) {
        ws_.send(id, nlohmann::json{{"type", "save_data_result"},
                                    {"success", false},
                                    {"message", "Server error"}}
                         .dump());
        return;
    }
    user->playerData =
        msg.contains("data") && msg["data"].is_object() ? msg["data"]
                                                        : nlohmann::json();
    dirty_ = true;
    ws_.send(id, nlohmann::json{{"type", "save_data_result"},
                                {"success", true}}
                     .dump());
}

void Server::handleLoadData(ws::Server::ConnId id, Client &client) {
    nlohmann::json data = nlohmann::json::object();
    for (const auto &[name, u] : users_)
        if (u.id == client.playerId) {
            data = u.playerData.is_null() ? nlohmann::json::object()
                                          : u.playerData;
            break;
        }
    ws_.send(id, nlohmann::json{{"type", "load_data_result"},
                                {"success", true},
                                {"data", data}}
                     .dump());
}

void Server::handleDeleteAccount(ws::Server::ConnId id, Client &client) {
    for (auto it = users_.begin(); it != users_.end(); ++it) {
        if (it->second.id == client.playerId) {
            users_.erase(it);
            dirty_ = true;
            break;
        }
    }
    Room *room = findRoomByConn(id);
    if (room)
        handleLeaveRoom(id, client);
    std::printf("[auth] account deleted: %s\n", client.username.c_str());
    clients_.erase(id);
    ws_.closeConn(id);
}

} // namespace gamesrv
