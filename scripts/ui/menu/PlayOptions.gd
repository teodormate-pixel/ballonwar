extends Control

@onready var bg: Panel = $Background
@onready var title_lbl: Label = $Title
@onready var cards: HBoxContainer = $Cards
@onready var back_btn: Button = $BackBtn

var _card_data = [
	{
		"title": "MOD CREATOR",
		"desc": "Construiește cu brush\npe o hartă plată.\nFără generare de teren.",
		"color": Color(0.2, 0.6, 0.9),
		"mode": "creator"
	},
	{
		"title": "SINGLEPLAYER",
		"desc": "Lume generată procedural\ncu resurse, inamici\nși crafting.",
		"color": Color(0.3, 0.8, 0.3),
		"mode": "singleplayer"
	},
	{
		"title": "STRUCTURE EDITOR",
		"desc": "Creează-ți propriile\nstructuri și blueprinturi\npentru construcție.",
		"color": Color(0.8, 0.6, 0.2),
		"mode": "struct_editor"
	}
]

func _ready() -> void:
	bg.add_theme_stylebox_override("panel", _make_style(Color(0.08, 0.04, 0.2, 0.92)))

	var card_idx = 0
	for child in cards.get_children():
		if child is Panel:
			var data = _card_data[card_idx] if card_idx < _card_data.size() else null
			if data:
				_setup_card(child, data)
			card_idx += 1

	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn"))

func _setup_card(card: Panel, data: Dictionary) -> void:
	card.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.1, 0.25, 0.9)))

	var title_label = card.get_node_or_null("CardTitle") as Label
	if title_label:
		title_label.text = data["title"]
		title_label.add_theme_color_override("font_color", data["color"])

	var desc_label = card.get_node_or_null("CardDesc") as Label
	if desc_label:
		desc_label.text = data["desc"]

	var play_btn = card.get_node_or_null("PlayBtn") as Button
	if play_btn:
		var mode = data["mode"]
		match mode:
			"creator":
				play_btn.pressed.connect(_start_creator)
			"struct_editor":
				play_btn.pressed.connect(_start_struct_editor)
			_:
				play_btn.pressed.connect(_start_game.bind(mode))

func _make_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s

func _start_game(mode: String) -> void:
	var wc = get_node("/root/WorldConfig")
	if wc:
		wc.set("game_mode", mode)
	var gs = get_node("/root/GlobalSettings")
	if gs:
		gs.last_game_mode = mode
	get_tree().change_scene_to_file("res://scenes/world/lume.tscn")

func _start_creator() -> void:
	var gs = get_node("/root/GlobalSettings")
	if gs:
		gs.last_game_mode = "creator"
	get_tree().change_scene_to_file("res://scenes/ui/Creator.tscn")

func _start_struct_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/structure/StructureEditor.tscn")
