#include "net.h"

#include "netcompat.h"
#include "platform.h"

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <csignal>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>

#include "game.h"

namespace bw {
namespace net {

namespace {

const char* kB64 =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64(const unsigned char* data, size_t len) {
    std::string out;
    for (size_t i = 0; i < len; i += 3) {
        const unsigned int v = (unsigned int)data[i] << 16 |
                               (i + 1 < len ? (unsigned int)data[i + 1] << 8 : 0) |
                               (i + 2 < len ? (unsigned int)data[i + 2] : 0);
        out.push_back(kB64[(v >> 18) & 63]);
        out.push_back(kB64[(v >> 12) & 63]);
        out.push_back(i + 1 < len ? kB64[(v >> 6) & 63] : '=');
        out.push_back(i + 2 < len ? kB64[v & 63] : '=');
    }
    return out;
}

} // namespace

std::string NetworkClient::defaultUrl() {
    const char* env = std::getenv("BALLOONWAR_SERVER_URL");
    if (env && *env)
        return env;
    return "ws://62.171.162.154:8765";
}

CredentialsStore::CredentialsStore(std::string path) : path_(std::move(path)) {}

bool CredentialsStore::save(const std::string& user,
                            const std::string& pass) const {
    if (user.empty() || pass.empty())
        return false;
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(path_).parent_path(), ec);
    std::ofstream f(path_);
    if (!f)
        return false;
    nlohmann::json j{{"username", user}, {"password", pass}};
    f << j.dump();
    std::filesystem::permissions(
        path_, std::filesystem::perms::owner_read |
                   std::filesystem::perms::owner_write,
        std::filesystem::perm_options::replace, ec);
    return true;
}

bool CredentialsStore::load(std::string& user, std::string& pass) const {
    std::ifstream f(path_);
    if (!f)
        return false;
    nlohmann::json j;
    try {
        f >> j;
    } catch (...) {
        return false;
    }
    if (!j.is_object() || !j.contains("username") || !j.contains("password"))
        return false;
    user = j["username"].get<std::string>();
    pass = j["password"].get<std::string>();
    return !user.empty() && !pass.empty();
}

bool CredentialsStore::remove() const {
    std::error_code ec;
    return std::filesystem::remove(path_, ec);
}

NetworkClient::NetworkClient(std::string url)
    : credentials(defaultCredentialsPath()), url_(std::move(url)) {
    // SSL_write to a closed socket must not kill the process
    // (SIGPIPE does not exist on Windows)
#ifndef _WIN32
    std::signal(SIGPIPE, SIG_IGN);
#endif
    // parse ws://host:port or wss://host:port (TLS)
    std::string rest = url_;
    if (rest.rfind("wss://", 0) == 0) {
        tls_ = true;
        rest = rest.substr(6);
    } else if (rest.rfind("ws://", 0) == 0) {
        rest = rest.substr(5);
    }
    const size_t slash = rest.find('/');
    if (slash != std::string::npos)
        rest = rest.substr(0, slash);
    const size_t colon = rest.rfind(':');
    if (colon != std::string::npos) {
        host_ = rest.substr(0, colon);
        port_ = std::atoi(rest.substr(colon + 1).c_str());
    } else {
        host_ = rest;
        port_ = tls_ ? 443 : 80;
    }
}

NetworkClient::~NetworkClient() { disconnect(); }

bool NetworkClient::connectAndAuth(const std::string& user,
                                   const std::string& pass, bool remember) {
    if (user.empty() || pass.empty())
        return false;
    sessionUser_ = user;
    sessionPass_ = pass;
    remember_ = remember;
    state.lastError.clear();
    if (thread_.joinable())
        return false;
    stop_ = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        std::queue<nlohmann::json> empty;
        outgoing_.swap(empty);
        std::queue<nlohmann::json> empty2;
        incoming_.swap(empty2);
    }
    state.connected = false;
    state.loggedIn = false;
    state.inRoom = false;
    state.isHost = false;
    state.playerId = 0;
    state.username.clear();
    state.roomId.clear();
    thread_ = std::thread([this] { run(); });
    return true;
}

bool NetworkClient::tryAutologin() {
    std::string user, pass;
    if (!credentials.load(user, pass))
        return false;
    return connectAndAuth(user, pass, true);
}

void NetworkClient::disconnect() {
    stop_ = true;
    const bw_socket_t fd = fd_.load();
    if (fd != BW_INVALID_SOCKET)
        ::shutdown(fd, BW_SHUT_RDWR); // wake select/recv, close in the thread
    if (thread_.joinable())
        thread_.join();
    state.connected = false;
    state.loggedIn = false;
    state.inRoom = false;
}

bool NetworkClient::send(const nlohmann::json& payload) {
    if (stop_ || !thread_.joinable())
        return false;
    std::lock_guard<std::mutex> lock(mutex_);
    outgoing_.push(payload);
    return true;
}

void NetworkClient::createRoom(const std::string& name,
                               const std::string& code,
                               const std::string& password,
                               const std::string& mode) {
    send({{"type", "create_room"},
          {"name", name},
          {"room_id", code},
          {"password", password},
          {"game_mode", mode}});
}

void NetworkClient::joinRoom(const std::string& roomId,
                             const std::string& password) {
    send({{"type", "join_room"}, {"room_id", roomId}, {"password", password}});
}

void NetworkClient::leaveRoom() { send({{"type", "leave_room"}}); }
void NetworkClient::fetchRooms() { send({{"type", "list_rooms"}}); }

void NetworkClient::sendReady(int characterId) {
    send({{"type", "player_ready"}, {"character_id", characterId}});
}

void NetworkClient::startGame() { send({{"type", "start_game"}}); }

void NetworkClient::sendInput(const double pos[3], double yaw, int weapon,
                              int mode, int score, int kills, double hp,
                              bool alive) {
    send({{"type", "player_input"},
          {"keys", nlohmann::json::object()},
          {"rot_x", yaw},
          {"actions", {{"weapon", weapon}, {"mode", mode}}},
          {"pos", {pos[0], pos[1], pos[2]}},
          {"score", score},
          {"kills", kills},
          {"hp", hp},
          {"alive", alive}});
}

void NetworkClient::sendTerrainModify(int64_t x, int64_t y, int64_t z,
                                      const std::string& action,
                                      int blockType) {
    send({{"type", "terrain_modify"},
          {"pos", {x, y, z}},
          {"action_type", action},
          {"block_type", blockType}});
}

void NetworkClient::sendChat(const std::string& message) {
    if (!message.empty())
        send({{"type", "chat"}, {"message", message}});
}

void NetworkClient::savePlayerData(const nlohmann::json& data) {
    send({{"type", "save_data"}, {"data", data}});
}

void NetworkClient::loadPlayerData() { send({{"type", "load_data"}}); }

void NetworkClient::deleteAccount() { send({{"type", "delete_account"}}); }

// ------------------------------------------------------------
// transport
// ------------------------------------------------------------

void NetworkClient::run() {
    plat::initSockets();
    struct addrinfo hints {};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* res = nullptr;
    const std::string port = std::to_string(port_);
    if (getaddrinfo(host_.c_str(), port.c_str(), &hints, &res) != 0 || !res) {
        std::lock_guard<std::mutex> lock(mutex_);
        incoming_.push({{"type", "_connection_failed"},
                        {"message", "DNS lookup failed: " + host_}});
        return;
    }
    bw_socket_t newFd =
        ::socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    fd_ = newFd;
    if (newFd == BW_INVALID_SOCKET ||
        ::connect(newFd, res->ai_addr, (int)res->ai_addrlen) != 0) {
        if (newFd != BW_INVALID_SOCKET) {
            bwCloseSocket(newFd);
            fd_ = BW_INVALID_SOCKET;
        }
        freeaddrinfo(res);
        std::lock_guard<std::mutex> lock(mutex_);
        incoming_.push({{"type", "_connection_failed"},
                        {"message", "Nu ma pot conecta la " + host_ + ":" + port}});
        return;
    }
    freeaddrinfo(res);

    if (tls_) {
        SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
        if (!ctx) {
            closeTransport();
            std::lock_guard<std::mutex> lock(mutex_);
            incoming_.push({{"type", "_connection_failed"},
                            {"message", "SSL_CTX_new failed"}});
            return;
        }
        const bool insecure = std::getenv("BW_TLS_INSECURE") != nullptr;
        if (insecure)
            SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nullptr);
        else
            SSL_CTX_set_default_verify_paths(ctx);
        SSL* ssl = SSL_new(ctx);
        if (!ssl) {
            SSL_CTX_free(ctx);
            closeTransport();
            std::lock_guard<std::mutex> lock(mutex_);
            incoming_.push({{"type", "_connection_failed"},
                            {"message", "SSL_new failed"}});
            return;
        }
        SSL_set_fd(ssl, newFd);
        SSL_set_tlsext_host_name(ssl, host_.c_str());
        if (SSL_connect(ssl) != 1) {
            const unsigned long err = ERR_get_error();
            char buf[256] = {0};
            ERR_error_string_n(err, buf, sizeof(buf));
            SSL_free(ssl);
            SSL_CTX_free(ctx);
            closeTransport();
            std::lock_guard<std::mutex> lock(mutex_);
            incoming_.push({{"type", "_connection_failed"},
                            {"message", std::string("TLS: ") + buf}});
            return;
        }
        if (!insecure && SSL_get_verify_result(ssl) != X509_V_OK) {
            SSL_free(ssl);
            SSL_CTX_free(ctx);
            closeTransport();
            std::lock_guard<std::mutex> lock(mutex_);
            incoming_.push(
                {{"type", "_connection_failed"},
                 {"message", "Certificat TLS neverificat"}});
            return;
        }
        sslCtx_ = ctx;
        ssl_ = ssl;
    }

    if (!handshake()) {
        closeTransport();
        std::lock_guard<std::mutex> lock(mutex_);
        incoming_.push({{"type", "_connection_failed"},
                        {"message", "WebSocket handshake failed"}});
        return;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        incoming_.push({{"type", "_connected"}});
    }
    nlohmann::json auth{{"type", "auth"},
                        {"username", sessionUser_},
                        {"password", sessionPass_}};
    wsSend(auth.dump());

    while (!stop_) {
        const bw_socket_t fd = fd_.load();
        if (fd == BW_INVALID_SOCKET)
            break;
        for (;;) {
            nlohmann::json payload;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                if (outgoing_.empty())
                    break;
                payload = outgoing_.front();
                outgoing_.pop();
            }
            if (!wsSend(payload.dump()))
                break;
        }
        std::string text;
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        struct timeval tv {};
        tv.tv_sec = 0;
        tv.tv_usec = 50000;
#ifdef _WIN32
        const int ready = ::select(0, &fds, nullptr, nullptr, &tv);
#else
        const int ready = ::select(fd + 1, &fds, nullptr, nullptr, &tv);
#endif
        if (ready > 0 && FD_ISSET(fd, &fds)) {
            if (!wsRecv(text))
                break;
            if (!text.empty()) {
                try {
                    auto message = nlohmann::json::parse(text);
                    if (message.is_object()) {
                        std::lock_guard<std::mutex> lock(mutex_);
                        incoming_.push(std::move(message));
                    }
                } catch (...) {
                }
            }
        }
    }
    closeTransport();
    std::lock_guard<std::mutex> lock(mutex_);
    incoming_.push({{"type", "_disconnected"}});
}

void NetworkClient::closeTransport() {
    if (ssl_) {
        SSL_shutdown((SSL*)ssl_);
        SSL_free((SSL*)ssl_);
        ssl_ = nullptr;
    }
    if (sslCtx_) {
        SSL_CTX_free((SSL_CTX*)sslCtx_);
        sslCtx_ = nullptr;
    }
    const bw_socket_t fd = fd_.exchange(BW_INVALID_SOCKET);
    bwCloseSocket(fd);
}

long NetworkClient::ioRead(void* buf, size_t len) {
    if (ssl_)
        return SSL_read((SSL*)ssl_, buf, (int)len);
    const bw_socket_t fd = fd_.load();
    if (fd == BW_INVALID_SOCKET)
        return -1;
    return ::recv(fd, (char*)buf, (int)len, 0);
}

long NetworkClient::ioWrite(const void* buf, size_t len) {
    if (ssl_)
        return SSL_write((SSL*)ssl_, buf, (int)len);
    const bw_socket_t fd = fd_.load();
    if (fd == BW_INVALID_SOCKET)
        return -1;
    return ::send(fd, (const char*)buf, (int)len, BW_MSG_NOSIGNAL);
}

bool NetworkClient::handshake() {
    unsigned char keyBytes[16];
    std::random_device rd;
    for (auto& b : keyBytes)
        b = (unsigned char)(rd() & 0xff);
    const std::string key = base64(keyBytes, sizeof(keyBytes));
    char request[1024];
    std::snprintf(request, sizeof(request),
                  "GET / HTTP/1.1\r\n"
                  "Host: %s:%d\r\n"
                  "Upgrade: websocket\r\n"
                  "Connection: Upgrade\r\n"
                  "Sec-WebSocket-Key: %s\r\n"
                  "Sec-WebSocket-Version: 13\r\n"
                  "\r\n",
                  host_.c_str(), port_, key.c_str());
    if (ioWrite(request, std::strlen(request)) < 0)
        return false;
    std::string response;
    char buf[1024];
    while (response.find("\r\n\r\n") == std::string::npos) {
        const long n = ioRead(buf, sizeof(buf));
        if (n <= 0)
            return false;
        response.append(buf, (size_t)n);
        if (response.size() > 16384)
            return false;
    }
    return response.find(" 101") != std::string::npos;
}

bool NetworkClient::wsSend(const std::string& payload) {
    const bw_socket_t fd = fd_.load();
    if (fd == BW_INVALID_SOCKET)
        return false;
    std::string frame;
    frame.push_back((char)0x81); // FIN + text
    const size_t n = payload.size();
    if (n < 126) {
        frame.push_back((char)(0x80 | n));
    } else if (n <= 0xFFFF) {
        frame.push_back((char)(0x80 | 126));
        frame.push_back((char)((n >> 8) & 0xff));
        frame.push_back((char)(n & 0xff));
    } else {
        frame.push_back((char)(0x80 | 127));
        for (int i = 7; i >= 0; --i)
            frame.push_back((char)((n >> (i * 8)) & 0xff));
    }
    unsigned char mask[4];
    std::random_device rd;
    for (auto& b : mask)
        b = (unsigned char)(rd() & 0xff);
    frame.append((char*)mask, 4);
    for (size_t i = 0; i < n; ++i)
        frame.push_back((char)((unsigned char)payload[i] ^ mask[i % 4]));
    size_t sent = 0;
    while (sent < frame.size()) {
        const long w =
            ioWrite(frame.data() + sent, frame.size() - sent);
        if (w <= 0)
            return false;
        sent += (size_t)w;
    }
    return true;
}

bool NetworkClient::wsRecv(std::string& out) {
    const bw_socket_t fd = fd_.load();
    if (fd == BW_INVALID_SOCKET)
        return false;
    out.clear();
    auto readExact = [&](unsigned char* dst, size_t len) -> bool {
        size_t got = 0;
        while (got < len) {
            const long n = ioRead(dst + got, len - got);
            if (n <= 0)
                return false;
            got += (size_t)n;
        }
        return true;
    };
    for (;;) {
        unsigned char header[2];
        if (!readExact(header, 2))
            return false;
        const int opcode = header[0] & 0x0f;
        const bool masked = (header[1] & 0x80) != 0;
        uint64_t len = header[1] & 0x7f;
        if (len == 126) {
            unsigned char ext[2];
            if (!readExact(ext, 2))
                return false;
            len = ((uint64_t)ext[0] << 8) | ext[1];
        } else if (len == 127) {
            unsigned char ext[8];
            if (!readExact(ext, 8))
                return false;
            len = 0;
            for (int i = 0; i < 8; ++i)
                len = (len << 8) | ext[i];
        }
        unsigned char mask[4] = {0, 0, 0, 0};
        if (masked && !readExact(mask, 4))
            return false;
        std::string data(len, '\0');
        if (len > 0 && !readExact((unsigned char*)data.data(), len))
            return false;
        if (masked)
            for (uint64_t i = 0; i < len; ++i)
                data[i] = (char)((unsigned char)data[i] ^ mask[i % 4]);
        if (opcode == 0x8) // close
            return false;
        if (opcode == 0x9) { // ping -> pong
            std::string pong;
            pong.push_back((char)0x8A);
            pong.push_back((char)(0x80 | len));
            unsigned char m[4] = {0, 0, 0, 0};
            pong.append((char*)m, 4);
            pong += data;
            ioWrite(pong.data(), pong.size());
            continue;
        }
        if (opcode == 0xA) // pong
            continue;
        if (opcode == 0x1 || opcode == 0x2 || opcode == 0x0) {
            out = std::move(data);
            return true;
        }
    }
}

// ------------------------------------------------------------
// messages
// ------------------------------------------------------------

void NetworkClient::applyMessage(const nlohmann::json& m) {
    const std::string type = m.value("type", "");
    auto intOf = [&](const char* key, int def = 0) {
        try {
            return m.contains(key) && m[key].is_number()
                       ? m[key].get<int>()
                       : def;
        } catch (...) {
            return def;
        }
    };
    if (type == "_connected") {
        state.connected = true;
    } else if (type == "auth_ok") {
        state.loggedIn = true;
        state.playerId = intOf("player_id");
        state.username = m.value("username", "");
        if (remember_)
            credentials.save(sessionUser_, sessionPass_);
    } else if (type == "auth_error") {
        state.loggedIn = false;
        state.lastError = m.value("message", "Auth failed");
    } else if (type == "room_created" || type == "joined") {
        state.roomId = m.value("room_id", "");
        state.inRoom = true;
        state.isHost = (type == "room_created");
        state.roomPlayers.clear();
        if (m.contains("players") && m["players"].is_array())
            for (const auto& p : m["players"])
                state.roomPlayers.push_back(p.value("name", "Player"));
        if (m.contains("settings") && m["settings"].is_object()) {
            state.roomGameMode = m["settings"].value("game_mode", "");
            state.roomTimeLimit = m["settings"].value("time_limit", 0.0);
        }
    } else if (type == "game_started") {
        state.roomGameMode = m.value("game_mode", state.roomGameMode);
        if (m.contains("time_limit"))
            state.roomTimeLimit = m.value("time_limit", 0.0);
    } else if (type == "room_list") {
        state.roomList.clear();
        state.roomIds.clear();
        if (m.contains("rooms") && m["rooms"].is_array())
            for (const auto& r : m["rooms"]) {
                state.roomIds.push_back(r.value("room_id", ""));
                state.roomList.push_back(
                    r.value("name", "Sala") + " [" +
                    r.value("room_id", "?") + "] " +
                    std::to_string(r.value("player_count", 0)) + "/" +
                    std::to_string(r.value("max_players", 8)));
            }
    } else if (type == "player_joined") {
        state.roomPlayers.push_back(m.value("name", "Player"));
    } else if (type == "player_ready") {
        // mark ready by name if present
        const std::string name = m.value("name", "");
        for (auto& p : state.roomPlayers)
            if (p == name)
                p += " - READY";
    } else if (type == "player_left") {
        const std::string name = m.value("name", "");
        state.roomPlayers.erase(
            std::remove(state.roomPlayers.begin(), state.roomPlayers.end(),
                        name),
            state.roomPlayers.end());
    } else if (type == "room_closed") {
        state.roomId.clear();
        state.inRoom = false;
        state.isHost = false;
        state.roomPlayers.clear();
        state.lastError = m.value("message", "Room closed");
    } else if (type == "state_update") {
        if (m.contains("players") && m["players"].is_array())
            state.remotePlayers = m["players"].get<std::vector<nlohmann::json>>();
        if (m.contains("time_remaining"))
            state.serverTimeRemaining = m.value("time_remaining", -1.0);
        if (m.value("match_finished", false))
            state.matchFinished = true;
    } else if (type == "match_ended") {
        if (m.contains("players") && m["players"].is_array())
            state.remotePlayers = m["players"].get<std::vector<nlohmann::json>>();
        state.matchFinished = true;
    } else if (type == "chat") {
        const std::string name = m.value("name", "Player");
        const std::string body = m.value("message", "");
        chatMessages.push_back(name + ": " + body);
        if (chatMessages.size() > 6)
            chatMessages.erase(chatMessages.begin());
    } else if (type == "error" || type == "_connection_failed") {
        state.lastError = m.value("message", "Network error");
    } else if (type == "_disconnected") {
        state.connected = false;
        state.loggedIn = false;
        state.inRoom = false;
        state.isHost = false;
    }
}

std::vector<nlohmann::json> NetworkClient::poll() {
    std::vector<nlohmann::json> messages;
    for (;;) {
        nlohmann::json message;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (incoming_.empty())
                break;
            message = incoming_.front();
            incoming_.pop();
        }
        applyMessage(message);
        messages.push_back(std::move(message));
    }
    return messages;
}

} // namespace net
} // namespace bw
