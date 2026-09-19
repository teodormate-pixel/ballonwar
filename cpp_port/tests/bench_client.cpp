// ============================================================
// Throughput benchmark client for a BalloonWar server.
//
//   ./build/bench_client <url> <clients> <messages>
//
// Each client runs in its own thread, authenticates and pipelines
// ping messages, counting pongs. Prints aggregate messages/second.
// ============================================================

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "net.h"

namespace {

void worker(const std::string &url, const std::string &user, int messages,
            std::atomic<int> &done, std::atomic<int> &errors) {
    bw::net::NetworkClient client(url);
    if (!client.connectAndAuth(user, "bench", false)) {
        ++errors;
        ++done;
        return;
    }
    // wait for auth_ok
    for (int i = 0; i < 500; ++i) {
        bool ok = false;
        for (const auto &m : client.poll())
            if (m.value("type", "") == "auth_ok")
                ok = true;
        if (ok)
            break;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    // pipeline the pings
    for (int i = 0; i < messages; ++i)
        client.send({{"type", "ping"}});

    int pongs = 0;
    const auto start = std::chrono::steady_clock::now();
    while (pongs < messages) {
        for (const auto &m : client.poll()) {
            if (m.value("type", "") == "pong")
                ++pongs;
        }
        if (std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                          start)
                .count() > 30.0)
            break;
        std::this_thread::sleep_for(std::chrono::microseconds(50));
    }
    if (pongs != messages)
        ++errors;
    client.disconnect();
    ++done;
}

} // namespace

int main(int argc, char **argv) {
    const std::string url = argc > 1 ? argv[1] : "ws://127.0.0.1:9891";
    const int clients = argc > 2 ? std::atoi(argv[2]) : 20;
    const int messages = argc > 3 ? std::atoi(argv[3]) : 2000;

    std::atomic<int> done{0}, errors{0};
    std::vector<std::thread> threads;
    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < clients; ++i)
        threads.emplace_back(worker, std::cref(url),
                             "bench_" + std::to_string(i), messages,
                             std::ref(done), std::ref(errors));
    for (auto &t : threads)
        t.join();
    const double elapsed =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - start)
            .count();

    const double total = (double)clients * messages;
    std::printf("%.0f msg/s  (%.0f msgs in %.3f s, %d errors)\n",
                total / elapsed, total, elapsed, errors.load());
    return errors.load() == 0 ? 0 : 1;
}
