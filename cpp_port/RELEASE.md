# BalloonWar - build si release (Linux / macOS / Windows)

Clientul (`balloonwar`) si serverul (`balloonwar-server`) se construiesc
cu CMake pe toate cele trei platforme. `Makefile`-ul rămâne build-ul rapid
doar pentru Linux.

## Build local

Dependinte: **GLFW** si **OpenSSL** (si un compilator C++17). Functiile
OpenGL 3.3 sunt incarcate prin `src/glloader.cpp` (fara GLEW).

```bash
# Linux (Ubuntu/Debian)
sudo apt install cmake ninja-build build-essential libglfw3-dev \
                 libssl-dev libx11-dev libxrandr-dev libxinerama-dev \
                 libxcursor-dev libxi-dev libgl1-mesa-dev python3-pil
cmake -S cpp_port -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure

# macOS (Homebrew)
brew install cmake glfw openssl@3 python dylibbundler
cmake -S cpp_port -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$(brew --prefix openssl@3)"
cmake --build build -j

# Windows (vcpkg)
vcpkg install glfw3:x64-windows-static openssl:x64-windows-static
cmake -S cpp_port -B build -A x64 \
      -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%/scripts/buildsystems/vcpkg.cmake \
      -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
```

Fara pachete de sistem, pe Linux se folosesc automat bibliotecile din
`cpp_port/third_party/` (GLFW/GLEW livrate cu proiectul).

## Pachet de release

```bash
cd build
cpack -G ZIP          # Windows: cpack -G ZIP -C Release
```

CPack instaleaza binarele plus asset-urile de runtime (modele `.glb`,
audio, texturi de teren reduse la 512 px prin
`cpp_port/tools/pack_assets.py`). Fisierele Blender (`.blend`),
arhivele si `.import`-urile Godot nu intra in pachet.

## Release automat (GitHub Actions)

Workflow-ul `.github/workflows/release.yml` construieste **4 pachete**:
`ubuntu-latest`, `macos-latest` (ARM64, Homebrew + dylibbundler),
`macos-latest` cross-compilat pentru **Intel (x86_64)** cu vcpkg si
`windows-latest` (static, vcpkg). GitHub a retras runner-ele Intel, deci
build-ul x86_64 de macOS se face prin cross-compilare
(`CMAKE_OSX_ARCHITECTURES=x86_64`, triplet vcpkg `x64-osx`).

```bash
git add . && git commit -m "release"
git tag v1.0.0
git push origin master --tags
```

La tag, artefactele sunt atasate automat la GitHub Release
(`BalloonWar-1.0.0-Linux-x86_64.zip` etc.). Se poate rula si manual
din tab-ul Actions (`workflow_dispatch`).

## Ce contine pachetul

```
BalloonWar-<versiune>-<platforma>/
  balloonwar[.exe]          # clientul
  balloonwar-server[.exe]   # serverul de multiplayer
  lib/                      # GLFW (Linux) / dylib-uri (macOS ARM)
  models/                   # personaj, balon, sageata, spawner
  assets/                   # audio + texturi PBR de teren
```

## Note

- **Audio**: clientul reda sunetele prin `mpv` (sau `paplay`) daca sunt
  instalate si in PATH; fara ele jocul ruleaza silentios. Procesele de
  audio sunt legate de joc (mor cu el) pe toate platformele.
- **Serverul** nu mai depinde de `libcrypt`/MySQL: parolele folosesc
  bcrypt portabil (OpenBSD, ISC), conturile se pastreaza in
  `BW_USERS_FILE` (JSON, implicit `~/.local/share/balloonwar/server_users.json`).
- Variabile: `PORT`, `BIND`, `TLS_CERT`, `TLS_KEY`, `BW_TICK_RATE`,
  `BW_BCRYPT_ROUNDS`, `BW_MAX_PLAYERS`, `BW_USERS_FILE`.
- Terenul foloseste texturile PBR din `assets/textures/`; in pachet sunt
  reduse la 512 px (jocul le reesantioneaza la 256 px si le cache-uieste
  in `~/.cache/balloonwar/terrain.bin`).
