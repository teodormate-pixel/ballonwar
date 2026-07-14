extends Control

var _CD: Node
var _selected_id: int = 1

func _ready() -> void:
	_CD = get_node("/root/CharacterData")
	_selected_id = _CD.get_default_character_id()
	_build()

func _make_bg_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s

func _build() -> void:
	var panel := Panel.new()
	panel.size = get_viewport_rect().size
	panel.position = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", _make_bg_style(Color(0.08, 0.04, 0.2, 0.92)))
	add_child(panel)

	var title := Label.new()
	title.text = "ALEGE PERSONAJUL"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 30)
	title.size = Vector2(get_viewport_rect().size.x, 60)
	panel.add_child(title)

	var card_container := HBoxContainer.new()
	card_container.position = Vector2(60, 120)
	card_container.size = Vector2(get_viewport_rect().size.x - 120, 440)
	card_container.add_theme_constant_override("separation", 20)
	panel.add_child(card_container)

	for c in _CD.characters:
		var card := _make_card(c)
		card_container.add_child(card)

	var nav := HBoxContainer.new()
	nav.position = Vector2(0, 580)
	nav.size = Vector2(get_viewport_rect().size.x, 60)
	nav.add_theme_constant_override("separation", 40)

	var back_btn := Button.new()
	back_btn.text = "ÎNAPOI"
	back_btn.size = Vector2(200, 50)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn"))
	nav.add_child(back_btn)

	var spacer := Control.new()
	spacer.size = Vector2(1, 1)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(spacer)

	var confirm_btn := Button.new()
	confirm_btn.text = "CONFIRMĂ"
	confirm_btn.size = Vector2(200, 50)
	confirm_btn.pressed.connect(_on_confirm)
	nav.add_child(confirm_btn)

	var nav_center := CenterContainer.new()
	nav_center.size = Vector2(get_viewport_rect().size.x, 60)
	nav_center.position = Vector2(0, 580)
	nav_center.add_child(nav)
	panel.add_child(nav_center)

func _make_card(c: Dictionary) -> Panel:
	var card := Panel.new()
	card.size = Vector2(240, 420)
	card.add_theme_stylebox_override("panel", _make_bg_style(Color(0.12, 0.1, 0.25, 0.9)))
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var preview := SubViewportContainer.new()
	preview.size = Vector2(240, 180)
	preview.position = Vector2(0, 5)
	preview.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(preview)

	var vp := SubViewport.new()
	vp.size = Vector2(240, 180)
	vp.transparent_bg = true
	vp.update_mode = SubViewport.UpdateMode.UPDATE_ALWAYS
	preview.add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1, 2.5)
	cam.look_at(Vector3.ZERO)
	vp.add_child(cam)

	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_char_color(c.id)
	capsule.material = mat
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.8, 0)
	vp.add_child(mesh)

	var name_label := Label.new()
	name_label.text = c["name"]
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.position = Vector2(0, 190)
	name_label.size = Vector2(240, 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_label)

	var stats := Label.new()
	stats.text = "HP: %d\nSPD: %.1f" % [c["base_health"], c["base_speed"]]
	stats.add_theme_font_size_override("font_size", 16)
	stats.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	stats.position = Vector2(10, 225)
	stats.size = Vector2(220, 50)
	card.add_child(stats)

	var abil_title := Label.new()
	abil_title.text = "ABILITĂȚI:"
	abil_title.add_theme_font_size_override("font_size", 14)
	abil_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	abil_title.position = Vector2(10, 275)
	abil_title.size = Vector2(220, 20)
	card.add_child(abil_title)

	for i in range(c["abilities"].size()):
		var a: Dictionary = c["abilities"][i]
		var al := Label.new()
		al.text = "%s (%ds)" % [a["name"], a["cooldown"]]
		al.add_theme_font_size_override("font_size", 12)
		al.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		al.position = Vector2(10, 298 + i * 20)
		al.size = Vector2(220, 20)
		card.add_child(al)

	var select_btn := Button.new()
	select_btn.text = "SELECTEAZĂ"
	select_btn.size = Vector2(180, 36)
	select_btn.position = Vector2(30, 360)
	select_btn.pressed.connect(_on_select.bind(c["id"]))
	card.add_child(select_btn)

	return card

func _get_char_color(id: int) -> Color:
	match id:
		1: return Color(0.8, 0.2, 0.2)
		2: return Color(0.2, 0.6, 0.9)
		3: return Color(0.3, 0.8, 0.3)
		4: return Color(0.9, 0.6, 0.1)
	return Color.WHITE

func _on_select(id: int) -> void:
	_selected_id = id

func _on_confirm() -> void:
	var gs = get_node("/root/GlobalSettings")
	if gs:
		gs.selected_character = _selected_id
	get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn")
