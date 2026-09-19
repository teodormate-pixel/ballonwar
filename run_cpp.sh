#!/usr/bin/env bash
# Porneste portul C++ BalloonWar (cpp_port/).
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="$SCRIPT_DIR/cpp_port"

if [[ ! -x "$CPP_DIR/balloonwar" ]]; then
    echo "Binary-ul lipseste; il construiesc (make -j4)..."
    make -C "$CPP_DIR" -j4
fi

export BALLOONWAR_ASSET_ROOT="${BALLOONWAR_ASSET_ROOT:-$SCRIPT_DIR}"
export LD_LIBRARY_PATH="$CPP_DIR/third_party/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SCRIPT_DIR"
exec "$CPP_DIR/balloonwar" "$@"
