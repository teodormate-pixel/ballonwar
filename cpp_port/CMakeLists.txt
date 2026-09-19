# ============================================================
# BalloonWar - cross-platform build (Linux / macOS / Windows)
#
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
#   cmake --build build -j
#
# Dependencies: GLFW, GLEW, OpenSSL (system packages, vcpkg or
# Homebrew). The Makefile in this directory remains the fast
# Linux-only build.
# ============================================================

cmake_minimum_required(VERSION 3.16)
project(BalloonWar VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(BW_BUILD_SERVER "Build the multiplayer server" ON)
option(BW_BUILD_TESTS "Build the test binaries" ON)

set(BW_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH
    "Repository root containing assets/ and models/")

find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(OpenGL REQUIRED)

# ---- GLFW / GLEW ------------------------------------------------
find_package(glfw3 CONFIG QUIET)
if(NOT glfw3_FOUND)
    find_package(glfw3 QUIET)
endif()

find_package(GLEW QUIET)

# Linux fallback: the vendored shared libraries in third_party/
set(BW_VENDORED_GL OFF)
if(NOT TARGET glfw AND UNIX AND NOT APPLE)
    set(_glfw_lib "${CMAKE_CURRENT_SOURCE_DIR}/third_party/lib/libglfw.so")
    if(EXISTS "${_glfw_lib}")
        add_library(glfw SHARED IMPORTED)
        set_target_properties(glfw PROPERTIES IMPORTED_LOCATION "${_glfw_lib}")
        set(BW_VENDORED_GL ON)
    endif()
endif()
if(NOT TARGET GLEW::GLEW AND UNIX AND NOT APPLE)
    set(_glew_lib "${CMAKE_CURRENT_SOURCE_DIR}/third_party/lib/libGLEW.so")
    if(EXISTS "${_glew_lib}")
        add_library(GLEW::GLEW SHARED IMPORTED)
        set_target_properties(GLEW::GLEW PROPERTIES
            IMPORTED_LOCATION "${_glew_lib}"
            INTERFACE_INCLUDE_DIRECTORIES
                "${CMAKE_CURRENT_SOURCE_DIR}/third_party/include")
    endif()
endif()

if(NOT TARGET glfw)
    message(FATAL_ERROR
        "GLFW not found. Install it (apt install libglfw3-dev, "
        "brew install glfw, vcpkg install glfw3) or use the Makefile.")
endif()
if(NOT TARGET GLEW::GLEW)
    message(FATAL_ERROR
        "GLEW not found. Install it (apt install libglew-dev, "
        "brew install glew, vcpkg install glew) or use the Makefile.")
endif()

# ---- sources ----------------------------------------------------
set(BW_COMMON_SRC
    src/game.cpp
    src/ui.cpp
    src/terrain.cpp
    src/world.cpp
    src/water.cpp
    src/model.cpp
    src/anim.cpp
    src/bake.cpp
    src/terraintex.cpp
    src/platform.cpp
    src/debug.cpp)

set(BW_CLIENT_SRC src/main.cpp src/net.cpp ${BW_COMMON_SRC})
set(BW_SERVER_SRC
    src/server_main.cpp
    src/gameserver.cpp
    src/wsserver.cpp
    src/bcrypt_portable.cpp
    src/platform.cpp)

set(BW_INCLUDES
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/include")

# ---- client -----------------------------------------------------
add_executable(balloonwar ${BW_CLIENT_SRC})
target_include_directories(balloonwar PRIVATE ${BW_INCLUDES})
target_link_libraries(balloonwar PRIVATE
    glfw GLEW::GLEW OpenGL::GL OpenSSL::SSL OpenSSL::Crypto Threads::Threads)
if(WIN32)
    target_compile_definitions(balloonwar PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
endif()
if(BW_VENDORED_GL)
    # keep the vendored GLFW/GLEW next to the binary and look them up
    # relative to it (the CI builds use static vcpkg libraries instead)
    set_target_properties(balloonwar PROPERTIES INSTALL_RPATH "$ORIGIN/lib")
    set_target_properties(balloonwar PROPERTIES BUILD_RPATH
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/lib")
endif()

# ---- server -----------------------------------------------------
if(BW_BUILD_SERVER)
    add_executable(balloonwar-server ${BW_SERVER_SRC})
    target_include_directories(balloonwar-server PRIVATE ${BW_INCLUDES})
    target_link_libraries(balloonwar-server PRIVATE
        OpenSSL::SSL OpenSSL::Crypto Threads::Threads)
    if(WIN32)
        target_link_libraries(balloonwar-server PRIVATE ws2_32 crypt32 bcrypt)
        target_compile_definitions(balloonwar-server PRIVATE
            NOMINMAX WIN32_LEAN_AND_MEAN)
    endif()
endif()

# ---- tests ------------------------------------------------------
if(BW_BUILD_TESTS)
    enable_testing()

    add_executable(smoke_test
        tests/smoke_test.cpp
        src/game.cpp src/ui.cpp src/terrain.cpp src/world.cpp src/water.cpp
        src/model.cpp src/anim.cpp src/bake.cpp src/terraintex.cpp
        src/platform.cpp src/debug.cpp)
    target_include_directories(smoke_test PRIVATE ${BW_INCLUDES})
    target_link_libraries(smoke_test PRIVATE Threads::Threads)
    add_test(NAME smoke COMMAND smoke_test)

    if(BW_BUILD_SERVER)
        add_executable(server_net_test
            tests/server_net_test.cpp
            src/net.cpp src/game.cpp src/terrain.cpp src/world.cpp
            src/water.cpp src/platform.cpp)
        target_include_directories(server_net_test PRIVATE ${BW_INCLUDES})
        target_link_libraries(server_net_test PRIVATE
            OpenSSL::SSL OpenSSL::Crypto Threads::Threads)
        if(WIN32)
            target_link_libraries(server_net_test PRIVATE ws2_32 crypt32 bcrypt)
        endif()
    endif()
endif()

# ---- packaging --------------------------------------------------
# stage the runtime assets (terrain textures are downscaled so the
# archive stays reasonable); Blender sources/archives are skipped
find_package(Python3 COMPONENTS Interpreter QUIET)
set(BW_ASSETS_DIR "${CMAKE_BINARY_DIR}/release_assets")
if(Python3_Interpreter_FOUND)
    execute_process(
        COMMAND "${Python3_EXECUTABLE}"
                "${CMAKE_CURRENT_SOURCE_DIR}/tools/pack_assets.py"
                "${BW_ROOT}" "${BW_ASSETS_DIR}"
                --terrain-size 512
        RESULT_VARIABLE _pack_result)
    if(NOT _pack_result EQUAL 0)
        message(WARNING "asset staging failed; packaging raw directories")
        set(BW_ASSETS_DIR "${BW_ROOT}")
    endif()
else()
    message(WARNING "Python3 not found; packaging raw asset directories")
    set(BW_ASSETS_DIR "${BW_ROOT}")
endif()

install(TARGETS balloonwar RUNTIME DESTINATION .)
# bundled dynamic libraries (macOS dylibbundler / vendored GLFW+GLEW)
install(DIRECTORY "${CMAKE_BINARY_DIR}/lib" DESTINATION . OPTIONAL)
if(BW_VENDORED_GL)
    install(FILES "${_glfw_lib}" DESTINATION lib RENAME libglfw.so.3)
    install(FILES "${_glew_lib}" DESTINATION lib RENAME libGLEW.so.2.2)
endif()
if(BW_BUILD_SERVER)
    install(TARGETS balloonwar-server RUNTIME DESTINATION .)
endif()
if(BW_ASSETS_DIR STREQUAL BW_ROOT)
    install(DIRECTORY "${BW_ROOT}/assets" DESTINATION .)
    install(DIRECTORY "${BW_ROOT}/models" DESTINATION .)
else()
    install(DIRECTORY "${BW_ASSETS_DIR}/" DESTINATION .)
endif()
install(FILES "${BW_ROOT}/README.md" DESTINATION . RENAME README.md
        OPTIONAL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/README.md" DESTINATION .
        RENAME README-cpp.md OPTIONAL)

set(CPACK_PACKAGE_NAME "BalloonWar")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VENDOR "BalloonWar")
set(CPACK_GENERATOR "ZIP")
set(CPACK_PACKAGE_FILE_NAME
    "BalloonWar-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
include(CPack)
