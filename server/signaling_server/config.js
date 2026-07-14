const config = {
  port: parseInt(process.env.PORT) || 8765,
  db: {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'teodor_ballon',
    password: process.env.DB_PASS || '',
    database: process.env.DB_NAME || 'teodor_ballon_war',
  },
  tickRate: 20,
  tickInterval: 1000 / 20,
  bcryptRounds: 10,
  maxRooms: 100,
  roomCodeLength: 4,
  maxPlayersPerRoom: 8,
  gameModes: [
    { id: 'free_for_all', name: 'Free For All', desc: 'Fiecare pentru sine', min_players: 2, max_players: 8 },
    { id: 'team_deathmatch', name: 'Team Deathmatch', desc: 'Echipe roșu vs albastru', min_players: 4, max_players: 8 },
    { id: 'last_man_standing', name: 'Last Man Standing', desc: 'Ultimul supraviețuitor câștigă', min_players: 2, max_players: 8 },
    { id: 'capture_the_flag', name: 'Capture the Flag', desc: 'Fură steagul adversarului', min_players: 4, max_players: 8 },
    { id: 'balloon_hunt', name: 'Balloon Hunt', desc: 'Jumate din jucători sunt baloane, cealaltă jumate vânează', min_players: 4, max_players: 8 },
  ],
};

module.exports = config;
