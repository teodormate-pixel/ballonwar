// ============================================================
// Minimal WebSocket server (RFC 6455) for BalloonWar
//
// Plain ws:// over TCP, optional wss:// (TLS) when a
// certificate/key pair is configured. Single-threaded,
// poll()-based event loop; all client frames are unmasked
// on receive and all server frames are sent unmasked.
//
// Text frames carry JSON messages; the protocol layer is in
// gameserver.cpp.
// ============================================================

#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

namespace ws {

struct Options {
    std::string bind = "0.0.0.0";
    int port = 8765;
    std::string tlsCert; // empty -> plain ws://
    std::string tlsKey;
    size_t maxMessage = 4u << 20; // reject larger frames
};

class Server {
  public:
    using ConnId = uint64_t;

    explicit Server(Options options);
    ~Server();
    Server(const Server &) = delete;
    Server &operator=(const Server &) = delete;

    bool start(std::string &error);
    void stop();

    // callbacks (set before start)
    std::function<void(ConnId)> onOpen;
    std::function<void(ConnId, const std::string &message)> onMessage;
    std::function<void(ConnId)> onClose;

    // wait for events and process them; timeout in milliseconds
    void poll(int timeoutMs);

    bool send(ConnId id, const std::string &text);
    void closeConn(ConnId id);
    bool isOpen(ConnId id) const;
    size_t connectionCount() const;
    const std::string &peerAddress(ConnId id) const;
    const std::string &lastError() const { return lastError_; }

  private:
    struct Conn;
    void acceptNew();
    void handleReadable(Conn &c);
    void handleWritable(Conn &c);
    void processBuffer(Conn &c);
    bool parseHandshake(Conn &c);
    bool parseFrames(Conn &c);
    bool readRaw(Conn &c, char *buf, size_t len, long &n);
    bool writeRaw(Conn &c, const char *buf, size_t len, long &n);
    bool flush(Conn &c);
    bool sendFrame(Conn &c, int opcode, const std::string &payload);
    void dropConn(Conn &c, bool notify);
    void reapDead();
    void setError(const std::string &error);

    Options options_;
    int listenFd_ = -1;
    void *tlsCtx_ = nullptr; // SSL_CTX*
    ConnId nextId_ = 1;
    std::unordered_map<ConnId, Conn> conns_;
    std::vector<ConnId> order_;
    std::vector<ConnId> dead_; // closed during a callback, reaped after poll
    std::string lastError_;
    bool running_ = false;
};

} // namespace ws
