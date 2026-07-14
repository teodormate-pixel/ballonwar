const WebSocket = require("ws");
const url = process.argv[2] || "ws://localhost:8765";
const ws = new WebSocket(url);
let step = 0;
const timer = setInterval(() => {
  if (step === 0) {
    ws.send(JSON.stringify({type:"auth", username:"test", password:"test123"}));
    console.log("1. auth sent");
    step++;
  } else if (step === 2) {
    ws.send(JSON.stringify({type:"create_room", name:"Test Room", settings:{max_players:4}}));
    console.log("3. create_room sent");
    step++;
  } else if (step === 4) {
    ws.send(JSON.stringify({type:"start_game"}));
    console.log("5. start_game sent");
    step++;
  } else if (step === 6) {
    ws.send(JSON.stringify({type:"player_input", keys:{forward:true}, rot_x:0, actions:{}}));
    step++;
  }
}, 1000);
ws.on("open", () => console.log("Connected"));
ws.on("message", (raw) => {
  const msg = JSON.parse(raw);
  console.log("RECV:", JSON.stringify(msg));
  if (msg.type === "auth_ok") { step = 2; console.log("2. auth_ok received"); }
  if (msg.type === "room_created") { step = 4; console.log("4. room_created:", msg.room_id); }
  if (msg.type === "game_started") { step = 6; console.log("6. game_started"); }
});
ws.on("error", (e) => console.log("ERROR:", e.message));
setTimeout(() => { ws.close(); process.exit(0); }, 10000);
