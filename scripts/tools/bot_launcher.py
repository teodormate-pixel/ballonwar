"""
Launches N headless bot clients that auto-connect to a running game server.
Bots walk toward the nearest remote player and stop in front of them.

Usage:
  python tools/bot_launcher.py [--count N] [--connect IP:PORT] [--godot PATH]

Examples:
  python tools/bot_launcher.py --count 3 --connect 127.0.0.1:8912
  python tools/bot_launcher.py --count 5
"""

import subprocess
import sys
import os
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))


def find_godot():
    candidates = [
        r"C:\Program Files\Godot\godot.exe",
        r"C:\Program Files\Godot 4\godot.exe",
        r"C:\Program Files (x86)\Godot\godot.exe",
        r"C:\Program Files (x86)\Godot 4\godot.exe",
        os.path.expandvars(r"%USERPROFILE%\AppData\Local\Godot\godot.exe"),
        os.path.expandvars(r"%USERPROFILE%\AppData\Local\Godot4\godot.exe"),
        os.path.expandvars(r"%USERPROFILE%\AppData\Roaming\Godot\godot.exe"),
        os.path.expandvars(r"%LOCALAPPDATA%\Godot\godot.exe"),
        os.path.expandvars(r"%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe"),
        os.path.expandvars(r"%USERPROFILE%\Downloads\godot.exe"),

    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    try:
        result = subprocess.run(["where", "godot"], capture_output=True, text=True)
        if result.returncode == 0:
            path = result.stdout.strip().split("\n")[0]
            if os.path.isfile(path):
                return path
    except:
        pass
    downloads = os.path.expandvars(r"%USERPROFILE%\Downloads")
    if os.path.isdir(downloads):
        for f in os.listdir(downloads):
            if f.lower().startswith("godot") and f.endswith(".exe"):
                return os.path.join(downloads, f)
    return "godot"


def main():
    parser = argparse.ArgumentParser(description="Launch bot clients for Balloon War")
    parser.add_argument("--count", type=int, default=1, help="Number of bots (default: 1)")
    parser.add_argument("--connect", default="127.0.0.1:8912", help="Server IP:PORT")
    parser.add_argument("--godot", default=find_godot(), help="Path to Godot executable")
    args = parser.parse_args()

    godot_exe = args.godot
    if not os.path.isfile(godot_exe):
        print(f"Error: Godot not found at '{godot_exe}'")
        print()
        print("How to fix:")
        print("  1. Find your godot.exe path (e.g. search 'godot.exe' in File Explorer)")
        print("  2. Run with --godot, e.g.:")
        print(f'     python tools\\bot_launcher.py --count 2 --godot "C:\\Path\\To\\godot.exe"')
        print()
        print("  Common locations to check:")
        print("    - C:\\Program Files\\Godot\\godot.exe")
        print("    - C:\\Program Files\\Godot 4\\godot.exe")
        print("    - %USERPROFILE%\\Downloads\\Godot_v4.x-stable_win64.exe")
        sys.exit(1)

    print(f"Spawning {args.count} bot(s) connecting to {args.connect}...")
    processes = []
    for i in range(args.count):
        cmd = [
            godot_exe,
            "--path", PROJECT_DIR,
            "--headless",
            "--scene", "res://lume.tscn",
            "--",
            f"--bot-connect={args.connect}",
        ]
        proc = subprocess.Popen(cmd)
        processes.append(proc)
        print(f"  Bot {i+1} spawned (PID {proc.pid})")

    print(f"\n{args.count} bot(s) running. Press Ctrl+C to kill all.")
    try:
        for p in processes:
            p.wait()
    except KeyboardInterrupt:
        print("\nKilling bots...")
        for p in processes:
            p.kill()
        print("Done.")


if __name__ == "__main__":
    main()
