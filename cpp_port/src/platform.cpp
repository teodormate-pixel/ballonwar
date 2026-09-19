#include "platform.h"

#include <chrono>
#include <cstring>
#include <thread>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>

#include <io.h>
#else
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/prctl.h>
#endif
#endif

namespace plat {

#ifdef _WIN32

ProcessHandle spawnDetached(const std::vector<std::string>& argv) {
    if (argv.empty())
        return 0;
    std::string cmdline;
    for (const auto& a : argv) {
        if (!cmdline.empty())
            cmdline += ' ';
        cmdline += '"';
        cmdline += a;
        cmdline += '"';
    }
    std::vector<char> mutableCmd(cmdline.begin(), cmdline.end());
    mutableCmd.push_back('\0');
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessA(nullptr, mutableCmd.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi))
        return 0;
    CloseHandle(pi.hThread);
    return (ProcessHandle)pi.hProcess;
}

void terminate(ProcessHandle handle) {
    if (handle)
        TerminateProcess((HANDLE)handle, 1);
}

bool alive(ProcessHandle handle) {
    if (!handle)
        return false;
    return WaitForSingleObject((HANDLE)handle, 0) == WAIT_TIMEOUT;
}

bool waitExit(ProcessHandle handle, int timeoutMs) {
    if (!handle)
        return true;
    return WaitForSingleObject((HANDLE)handle, (DWORD)timeoutMs) ==
           WAIT_OBJECT_0;
}

void release(ProcessHandle handle) {
    if (handle)
        CloseHandle((HANDLE)handle);
}

void sleepMs(int ms) { Sleep((DWORD)ms); }

void initSockets() {
    WSADATA data;
    WSAStartup(MAKEWORD(2, 2), &data);
}

void shutdownSockets() { WSACleanup(); }

bool fileReadable(const std::string& path) {
    return _access(path.c_str(), 4) == 0; // 4 = read
}

#else // POSIX

ProcessHandle spawnDetached(const std::vector<std::string>& argv) {
    if (argv.empty())
        return 0;
    const pid_t pid = fork();
    if (pid != 0)
        return (ProcessHandle)pid;
    // child: die with the parent so no orphaned audio player is left
    // behind when the game is killed or crashes
#ifdef __linux__
    prctl(PR_SET_PDEATHSIG, SIGTERM);
#endif
    if (getppid() == 1)
        _exit(0);
    std::vector<char*> args;
    args.reserve(argv.size() + 1);
    for (const auto& a : argv)
        args.push_back(const_cast<char*>(a.c_str()));
    args.push_back(nullptr);
    execvp(args[0], args.data());
    _exit(127);
}

void terminate(ProcessHandle handle) {
    if (handle > 0)
        kill((pid_t)handle, SIGTERM);
}

bool alive(ProcessHandle handle) {
    if (handle <= 0)
        return false;
    int status = 0;
    const pid_t r = waitpid((pid_t)handle, &status, WNOHANG);
    return r == 0; // 0 = still running, pid = exited, -1 = unknown
}

bool waitExit(ProcessHandle handle, int timeoutMs) {
    if (handle <= 0)
        return true;
    for (int waited = 0; waited < timeoutMs; waited += 10) {
        int status = 0;
        const pid_t r = waitpid((pid_t)handle, &status, WNOHANG);
        if (r == (pid_t)handle || r == -1) // exited or already reaped
            return true;
        sleepMs(10);
    }
    return false;
}

void release(ProcessHandle handle) { (void)handle; }

void sleepMs(int ms) {
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

void initSockets() {}

void shutdownSockets() {}

bool fileReadable(const std::string& path) {
    return access(path.c_str(), R_OK) == 0;
}

#endif

} // namespace plat
