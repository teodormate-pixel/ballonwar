#include "debug.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <mutex>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <execinfo.h>
#include <signal.h>
#include <unistd.h>
#endif

#include "platform.h" 

namespace bw {
namespace dbg {

namespace {

std::mutex gMutex;
std::FILE* gFile = nullptr;
std::string gPath;
bool gVerbose = false;

std::string defaultPath() {
    const char* env = std::getenv("BW_LOG");
    if (env && *env)
        return env;
    const char* home = std::getenv("HOME");
    if (!home)
        return "balloonwar.log";
    return std::string(home) + "/.local/share/balloonwar/balloonwar.log";
}

void timestamp(char* out, size_t len) {
    std::time_t now = std::time(nullptr);
    std::tm tm{};
#ifdef _WIN32
    localtime_s(&tm, &now);
#else
    localtime_r(&now, &tm);
#endif
    std::strftime(out, len, "%H:%M:%S", &tm);
}

void writeLine(const char* level, const char* fmt, va_list args) {
    char message[2048];
    vsnprintf(message, sizeof(message), fmt, args);
    char ts[16];
    timestamp(ts, sizeof(ts));
    std::lock_guard<std::mutex> lock(gMutex);
    std::fprintf(stderr, "[%s] %s: %s\n", ts, level, message);
    if (gFile) {
        std::fprintf(gFile, "[%s] %s: %s\n", ts, level, message);
        std::fflush(gFile);
    }
}

#ifdef _WIN32

void writeCrashHeader(const char* header) {
    std::lock_guard<std::mutex> lock(gMutex);
    std::fprintf(stderr, "\n*** %s ***\n", header);
    if (gFile) {
        std::fprintf(gFile, "\n*** %s ***\n", header);
        std::fflush(gFile);
    }
}

LONG WINAPI crashFilter(EXCEPTION_POINTERS* info) {
    char header[128];
    std::snprintf(header, sizeof(header), "CRASH exception 0x%08lx",
                  info && info->ExceptionRecord
                      ? info->ExceptionRecord->ExceptionCode
                      : 0UL);
    writeCrashHeader(header);
    char text[512];
    std::snprintf(text, sizeof(text),
                  "Jocul s-a oprit neasteptat (%s).\n\nLog: %s",
                  header, gPath.empty() ? "(fara log)" : gPath.c_str());
    plat::fatalMessage("BalloonWar", text);
    return EXCEPTION_EXECUTE_HANDLER;
}

#else // POSIX

void crashHandler(int sig) {
    const char* name = strsignal(sig);
    char header[256];
    std::snprintf(header, sizeof(header), "CRASH signal %d (%s)", sig,
                  name ? name : "?");
    {
        std::lock_guard<std::mutex> lock(gMutex);
        std::fprintf(stderr, "\n*** %s ***\n", header);
        if (gFile) {
            std::fprintf(gFile, "\n*** %s ***\n", header);
            std::fflush(gFile);
        }
        void* frames[64];
        const int count = backtrace(frames, 64);
        char** symbols = backtrace_symbols(frames, count);
        for (int i = 0; i < count; ++i) {
            std::fprintf(stderr, "  #%d %s\n", i,
                         symbols ? symbols[i] : "?");
            if (gFile)
                std::fprintf(gFile, "  #%d %s\n", i,
                             symbols ? symbols[i] : "?");
        }
        if (symbols)
            free(symbols);
        if (gFile)
            std::fflush(gFile);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

#endif

} // namespace

// public (declared in debug.h): installs the platform crash reporter
void installCrashHandler() {
#ifdef _WIN32
    SetUnhandledExceptionFilter(crashFilter);
#else
    signal(SIGSEGV, crashHandler);
    signal(SIGABRT, crashHandler);
    signal(SIGFPE, crashHandler);
    signal(SIGILL, crashHandler);
    signal(SIGBUS, crashHandler);
#endif
}

void init(bool verbose) {
    gVerbose = verbose || std::getenv("BW_DEBUG") != nullptr;
    gPath = defaultPath();
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(gPath).parent_path(), ec);
    gFile = std::fopen(gPath.c_str(), "a");
    if (gFile) {
        std::time_t now = std::time(nullptr);
        std::fprintf(gFile, "\n===== BalloonWar C++ start %s =====\n",
                     std::ctime(&now));
        std::fflush(gFile);
    }
    info("log file: %s", gPath.c_str());
    installCrashHandler();
}


void info(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    writeLine("info", fmt, args);
    va_end(args);
}

void warn(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    writeLine("warn", fmt, args);
    va_end(args);
}

void error(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    writeLine("error", fmt, args);
    va_end(args);
}

bool verbose() { return gVerbose; }

const std::string& logPath() { return gPath; }

} // namespace dbg
} // namespace bw
