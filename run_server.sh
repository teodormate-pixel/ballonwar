#!/usr/bin/env bash
# Porneste serverul de joc C++ (cpp_port/balloonwar-server).
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="$SCRIPT_DIR/cpp_port"

if [[ ! -x "$CPP_DIR/balloonwar-server" ]]; then
    echo "Binary-ul serverului lipseste; il construiesc (make server -j4)..."
    make -C "$CPP_DIR" -j4 server
fi

export LD_LIBRARY_PATH="$CPP_DIR/third_party/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$CPP_DIR/balloonwar-server" "$@"
