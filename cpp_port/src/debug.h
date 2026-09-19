// ============================================================
// Diagnostics: file log, crash handler with backtrace and
// OpenGL error checking.
//
// Enabled by default; the log path can be changed with BW_LOG
// (default ~/.local/share/balloonwar/balloonwar.log).
// BW_DEBUG=1 also enables the in-game debug overlay and verbose
// logging.
// ============================================================

#pragma once

#include <string>

namespace bw {
namespace dbg {

// Opens the log file (BW_LOG or the default path) and mirrors every
// message to stderr. Safe to call more than once.
void init(bool verbose);

// Installs handlers for SIGSEGV/SIGABRT/SIGFPE/SIGILL/SIGBUS that
// write a backtrace to the log and stderr, then re-raise.
void installCrashHandler();

#if defined(__GNUC__) || defined(__clang__)
#define BW_PRINTF_FMT(a, b) __attribute__((format(printf, a, b)))
#else
#define BW_PRINTF_FMT(a, b)
#endif

void info(const char* fmt, ...) BW_PRINTF_FMT(1, 2);
void warn(const char* fmt, ...) BW_PRINTF_FMT(1, 2);
void error(const char* fmt, ...) BW_PRINTF_FMT(1, 2);

bool verbose();

// Path of the current log file ("" before init).
const std::string& logPath();

} // namespace dbg
} // namespace bw
