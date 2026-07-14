extends Node

const RECIPES_FILE: String = "res://resources/recipes.json"
const GRID_SIZE: int = 20

var recipes: Array = []
var grid: Dictionary = {}

func _ready() -> void:
	_load_recipes()

func _load_recipes() -> void:
	if not ResourceLoader.exists(RECIPES_FILE):
		return
	var file = FileAccess.open(RECIPES_FILE, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err == OK and json.data is Dictionary and json.data.has("recipes"):
		recipes = json.data["recipes"]

func get_recipes_for_mode(mode: String = "workbench") -> Array:
	var result: Array = []
	for r in recipes:
		if r.get("mode", "workbench") == mode:
			result.append(r)
	return result

func check_recipe(ingredient_counts: Dictionary, mode: String = "workbench") -> Dictionary:
	for r in recipes:
		if r.get("mode", "workbench") != mode:
			continue
		var ings: Dictionary = r["ingredients"]
		var match_all: bool = true
		for key in ings:
			var needed: int = ings[key]
			var have: int = ingredient_counts.get(key, 0)
			if have < needed:
				match_all = false
				break
		if match_all:
			return r
	return {}

func can_craft(recipe: Dictionary, inventory: Dictionary) -> bool:
	var ings: Dictionary = recipe["ingredients"]
	for key in ings:
		var needed: int = ings[key]
		var have: int = inventory.get(int(key), 0)
		if have < needed:
			return false
	return true

func craft(recipe: Dictionary, inventory: Dictionary) -> bool:
	if not can_craft(recipe, inventory):
		return false
	var ings: Dictionary = recipe["ingredients"]
	for key in ings:
		var needed: int = ings[key]
		var bt: int = int(key)
		if inventory.has(bt):
			inventory[bt] -= needed
			if inventory[bt] <= 0:
				inventory.erase(bt)
	var result: Dictionary = recipe["result"]
	var rtype: int = result["type"]
	var rcount: int = result.get("count", 1)
	if inventory.has(rtype):
		inventory[rtype] += rcount
	else:
		inventory[rtype] = rcount
	return true

func scan_grid_from_inventory(inventory: Dictionary, mode: String = "workbench") -> Array:
	var counts: Dictionary = {}
	for bt in inventory:
		if inventory[bt] > 0:
			counts[str(bt)] = inventory[bt]
	var found: Array = []
	for r in recipes:
		if r.get("mode", "workbench") != mode:
			continue
		if can_craft(r, inventory):
			found.append(r)
	return found
