const defaultCharacters = [
  {
    id: 1,
    name: 'Bombardier',
    model_path: 'res://characters/bombardier/bombardier.tscn',
    abilities: [
      { name: 'Triple Shot', desc: 'Trage 3 gloanțe odată', cooldown: 5 },
      { name: 'Scut', desc: 'Scut temporar 3s', cooldown: 10 },
    ],
    base_speed: 10.0,
    base_health: 100,
    thumbnail: '',
  },
  {
    id: 2,
    name: 'Scout',
    model_path: 'res://characters/scout/scout.tscn',
    abilities: [
      { name: 'Sprint', desc: 'Aleargă de 2x mai repede 2s', cooldown: 6 },
      { name: 'Salt Înalt', desc: 'Salt de 3x mai sus', cooldown: 8 },
    ],
    base_speed: 14.0,
    base_health: 80,
    thumbnail: '',
  },
  {
    id: 3,
    name: 'Tank',
    model_path: 'res://characters/tank/tank.tscn',
    abilities: [
      { name: 'Armură', desc: 'Reduce damage cu 50% 4s', cooldown: 12 },
      { name: 'Baraj', desc: 'Trage o ploaie de gloanțe', cooldown: 15 },
    ],
    base_speed: 7.0,
    base_health: 150,
    thumbnail: '',
  },
  {
    id: 4,
    name: 'Engineer',
    model_path: 'res://characters/engineer/engineer.tscn',
    abilities: [
      { name: 'Vindecare', desc: 'Vindecă 30 HP', cooldown: 10 },
      { name: 'Turn', desc: 'Plasează un turn automat', cooldown: 20 },
    ],
    base_speed: 9.0,
    base_health: 90,
    thumbnail: '',
  },
];

function getCharacterById(id) {
  return defaultCharacters.find((c) => c.id === id) || null;
}

function getDefaultCharacterId() {
  return 1;
}

module.exports = { getCharacterById, getDefaultCharacterId };
