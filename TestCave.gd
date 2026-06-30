extends Node3D

@onready var teren: Node3D = $Teren
@onready var player: CharacterBody3D = $StarterPlayer

var _hud: CanvasLayer
var _info: Label
var _entrance_digged: bool = false

func _ready() -> void:
	_create_hud()
	_configura_teren()
	if teren and teren.has_method("cautare_jucator_securizata"):
		await get_tree().create_timer(0.5).timeout
		teren.cautare_jucator_securizata()

func _configura_teren() -> void:
	if not teren:
		return
	teren.set("cave_enabled", true)
	teren.set("cave_frequency", 0.035)
	teren.set("cave_threshold", 0.22)
	teren.set("cave_max_depth", 50)
	teren.set("cave_min_y", 5)
	teren.set("distanta_randare", 2)

func _create_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 128
	add_child(_hud)
	_info = Label.new()
	_info.position = Vector2(10, 10)
	_info.add_theme_color_override("font_color", Color(0, 1, 0))
	_info.add_theme_font_size_override("font_size", 18)
	_info.text = """TEST PESTERI
[F] — Sapă intrare în peșteră
[G] — Arată/Nascunde info
Mouse — Privește
WASD — Mișcare
Click stânga — Sapă"""
	_hud.add_child(_info)

	var btn_label := Label.new()
	btn_label.position = Vector2(10, 160)
	btn_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
	btn_label.add_theme_font_size_override("font_size", 14)
	btn_label.text = "Sapă în jos cu [F] pentru a găsi peșteri!"
	_hud.add_child(btn_label)
	btn_label.name = "Hint"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_creeaza_intrare()
			KEY_G:
				_info.visible = not _info.visible

func _creeaza_intrare() -> void:
	if not teren or not teren.has_method("get_surface_height_at") or not teren.has_method("sapa_sfera"):
		return
	if not player:
		return
	var px: int = int(floor(player.global_position.x))
	var pz: int = int(floor(player.global_position.z))
	var sy: float = teren.get_surface_height_at(float(px), float(pz))
	if sy <= 0:
		return
	var path_points := [
		Vector3(px, sy, pz),
		Vector3(px, sy - 2, pz),
		Vector3(px + 1, sy - 4, pz),
		Vector3(px + 1, sy - 6, pz + 1),
		Vector3(px, sy - 8, pz + 1),
		Vector3(px, sy - 10, pz),
	]
	for i in range(path_points.size() - 1):
		var a: Vector3 = path_points[i]
		var b: Vector3 = path_points[i + 1]
		var steps: int = maxi(1, int(round(a.distance_to(b) / 0.5)))
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var pos: Vector3 = a.lerp(b, t)
			var dir_down := Vector3.DOWN
			teren.sapa_sfera(pos, dir_down, 1.5)
	await get_tree().create_timer(0.5).timeout
	_entrance_digged = true
	var hint: Label = _hud.get_node_or_null("Hint")
	if hint:
		hint.text = "Intrare creată! Apropie-te de gaură și sapi mai adânc."
