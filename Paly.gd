extends Button

# Calea către scena pe care vrei să o deschizi (o poți schimba direct din Inspector)
@export_file("*.tscn") var calea_catre_scena: String = "res://lume.tscn"

func _ready() -> void:
	# Conectăm apăsarea acestui buton (self) la propria funcție
	if not self.button_down.is_connected(_on_button_pressed):
		self.button_down.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	var tree: SceneTree = get_tree()
	if calea_catre_scena != "":
		print("[UI] Buton apăsat! Se încarcă scena: ", calea_catre_scena)

		tree.change_scene_to_file(calea_catre_scena)	
	else:
		print("[UI Eroare] Nu ai setat nicio cale către scenă în Inspector!")
