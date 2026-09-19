CXX      = g++
CXXFLAGS = -O2 -g -std=c++17 -Wall -Wextra -Isrc -Ithird_party/include
LDFLAGS  = -Lthird_party/lib
LDLIBS   = -lglfw -lGL -lssl -lcrypto -ldl -lpthread -lm

SAN = -fsanitize=address,undefined -fno-omit-frame-pointer

SRC = src/main.cpp src/game.cpp src/ui.cpp src/net.cpp src/terrain.cpp \
      src/world.cpp src/water.cpp src/model.cpp src/anim.cpp src/bake.cpp \
      src/terraintex.cpp src/platform.cpp src/glloader.cpp src/debug.cpp
OBJ = $(SRC:src/%.cpp=build/%.o)
DBGOBJ = $(SRC:src/%.cpp=build_debug/%.o)
HDR = src/game.h src/ui.h src/net.h src/terrain.h src/world.h src/water.h \
      src/model.h src/anim.h src/bake.h src/terraintex.h src/font_data.h src/debug.h \
      src/platform.h src/glloader.h src/glcorearb.h src/bcrypt_portable.h \
      src/wsserver.h src/gameserver.h

SERVER_SRC = src/server_main.cpp src/gameserver.cpp src/wsserver.cpp \
             src/bcrypt_portable.cpp src/platform.cpp
SERVER_OBJ = $(SERVER_SRC:src/%.cpp=build/%.o)
SERVER_BIN = balloonwar-server

BIN = balloonwar
BIN_DEBUG = balloonwar_debug

.PHONY: all clean run test test_net test_server bench debug test_san server

all: $(BIN) $(SERVER_BIN)

$(BIN): $(OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $(OBJ) $(LDLIBS)

# game server (no OpenGL): WebSocket + JSON protocol + game loop
server: $(SERVER_BIN)

$(SERVER_BIN): $(SERVER_OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $(SERVER_OBJ) \
	    -lssl -lcrypto -ldl -lpthread -lm

build/%.o: src/%.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) -c -o $@ $<

build:
	mkdir -p build

build_debug:
	mkdir -p build_debug

# AddressSanitizer + UndefinedBehaviorSanitizer build
$(BIN_DEBUG): $(DBGOBJ)
	$(CXX) $(CXXFLAGS) $(SAN) $(LDFLAGS) -o $@ $(DBGOBJ) $(LDLIBS)

build_debug/%.o: src/%.cpp $(HDR) | build_debug
	$(CXX) $(CXXFLAGS) $(SAN) -c -o $@ $<

debug: $(BIN_DEBUG)

run: $(BIN)
	LD_LIBRARY_PATH=third_party/lib:$$LD_LIBRARY_PATH ./$(BIN)

test: build/smoke_test
	LD_LIBRARY_PATH=third_party/lib:$$LD_LIBRARY_PATH ./build/smoke_test

build/smoke_test: tests/smoke_test.cpp src/game.cpp src/ui.cpp src/debug.cpp \
                  src/terrain.cpp src/world.cpp src/water.cpp src/model.cpp \
                  src/anim.cpp src/bake.cpp src/terraintex.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) -o $@ $(filter %.cpp,$^) -lpthread -lm

# smoke test under sanitizers (no OpenGL)
build/smoke_test_san: tests/smoke_test.cpp src/game.cpp src/ui.cpp src/debug.cpp \
                      src/terrain.cpp src/world.cpp src/water.cpp src/model.cpp \
                      src/anim.cpp src/bake.cpp src/terraintex.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) $(SAN) -o $@ $(filter %.cpp,$^) -lpthread -lm

test_san: build/smoke_test_san
	ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=print_stacktrace=1 \
	    ./build/smoke_test_san

build/net_test: tests/net_test.cpp src/net.cpp src/game.cpp src/terrain.cpp \
                src/world.cpp src/water.cpp src/platform.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) -o $@ $(filter %.cpp,$^) -lssl -lcrypto -lpthread -lm

# end-to-end: the real C++ client against the C++ game server
build/server_net_test: tests/server_net_test.cpp src/net.cpp src/game.cpp \
                       src/terrain.cpp src/world.cpp src/water.cpp \
                       src/platform.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) -o $@ $(filter %.cpp,$^) -lssl -lcrypto -lpthread -lm

build/bench_client: tests/bench_client.cpp src/net.cpp src/game.cpp \
                    src/terrain.cpp src/world.cpp src/water.cpp \
                    src/platform.cpp $(HDR) | build
	$(CXX) $(CXXFLAGS) -o $@ $(filter %.cpp,$^) -lssl -lcrypto -lpthread -lm

bench: $(SERVER_BIN) build/bench_client
	@rm -f /tmp/bw_bench_users.json; \
	BW_USERS_FILE=/tmp/bw_bench_users.json PORT=9893 ./$(SERVER_BIN) \
	    >/tmp/bw_bench.log 2>&1 & \
	SERVER_PID=$$!; \
	sleep 0.7; \
	./build/bench_client ws://127.0.0.1:9893 20 2000; \
	RESULT=$$?; \
	kill $$SERVER_PID 2>/dev/null; \
	exit $$RESULT

# starts the Python mock WebSocket server, runs the client, stops it;
# then repeats the test over TLS (wss://) with a self-signed certificate
# starts the C++ server on a test port and runs the protocol clients
# (plain ws:// then wss:// with a self-signed certificate)
test_server: $(SERVER_BIN) build/server_net_test
	@rm -f /tmp/bw_server_users.json; \
	BW_USERS_FILE=/tmp/bw_server_users.json PORT=9879 ./$(SERVER_BIN) \
	    >/tmp/bw_server.log 2>&1 & \
	SERVER_PID=$$!; \
	sleep 0.7; \
	BW_NET_URL=ws://127.0.0.1:9879 ./build/server_net_test; R1=$$?; \
	python3 tests/server_client.py 9879; R2=$$?; \
	kill $$SERVER_PID 2>/dev/null; \
	wait $$SERVER_PID 2>/dev/null; \
	if [ $$R1 -ne 0 ] || [ $$R2 -ne 0 ]; then \
	    echo "--- server log ---"; cat /tmp/bw_server.log; exit 1; \
	fi; \
	openssl req -x509 -newkey rsa:2048 -keyout /tmp/bw_srv_key.pem \
	    -out /tmp/bw_srv_cert.pem -days 2 -nodes -subj "/CN=127.0.0.1" \
	    >/dev/null 2>&1 || true; \
	BW_USERS_FILE=/tmp/bw_server_users.json PORT=9880 \
	    TLS_CERT=/tmp/bw_srv_cert.pem TLS_KEY=/tmp/bw_srv_key.pem \
	    ./$(SERVER_BIN) >/tmp/bw_server_tls.log 2>&1 & \
	SERVER_PID=$$!; \
	sleep 0.7; \
	BW_NET_URL=wss://127.0.0.1:9880 BW_TLS_INSECURE=1 \
	    ./build/server_net_test; R3=$$?; \
	python3 tests/server_client.py 9880 tls; R4=$$?; \
	kill $$SERVER_PID 2>/dev/null; \
	wait $$SERVER_PID 2>/dev/null; \
	if [ $$R3 -ne 0 ] || [ $$R4 -ne 0 ]; then \
	    echo "--- tls server log ---"; cat /tmp/bw_server_tls.log; exit 1; \
	fi

test_net: build/net_test
	@python3 tests/mock_ws_server.py 9876 >/tmp/bw_mock_ws.log 2>&1 & \
	MOCK_PID=$$!; \
	sleep 1; \
	LD_LIBRARY_PATH=third_party/lib ./build/net_test; \
	RESULT=$$?; \
	kill $$MOCK_PID 2>/dev/null; \
	if [ $$RESULT -ne 0 ]; then exit $$RESULT; fi; \
	openssl req -x509 -newkey rsa:2048 -keyout /tmp/bw_key.pem \
	    -out /tmp/bw_cert.pem -days 2 -nodes -subj "/CN=127.0.0.1" \
	    >/dev/null 2>&1 || true; \
	python3 tests/mock_ws_server.py 9877 /tmp/bw_cert.pem /tmp/bw_key.pem \
	    >/tmp/bw_mock_tls.log 2>&1 & \
	MOCK_PID=$$!; \
	sleep 1; \
	BW_NET_URL=wss://127.0.0.1:9877 BW_TLS_INSECURE=1 \
	    LD_LIBRARY_PATH=third_party/lib ./build/net_test; \
	RESULT=$$?; \
	kill $$MOCK_PID 2>/dev/null; \
	exit $$RESULT

clean:
	rm -rf build build_debug $(BIN) $(BIN_DEBUG) $(SERVER_BIN)
