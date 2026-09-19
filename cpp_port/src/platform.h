// ============================================================
// Small platform abstraction (Windows / macOS / Linux)
//
// Detached child processes (audio helpers), process control,
// sleeping, socket subsystem init and file access. Keeps the
// POSIX/Windows differences out of the game and server code.
// ============================================================

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace plat {

using ProcessHandle = intptr_t;

// spawns a detached helper process (audio players); returns a handle
// (0 on failure). On Linux the child dies with the game even on SIGKILL.
ProcessHandle spawnDetached(const std::vector<std::string>& argv);

// asks the process to terminate (SIGTERM / TerminateProcess)
void terminate(ProcessHandle handle);

// true while the process is running (non-blocking)
bool alive(ProcessHandle handle);

// waits up to timeoutMs for the process to exit; returns true if it did
bool waitExit(ProcessHandle handle, int timeoutMs);

// releases the handle (no effect on the running process)
void release(ProcessHandle handle);

void sleepMs(int ms);

// socket subsystem (WSAStartup on Windows, no-op elsewhere)
void initSockets();
void shutdownSockets();

// portable access(path, R_OK)
bool fileReadable(const std::string& path);

} // namespace plat
