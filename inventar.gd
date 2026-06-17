extends Control
class_name Inventar

signal block_selected(selected_block: int)

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON, COPPER, GOLD, DIAMOND }

const BLOCK_ORDER: Array = [
	BlockType.GRASS,
	BlockType.DIRT,
	BlockType.STONE,
	BlockType.COAL,
	BlockType.IRON,
	BlockType.COPPER,
	BlockType.GOLD,
	BlockType.DIAMOND
]

var inventory: Dictionary = {
	BlockType.GRASS: 64,
	BlockType.DIRT: 64,
	BlockType.STONE: 32,
	BlockType.COAL: 0,
	BlockType.IRON: 0,
	BlockType.COPPER: 0,
	BlockType.GOLD: 0,
	BlockType.DIAMOND: 0
}

const BLOCK_COLORS: Dictionary = {
	BlockType.GRASS: Color(0.28, 0.70, 0.24),
	BlockType.DIRT: Color(0.58, 0.40, 0.24),
	BlockType.STONE: Color(0.52, 0.52, 0.52),
	BlockType.COAL: Color(0.15, 0.15, 0.15),
	BlockType.IRON: Color(0.70, 0.55, 0.35),
	BlockType.COPPER: Color(0.85, 0.50, 0.25),
	BlockType.GOLD: Color(0.85, 0.72, 0.15),
	BlockType.DIAMOND: Color(0.20, 0.60, 0.80)
}

var selected_index: int = 0
var slot_nodes: Array = []
var bg_panel: Panel = null

func _ready() -> void:
	visible = true
	_build_inventory_ui()
	_update_ui()
	call_deferred("_position_at_bottom")

func _build_inventory_ui() -> void:
	bg_panel = Panel.new()
	bg_panel.name = "Bg"
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.75)
	bg_style.corner_radius_top_left = 10
	bg_style.corner_radius_top_right = 10
	bg_style.corner_radius_bottom_left = 10
	bg_style.corner_radius_bottom_right = 10
	bg_style.content_margin_left = 6
	bg_style.content_margin_right = 6
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var hbox = HBoxContainer.new()
	hbox.name = "Slots"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 4)
	bg_panel.add_child(hbox)

	for i in BLOCK_ORDER.size():
		var bt = BLOCK_ORDER[i]
		var slot = _create_slot(bt, i)
		hbox.add_child(slot)
		slot_nodes.append(slot)

func _create_slot(block_type: int, index: int) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(52, 58)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	slot.add_child(vbox)

	var icon = ColorRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(36, 36)
	icon.color = BLOCK_COLORS.get(block_type, Color.WHITE)
	vbox.add_child(icon)

	var count_label = Label.new()
	count_label.name = "Count"
	count_label.text = "0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	count_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(count_label)

	return slot

func add_block(block_type: int, amount: int = 1) -> void:
	if not inventory.has(block_type):
		return
	inventory[block_type] += amount
	_update_ui()

func try_use_selected_block() -> bool:
	var bt: int = get_selected_block_type()
	if not has_block(bt):
		return false
	inventory[bt] -= 1
	_update_ui()
	return true

func has_block(block_type: int) -> bool:
	return inventory.has(block_type) and inventory[block_type] > 0

func get_selected_block_type() -> int:
	if selected_index < 0 or selected_index >= BLOCK_ORDER.size():
		return BLOCK_ORDER[0]
	return BLOCK_ORDER[selected_index]

func select_block_index(index: int) -> void:
	if index < 0 or index >= BLOCK_ORDER.size():
		return
	selected_index = index
	emit_signal("block_selected", get_selected_block_type())
	_update_ui()

func _update_ui() -> void:
	for i in slot_nodes.size():
		var slot = slot_nodes[i] as Panel
		if not slot:
			continue
		var bt = BLOCK_ORDER[i]
		var count = inventory.get(bt, 0)

		var vbox = slot.get_child(0) as VBoxContainer
		if vbox and vbox.get_child_count() > 1:
			var count_label = vbox.get_child(1) as Label
			if count_label:
				count_label.text = str(count) if count > 0 else ""

		var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
		if i == selected_index:
			style.border_color = Color(1, 1, 1, 0.9)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		else:
			style.border_color = Color(0, 0, 0, 0)
			style.border_width_left = 0
			style.border_width_right = 0
			style.border_width_top = 0
			style.border_width_bottom = 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_position_at_bottom()

func _position_at_bottom() -> void:
	if not bg_panel or not get_parent():
		return
	var parent_size = get_parent().size    
	var bg_size = bg_panel.size
	if bg_size == Vector2.ZERO:
		bg_size = Vector2(52 * BLOCK_ORDER.size() + 4 * (BLOCK_ORDER.size() - 1) + 12, 72)
	bg_panel.position = Vector2(
		(parent_size.x - bg_size.x) / 2,
		parent_size.y - bg_size.y - 12
	)

func get_block_name(block_type: int) -> String:
	match block_type:
		BlockType.GRASS: return "Grass"
		BlockType.DIRT: return "Dirt"
		BlockType.STONE: return "Stone"
		BlockType.COAL: return "Coal"
		BlockType.IRON: return "Iron"
		BlockType.COPPER: return "Copper"
		BlockType.GOLD: return "Gold"
		BlockType.DIAMOND: return "Diamond"
	return "Unknown"
