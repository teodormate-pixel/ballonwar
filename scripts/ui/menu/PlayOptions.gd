extends Control

func _make_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s

func _ready() -> void:
	var panel := Panel.new()
	panel.size = get_viewport_rect().size
	panel.position = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.08, 0.04, 0.2, 0.92)))
	add_child(panel)

	var title := Label.new()
	title.text = "Alege modul de joc"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 80)
	title.size = Vector2(get_viewport_rect().size.x, 60)
	panel.add_child(title)

	var cont := HBoxContainer.new()
	cont.position = Vector2(120, 200)
	cont.size = Vector2(get_viewport_rect().size.x - 240, 500)
	cont.add_theme_constant_override("separation", 50)
	panel.add_child(cont)

	var cards = [
		{
			"title": "MOD CREATOR",
			"desc": "Construiește cu brush\npe o hartă plată.\nFără generare de teren.",
			"color": Color(0.2, 0.6, 0.9),
			"scene": "res://scenes/world/lume.tscn",
			"mode": "creator"
		},
		{
			"title": "SINGLEPLAYER",
			"desc": "Lume generată procedural\ncu resurse, inamici\nși crafting.",
			"color": Color(0.3, 0.8, 0.3),
			"scene": "res://scenes/world/lume.tscn",
			"mode": "singleplayer"
		}
	]

	for c in cards:
		var card := Panel.new()
		card.size = Vector2(380, 460)
		card.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.1, 0.25, 0.9)))
		cont.add_child(card)

		var title_lbl := Label.new()
		title_lbl.text = c["title"]
		title_lbl.add_theme_font_size_override("font_size", 32)
		title_lbl.add_theme_color_override("font_color", c["color"])
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.position = Vector2(0, 20)
		title_lbl.size = Vector2(380, 50)
		card.add_child(title_lbl)

		var desc := Label.new()
		desc.text = c["desc"]
		desc.add_theme_font_size_override("font_size", 20)
		desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.position = Vector2(20, 100)
		desc.size = Vector2(340, 160)
		card.add_child(desc)

		var play_btn := Button.new()
		play_btn.text = "JOACĂ"
		play_btn.size = Vector2(240, 50)
		play_btn.position = Vector2(70, 340)
		play_btn.pressed.connect(_start_game.bind(c["mode"], c["scene"]))
		card.add_child(play_btn)

	var back_btn := Button.new()
	back_btn.text = "ÎNAPOI"
	back_btn.size = Vector2(200, 50)
	back_btn.position = Vector2(get_viewport_rect().size.x / 2 - 100, 720)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn"))
	panel.add_child(back_btn)

func _start_game(mode: String, scene: String) -> void:
	var wc = get_node("/root/WorldConfig")
	if wc and wc.has_method("set"):
		wc.set("game_mode", mode)
	var gs = get_node("/root/GlobalSettings")
	if gs:
		gs.last_game_mode = mode
	get_tree().change_scene_to_file(scene)
