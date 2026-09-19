// ============================================================
// Cross-platform socket helpers (POSIX sockets / Winsock2)
//
// Used by the WebSocket client (net.cpp) and server
// (wsserver.cpp) so the same code builds on Linux, macOS and
// Windows.
// ============================================================

#pragma once

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include <cstdint>

using bw_socket_t = SOCKET;
using bw_pollfd = WSAPOLLFD;
constexpr bw_socket_t BW_INVALID_SOCKET = INVALID_SOCKET;

inline int bwSockErr() { return WSAGetLastError(); }
inline bool bwWouldBlock(int e) {
    return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS;
}
inline void bwCloseSocket(bw_socket_t s) {
    if (s != INVALID_SOCKET)
        closesocket(s);
}
inline bool bwSetNonBlocking(bw_socket_t s) {
    u_long one = 1;
    return ioctlsocket(s, FIONBIO, &one) == 0;
}
inline int bwPoll(bw_pollfd* fds, int n, int timeoutMs) {
    return WSAPoll(fds, (ULONG)n, timeoutMs);
}
inline int bwInetPton(int af, const char* src, void* dst) {
    return InetPtonA(af, src, dst);
}
inline const char* bwInetNtop(int af, const void* src, char* dst,
                              size_t size) {
    return InetNtopA(af, src, dst, (DWORD)size);
}
#define BW_MSG_NOSIGNAL 0
#define BW_SHUT_RDWR SD_BOTH

#else // POSIX

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>

using bw_socket_t = int;
using bw_pollfd = struct pollfd;
constexpr bw_socket_t BW_INVALID_SOCKET = -1;

inline int bwSockErr() { return errno; }
inline bool bwWouldBlock(int e) { return e == EAGAIN || e == EWOULDBLOCK; }
inline void bwCloseSocket(bw_socket_t s) {
    if (s >= 0)
        ::close(s);
}
inline bool bwSetNonBlocking(bw_socket_t s) {
    const int flags = fcntl(s, F_GETFL, 0);
    return flags >= 0 && fcntl(s, F_SETFL, flags | O_NONBLOCK) == 0;
}
inline int bwPoll(bw_pollfd* fds, int n, int timeoutMs) {
    return ::poll(fds, (nfds_t)n, timeoutMs);
}
inline int bwInetPton(int af, const char* src, void* dst) {
    return ::inet_pton(af, src, dst);
}
inline const char* bwInetNtop(int af, const void* src, char* dst,
                              size_t size) {
    return ::inet_ntop(af, src, dst, (socklen_t)size);
}
#define BW_MSG_NOSIGNAL MSG_NOSIGNAL
#define BW_SHUT_RDWR SHUT_RDWR

#endif
