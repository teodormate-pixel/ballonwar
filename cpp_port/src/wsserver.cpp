#include "wsserver.h"

#include "netcompat.h"
#include "platform.h"

#include <openssl/err.h>
#include <openssl/ssl.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace ws {

namespace {

constexpr size_t kMaxHandshake = 16 * 1024;

// ---- SHA-1 (RFC 3174), used only for the handshake accept key ----
struct Sha1 {
    uint32_t h[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476,
                     0xC3D2E1F0};
    uint64_t len = 0;
    unsigned char buf[64];
    size_t bufLen = 0;

    static uint32_t rol(uint32_t v, int n) {
        return (v << n) | (v >> (32 - n));
    }

    void block(const unsigned char *p) {
        uint32_t w[80];
        for (int i = 0; i < 16; ++i)
            w[i] = (uint32_t)p[i * 4] << 24 | (uint32_t)p[i * 4 + 1] << 16 |
                   (uint32_t)p[i * 4 + 2] << 8 | (uint32_t)p[i * 4 + 3];
        for (int i = 16; i < 80; ++i)
            w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; ++i) {
            uint32_t f, k;
            if (i < 20) {
                f = (b & c) | (~b & d);
                k = 0x5A827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDC;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6;
            }
            const uint32_t tmp = rol(a, 5) + f + e + k + w[i];
            e = d;
            d = c;
            c = rol(b, 30);
            b = a;
            a = tmp;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
    }

    void update(const void *data, size_t n) {
        const unsigned char *p = (const unsigned char *)data;
        len += n;
        while (n > 0) {
            const size_t take = std::min(n, sizeof(buf) - bufLen);
            std::memcpy(buf + bufLen, p, take);
            bufLen += take;
            p += take;
            n -= take;
            if (bufLen == 64) {
                block(buf);
                bufLen = 0;
            }
        }
    }

    void finish(unsigned char out[20]) {
        const uint64_t bits = len * 8;
        unsigned char pad = 0x80;
        update(&pad, 1);
        unsigned char zero = 0;
        while (bufLen != 56)
            update(&zero, 1);
        unsigned char lenBytes[8];
        for (int i = 0; i < 8; ++i)
            lenBytes[i] = (unsigned char)(bits >> ((7 - i) * 8));
        update(lenBytes, 8);
        for (int i = 0; i < 5; ++i) {
            out[i * 4] = (unsigned char)(h[i] >> 24);
            out[i * 4 + 1] = (unsigned char)(h[i] >> 16);
            out[i * 4 + 2] = (unsigned char)(h[i] >> 8);
            out[i * 4 + 3] = (unsigned char)h[i];
        }
    }
};

std::string base64(const unsigned char *data, size_t len) {
    static const char *tbl =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((len + 2) / 3 * 4);
    size_t i = 0;
    while (i + 2 < len) {
        const uint32_t v = (uint32_t)data[i] << 16 |
                           (uint32_t)data[i + 1] << 8 | data[i + 2];
        out.push_back(tbl[(v >> 18) & 63]);
        out.push_back(tbl[(v >> 12) & 63]);
        out.push_back(tbl[(v >> 6) & 63]);
        out.push_back(tbl[v & 63]);
        i += 3;
    }
    if (i + 1 == len) {
        const uint32_t v = (uint32_t)data[i] << 16;
        out.push_back(tbl[(v >> 18) & 63]);
        out.push_back(tbl[(v >> 12) & 63]);
        out.push_back('=');
        out.push_back('=');
    } else if (i + 2 == len) {
        const uint32_t v = (uint32_t)data[i] << 16 |
                           (uint32_t)data[i + 1] << 8;
        out.push_back(tbl[(v >> 18) & 63]);
        out.push_back(tbl[(v >> 12) & 63]);
        out.push_back(tbl[(v >> 6) & 63]);
        out.push_back('=');
    }
    return out;
}

std::string toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return (char)std::tolower(c); });
    return s;
}

std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos)
        return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

std::string sockErrString() {
#ifdef _WIN32
    char buf[64] = {0};
    std::snprintf(buf, sizeof(buf), "winsock error %d", bwSockErr());
    return buf;
#else
    return std::strerror(bwSockErr());
#endif
}

} // namespace

struct Server::Conn {
    ConnId id = 0;
    int fd = -1;
    bool open = false;
    bool handshakeDone = false;
    bool closing = false;
    bool sslHandshaking = false;
    bool sslWantWrite = false;
    SSL *ssl = nullptr;
    std::string peer;
    std::string in;
    std::string out;
    std::string frag;
    int fragOpcode = 0;
};

Server::Server(Options options) : options_(std::move(options)) {}

Server::~Server() { stop(); }

void Server::setError(const std::string &error) {
    lastError_ = error;
    std::fprintf(stderr, "[ws] %s\n", error.c_str());
}

bool Server::start(std::string &error) {
    if (running_)
        return true;
    plat::initSockets();

    if (!options_.tlsCert.empty() && !options_.tlsKey.empty()) {
        SSL_library_init();
        SSL_load_error_strings();
        SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
        if (!ctx) {
            error = "SSL_CTX_new failed";
            return false;
        }
        if (SSL_CTX_use_certificate_file(ctx, options_.tlsCert.c_str(),
                                         SSL_FILETYPE_PEM) != 1 ||
            SSL_CTX_use_PrivateKey_file(ctx, options_.tlsKey.c_str(),
                                        SSL_FILETYPE_PEM) != 1) {
            error = "cannot load TLS certificate/key";
            SSL_CTX_free(ctx);
            return false;
        }
        tlsCtx_ = ctx;
    }

    listenFd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd_ == BW_INVALID_SOCKET) {
        error = "socket() failed: " + sockErrString();
        return false;
    }
    int one = 1;
    ::setsockopt(listenFd_, SOL_SOCKET, SO_REUSEADDR, (const char *)&one,
                 (int)sizeof(one));
    if (!bwSetNonBlocking(listenFd_)) {
        error = "cannot make listen socket non-blocking";
        bwCloseSocket(listenFd_);
        listenFd_ = BW_INVALID_SOCKET;
        return false;
    }
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)options_.port);
    if (bwInetPton(AF_INET, options_.bind.c_str(), &addr.sin_addr) != 1)
        addr.sin_addr.s_addr = INADDR_ANY;
    if (::bind(listenFd_, (sockaddr *)&addr, (int)sizeof(addr)) != 0) {
        error = "bind(" + options_.bind + ":" +
                std::to_string(options_.port) + ") failed: " +
                sockErrString();
        bwCloseSocket(listenFd_);
        listenFd_ = BW_INVALID_SOCKET;
        return false;
    }
    if (::listen(listenFd_, 128) != 0) {
        error = "listen() failed: " + sockErrString();
        bwCloseSocket(listenFd_);
        listenFd_ = BW_INVALID_SOCKET;
        return false;
    }
    running_ = true;
    lastError_.clear();
    return true;
}

void Server::stop() {
    for (auto &[id, c] : conns_) {
        (void)id;
        if (c.ssl) {
            SSL_shutdown(c.ssl);
            SSL_free(c.ssl);
            c.ssl = nullptr;
        }
        bwCloseSocket(c.fd);
    }
    conns_.clear();
    order_.clear();
    dead_.clear();
    if (listenFd_ != BW_INVALID_SOCKET) {
        bwCloseSocket(listenFd_);
        listenFd_ = BW_INVALID_SOCKET;
    }
    if (tlsCtx_) {
        SSL_CTX_free((SSL_CTX *)tlsCtx_);
        tlsCtx_ = nullptr;
    }
    running_ = false;
}

bool Server::isOpen(ConnId id) const {
    auto it = conns_.find(id);
    return it != conns_.end() && it->second.open;
}

size_t Server::connectionCount() const {
    size_t n = 0;
    for (const auto &[id, c] : conns_) {
        (void)id;
        if (c.open)
            ++n;
    }
    return n;
}

const std::string &Server::peerAddress(ConnId id) const {
    static const std::string empty;
    auto it = conns_.find(id);
    return it == conns_.end() ? empty : it->second.peer;
}

void Server::acceptNew() {
    for (;;) {
        sockaddr_in addr{};
        socklen_t len = sizeof(addr);
        const bw_socket_t fd = ::accept(listenFd_, (sockaddr *)&addr, &len);
        if (fd == BW_INVALID_SOCKET)
            return; // would block or error
        bwSetNonBlocking(fd);
        int one = 1;
        ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const char *)&one,
                     (int)sizeof(one));

        Conn c;
        c.id = nextId_++;
        c.fd = fd;
        c.open = true;
        char ip[64] = {0};
        bwInetNtop(AF_INET, &addr.sin_addr, ip, sizeof(ip));
        c.peer = std::string(ip) + ":" + std::to_string(ntohs(addr.sin_port));
        if (tlsCtx_) {
            c.ssl = SSL_new((SSL_CTX *)tlsCtx_);
            SSL_set_fd(c.ssl, fd);
            SSL_set_accept_state(c.ssl);
            c.sslHandshaking = true;
        }
        const ConnId id = c.id;
        conns_.emplace(id, std::move(c));
        order_.push_back(id);
    }
}

bool Server::readRaw(Conn &c, char *buf, size_t len, long &n) {
    n = 0;
    if (c.ssl) {
        const int r = SSL_read(c.ssl, buf, (int)len);
        if (r > 0) {
            n = r;
            return true;
        }
        const int err = SSL_get_error(c.ssl, r);
        if (err == SSL_ERROR_WANT_WRITE) {
            c.sslWantWrite = true;
            return true;
        }
        if (err == SSL_ERROR_WANT_READ) {
            c.sslWantWrite = false;
            return true;
        }
        return false;
    }
    const long r = (long)::recv(c.fd, (char *)buf, (int)len, 0);
    if (r > 0) {
        n = r;
        return true;
    }
    if (r == 0)
        return false;
    return bwWouldBlock(bwSockErr());
}

bool Server::writeRaw(Conn &c, const char *buf, size_t len, long &n) {
    n = 0;
    if (c.ssl) {
        const int r = SSL_write(c.ssl, buf, (int)len);
        if (r > 0) {
            n = r;
            c.sslWantWrite = false;
            return true;
        }
        const int err = SSL_get_error(c.ssl, r);
        if (err == SSL_ERROR_WANT_WRITE) {
            c.sslWantWrite = true;
            return true;
        }
        if (err == SSL_ERROR_WANT_READ) {
            c.sslWantWrite = false;
            return true;
        }
        return false;
    }
    const long r = (long)::send(c.fd, (const char *)buf, (int)len,
                                BW_MSG_NOSIGNAL);
    if (r > 0) {
        n = r;
        return true;
    }
    return bwWouldBlock(bwSockErr());
}

bool Server::flush(Conn &c) {
    while (!c.out.empty()) {
        long n = 0;
        if (!writeRaw(c, c.out.data(), c.out.size(), n))
            return false;
        if (n <= 0)
            return true; // would block; wait for POLLOUT
        c.out.erase(0, (size_t)n);
    }
    return true;
}

bool Server::sendFrame(Conn &c, int opcode, const std::string &payload) {
    if (!c.open)
        return false;
    std::string frame;
    frame.reserve(payload.size() + 10);
    frame.push_back((char)(0x80 | opcode));
    const size_t n = payload.size();
    if (n < 126) {
        frame.push_back((char)n);
    } else if (n <= 0xFFFF) {
        frame.push_back((char)126);
        frame.push_back((char)((n >> 8) & 0xff));
        frame.push_back((char)(n & 0xff));
    } else {
        frame.push_back((char)127);
        for (int i = 7; i >= 0; --i)
            frame.push_back((char)((n >> (i * 8)) & 0xff));
    }
    frame += payload;
    c.out += frame;
    return flush(c);
}

bool Server::send(ConnId id, const std::string &text) {
    auto it = conns_.find(id);
    if (it == conns_.end() || !it->second.open)
        return false;
    return sendFrame(it->second, 0x1, text);
}

void Server::closeConn(ConnId id) {
    auto it = conns_.find(id);
    if (it == conns_.end())
        return;
    Conn &c = it->second;
    if (c.open && c.handshakeDone) {
        // best-effort close frame
        std::string payload;
        payload.push_back((char)0x03); // going away
        payload.push_back((char)0xE8);
        sendFrame(c, 0x8, payload);
    }
    dropConn(c, true);
}

void Server::dropConn(Conn &c, bool notify) {
    if (!c.open)
        return;
    // Mark as closed but keep the object alive until the end of the poll
    // iteration: callbacks (onMessage/onClose) may still hold references
    // to it and may re-enter send()/closeConn().
    c.open = false;
    const ConnId id = c.id;
    if (c.ssl) {
        SSL_shutdown(c.ssl);
        SSL_free(c.ssl);
        c.ssl = nullptr;
    }
    if (c.fd != BW_INVALID_SOCKET) {
        bwCloseSocket(c.fd);
        c.fd = BW_INVALID_SOCKET;
    }
    dead_.push_back(id);
    if (notify && onClose)
        onClose(id);
}

void Server::reapDead() {
    for (ConnId id : dead_) {
        conns_.erase(id);
        order_.erase(std::remove(order_.begin(), order_.end(), id),
                     order_.end());
    }
    dead_.clear();
}

bool Server::parseHandshake(Conn &c) {
    const size_t end = c.in.find("\r\n\r\n");
    if (end == std::string::npos) {
        if (c.in.size() > kMaxHandshake) {
            setError("handshake too large from " + c.peer);
            return false;
        }
        return true; // need more data
    }
    const std::string head = c.in.substr(0, end);
    c.in.erase(0, end + 4);

    std::string key;
    bool upgrade = false;
    size_t lineStart = head.find("\r\n");
    while (lineStart != std::string::npos) {
        const size_t lineEnd = head.find("\r\n", lineStart + 2);
        const std::string line =
            head.substr(lineStart + 2,
                        lineEnd == std::string::npos
                            ? std::string::npos
                            : lineEnd - lineStart - 2);
        const size_t colon = line.find(':');
        if (colon != std::string::npos) {
            const std::string name = toLower(trim(line.substr(0, colon)));
            const std::string value = toLower(trim(line.substr(colon + 1)));
            if (name == "sec-websocket-key")
                key = trim(line.substr(colon + 1));
            else if (name == "upgrade" && value.find("websocket") !=
                                              std::string::npos)
                upgrade = true;
        }
        if (lineEnd == std::string::npos)
            break;
        lineStart = lineEnd;
    }

    if (key.empty() || !upgrade) {
        const std::string bad =
            "HTTP/1.1 400 Bad Request\r\n"
            "Content-Length: 0\r\n"
            "Connection: close\r\n\r\n";
        c.out += bad;
        flush(c);
        return false;
    }

    static const char *kGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    Sha1 sha;
    const std::string joined = key + kGuid;
    sha.update(joined.data(), joined.size());
    unsigned char digest[20];
    sha.finish(digest);
    const std::string accept = base64(digest, sizeof(digest));

    std::string response =
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " +
        accept + "\r\n\r\n";
    c.out += response;
    if (!flush(c))
        return false;
    c.handshakeDone = true;
    if (onOpen)
        onOpen(c.id);
    return true;
}

bool Server::parseFrames(Conn &c) {
    for (;;) {
        if (c.in.size() < 2)
            return true;
        const unsigned char b0 = (unsigned char)c.in[0];
        const unsigned char b1 = (unsigned char)c.in[1];
        const int opcode = b0 & 0x0f;
        const bool fin = (b0 & 0x80) != 0;
        const bool masked = (b1 & 0x80) != 0;
        uint64_t len = b1 & 0x7f;
        size_t pos = 2;
        if (len == 126) {
            if (c.in.size() < 4)
                return true;
            len = ((uint64_t)(unsigned char)c.in[2] << 8) |
                  (unsigned char)c.in[3];
            pos = 4;
        } else if (len == 127) {
            if (c.in.size() < 10)
                return true;
            len = 0;
            for (int i = 0; i < 8; ++i)
                len = (len << 8) | (unsigned char)c.in[2 + i];
            pos = 10;
        }
        if (len > options_.maxMessage) {
            setError("frame too large from " + c.peer);
            return false;
        }
        unsigned char mask[4] = {0, 0, 0, 0};
        if (masked) {
            if (c.in.size() < pos + 4)
                return true;
            std::memcpy(mask, c.in.data() + pos, 4);
            pos += 4;
        }
        if (c.in.size() < pos + len)
            return true;
        std::string payload = c.in.substr(pos, (size_t)len);
        c.in.erase(0, pos + (size_t)len);
        if (masked)
            for (size_t i = 0; i < payload.size(); ++i)
                payload[i] = (char)((unsigned char)payload[i] ^ mask[i % 4]);

        switch (opcode) {
        case 0x0: // continuation
            c.frag += payload;
            if (fin) {
                if (c.fragOpcode == 0x1 || c.fragOpcode == 0x2) {
                    if (onMessage)
                        onMessage(c.id, c.frag);
                    if (!c.open)
                        return false;
                }
                c.frag.clear();
                c.fragOpcode = 0;
            }
            break;
        case 0x1: // text
        case 0x2: // binary (JSON payloads)
            if (fin) {
                if (onMessage)
                    onMessage(c.id, payload);
                if (!c.open)
                    return false;
            } else {
                c.frag = std::move(payload);
                c.fragOpcode = opcode;
            }
            break;
        case 0x8: { // close
            std::string reply;
            reply.push_back((char)0x03);
            reply.push_back((char)0xE8);
            sendFrame(c, 0x8, reply);
            return false;
        }
        case 0x9: // ping
            sendFrame(c, 0xA, payload);
            if (!c.open)
                return false;
            break;
        case 0xA: // pong
            break;
        default:
            setError("unsupported opcode from " + c.peer);
            return false;
        }
    }
}

void Server::processBuffer(Conn &c) {
    if (!c.handshakeDone) {
        if (!parseHandshake(c))
            dropConn(c, true);
        return;
    }
    if (!parseFrames(c))
        dropConn(c, true);
}

void Server::handleReadable(Conn &c) {
    if (c.sslHandshaking) {
        const int r = SSL_accept(c.ssl);
        if (r == 1) {
            c.sslHandshaking = false;
            c.sslWantWrite = false;
        } else {
            const int err = SSL_get_error(c.ssl, r);
            if (err == SSL_ERROR_WANT_WRITE) {
                c.sslWantWrite = true;
            } else if (err != SSL_ERROR_WANT_READ) {
                dropConn(c, true);
                return;
            }
            return; // wait for the handshake to finish
        }
    }
    char buf[8192];
    for (;;) {
        long n = 0;
        if (!readRaw(c, buf, sizeof(buf), n)) {
            dropConn(c, true);
            return;
        }
        if (n <= 0)
            break;
        c.in.append(buf, (size_t)n);
    }
    processBuffer(c);
}

void Server::handleWritable(Conn &c) {
    if (c.sslHandshaking) {
        const int r = SSL_accept(c.ssl);
        if (r == 1) {
            c.sslHandshaking = false;
            c.sslWantWrite = false;
            processBuffer(c);
        } else {
            const int err = SSL_get_error(c.ssl, r);
            if (err == SSL_ERROR_WANT_WRITE)
                c.sslWantWrite = true;
            else if (err != SSL_ERROR_WANT_READ)
                dropConn(c, true);
        }
        return;
    }
    if (!flush(c))
        dropConn(c, true);
}

void Server::poll(int timeoutMs) {
    if (!running_)
        return;
    std::vector<bw_pollfd> fds;
    std::vector<ConnId> ids; // parallel to fds (0 = listen socket)
    fds.reserve(order_.size() + 1);
    ids.reserve(order_.size() + 1);
    bw_pollfd lp{};
    lp.fd = listenFd_;
    lp.events = POLLIN;
    fds.push_back(lp);
    ids.push_back(0);
    for (ConnId id : order_) {
        auto it = conns_.find(id);
        if (it == conns_.end())
            continue;
        Conn &c = it->second;
        if (!c.open)
            continue;
        bw_pollfd p{};
        p.fd = c.fd;
        p.events = POLLIN;
        if (!c.out.empty() || c.sslWantWrite)
            p.events |= POLLOUT;
        fds.push_back(p);
        ids.push_back(id);
    }
    const int rc = bwPoll(fds.data(), (int)fds.size(), timeoutMs);
    if (rc <= 0)
        return;
    if (fds[0].revents & POLLIN)
        acceptNew();
    for (size_t i = 1; i < fds.size(); ++i) {
        const ConnId id = ids[i];
        auto it = conns_.find(id);
        if (it == conns_.end())
            continue;
        Conn &c = it->second;
        if (fds[i].revents & (POLLERR | POLLNVAL)) {
            dropConn(c, true);
            continue;
        }
        if (fds[i].revents & POLLOUT)
            handleWritable(c);
        if (!c.open)
            continue;
        if (fds[i].revents & (POLLIN | POLLHUP))
            handleReadable(c);
    }
    reapDead();
}

} // namespace ws
