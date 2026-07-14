extends Panel

signal confirmed(character_id: int)

var selected_id: int = 1
var _CD
var _cards: Dictionary = {}
var _confirm_btn: Button
var _ready_label: Label

func _ready():
	_CD = get_node("/root/CharacterData")
	_build()

func _build():
	add_theme_stylebox_override("panel", _style(Color(0.06, 0.06, 0.12, 0.85)))

	var hb = HBoxContainer.new()
	hb.anchors_preset = PRESET_FULL_RECT
	hb.add_theme_constant_override("separation", 6)
	hb.add_theme_constant_override("margin_left", 8)
	hb.add_theme_constant_override("margin_right", 8)
	hb.add_theme_constant_override("margin_top", 6)
	hb.add_theme_constant_override("margin_bottom", 6)
	add_child(hb)

	var title = Label.new()
	title.text = "CHARACTER:"
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
	title.add_theme_font_size_override("font_size", 14)
	title.custom_minimum_size.x = 80
	hb.add_child(title)

	for c in _CD.characters:
		var card = _make_card(c)
		hb.add_child(card)
		_cards[c["id"]] = card

	var sep = VSeparator.new()
	hb.add_child(sep)

	_confirm_btn = Button.new()
	_confirm_btn.text = "CONFIRM"
	_confirm_btn.custom_minimum_size.x = 100
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	_confirm_btn.pressed.connect(_on_confirm)
	hb.add_child(_confirm_btn)

	_ready_label = Label.new()
	_ready_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_ready_label.add_theme_font_size_override("font_size", 12)
	_ready_label.custom_minimum_size.x = 100
	hb.add_child(_ready_label)

func _make_card(data: Dictionary) -> Button:
	var cid = data["id"]
	var card = Button.new()
	card.custom_minimum_size = Vector2(150, 44)
	card.flat = true
	card.add_theme_color_override("font_color", Color(1, 1, 1))
	card.add_theme_font_size_override("font_size", 12)
	var is_sel = cid == selected_id
	card.add_theme_stylebox_override("normal", _card_style(is_sel))
	card.add_theme_stylebox_override("hover", _card_style(is_sel))
	card.add_theme_stylebox_override("pressed", _card_style(true))
	card.add_theme_stylebox_override("focus", _card_style(is_sel))
	card.text = data["name"] + "  HP:" + str(data["base_health"]) + " SPD:" + str(data["base_speed"])
	card.pressed.connect(_on_card_pressed.bind(cid))
	return card

func _on_card_pressed(cid: int):
	_select(cid)

func _select(cid: int):
	selected_id = cid
	for id in _cards:
		var style = _card_style(id == cid)
		_cards[id].add_theme_stylebox_override("normal", style)
		_cards[id].add_theme_stylebox_override("hover", style)
		_cards[id].add_theme_stylebox_override("pressed", style)

func _on_confirm():
	confirmed.emit(selected_id)

func set_ready_status(text: String):
	if _ready_label:
		_ready_label.text = text

func _style(bg: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	return s

func _card_style(selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	if selected:
		s.border_width_left = 2
		s.border_width_right = 2
		s.border_width_top = 2
		s.border_width_bottom = 2
		s.border_color = Color(0.3, 1, 0.3)
	else:
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1
		s.border_color = Color(0.3, 0.3, 0.5)
	return s
