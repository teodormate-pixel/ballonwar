// ============================================================
// WebSocket multiplayer client (compatible with the Node server
// and with balloonwar/net/client.py).
//
// Plain ws:// over TCP; wss:// (TLS) is reported as unsupported.
// Transport runs on a background thread; poll() applies queued
// messages on the main thread.
// ============================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#include <nlohmann/json.hpp>

#include "netcompat.h"

namespace bw {
namespace net {

struct NetworkState {
    bool connected = false;
    bool loggedIn = false;
    bool inRoom = false;
    bool isHost = false;
    int playerId = 0;
    std::string username;
    std::string roomId;
    std::string roomGameMode;
    double roomTimeLimit = 0.0;
    std::string lastError;
    std::vector<std::string> roomPlayers;
    std::vector<std::string> roomList;
    std::vector<std::string> roomIds;
    std::vector<nlohmann::json> remotePlayers;
    double serverTimeRemaining = -1.0;
    bool matchFinished = false;
};

class CredentialsStore {
  public:
    explicit CredentialsStore(std::string path);
    bool save(const std::string& user, const std::string& pass) const;
    bool load(std::string& user, std::string& pass) const;
    bool remove() const;

  private:
    std::string path_;
};

class NetworkClient {
  public:
    explicit NetworkClient(std::string url = defaultUrl());
    ~NetworkClient();

    NetworkState state;
    CredentialsStore credentials;

    bool connectAndAuth(const std::string& user, const std::string& pass,
                        bool remember);
    bool tryAutologin();
    void disconnect();
    bool send(const nlohmann::json& payload);

    void createRoom(const std::string& name, const std::string& code,
                    const std::string& password, const std::string& mode);
    void joinRoom(const std::string& roomId, const std::string& password);
    void leaveRoom();
    void fetchRooms();
    void sendReady(int characterId);
    void startGame();
    void sendInput(const double pos[3], double yaw, int weapon, int mode,
                   int score, int kills, double hp, bool alive);
    void sendTerrainModify(int64_t x, int64_t y, int64_t z,
                           const std::string& action, int blockType);
    void sendChat(const std::string& message);
    void savePlayerData(const nlohmann::json& data);
    void loadPlayerData();
    void deleteAccount();

    // apply incoming messages to state; returns the raw messages
    std::vector<nlohmann::json> poll();
    std::vector<std::string> chatMessages;

    static std::string defaultUrl();

  private:
    void run();
    bool handshake();
    bool wsSend(const std::string& payload);
    bool wsRecv(std::string& out);
    void applyMessage(const nlohmann::json& message);
    long ioRead(void* buf, size_t len);
    long ioWrite(const void* buf, size_t len);
    void closeTransport();

    std::string url_;
    std::string host_;
    int port_ = 80;
    bool tls_ = false;
    void* sslCtx_ = nullptr; // SSL_CTX*
    void* ssl_ = nullptr;    // SSL*
    std::atomic<bw_socket_t> fd_{BW_INVALID_SOCKET};
    std::atomic<bool> stop_{false};
    std::thread thread_;
    mutable std::mutex mutex_;
    std::queue<nlohmann::json> outgoing_;
    std::queue<nlohmann::json> incoming_;
    std::string sessionUser_;
    std::string sessionPass_;
    bool remember_ = false;
};

} // namespace net
} // namespace bw
