extends Control
class_name Inventar

signal block_selected(selected_block: int)

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON, COPPER, GOLD, DIAMOND, WOOD, LEAF }

const BLOCK_NAMES: Dictionary = {
	BlockType.GRASS: "Grass", BlockType.DIRT: "Dirt", BlockType.STONE: "Stone",
	BlockType.COAL: "Coal", BlockType.IRON: "Iron", BlockType.COPPER: "Copper",
	BlockType.GOLD: "Gold", BlockType.DIAMOND: "Diamond", BlockType.WOOD: "Wood", BlockType.LEAF: "Leaf"
}

const BLOCK_COLORS: Dictionary = {
	BlockType.GRASS: Color(0.28, 0.70, 0.24), BlockType.DIRT: Color(0.58, 0.40, 0.24),
	BlockType.STONE: Color(0.52, 0.52, 0.52), BlockType.COAL: Color(0.15, 0.15, 0.15),
	BlockType.IRON: Color(0.70, 0.55, 0.35), BlockType.COPPER: Color(0.85, 0.50, 0.25),
	BlockType.GOLD: Color(0.85, 0.72, 0.15), BlockType.DIAMOND: Color(0.20, 0.60, 0.80),
	BlockType.WOOD: Color(0.50, 0.30, 0.15), BlockType.LEAF: Color(0.15, 0.55, 0.15)
}

const BLOCK_ORDER: Array = [
	BlockType.GRASS, BlockType.DIRT, BlockType.STONE, BlockType.COAL, BlockType.IRON,
	BlockType.COPPER, BlockType.GOLD, BlockType.DIAMOND, BlockType.WOOD, BlockType.LEAF
]

const RECIPES: Array = [
	{"name": "Grass", "ingredients": {BlockType.DIRT: 4}, "result_type": BlockType.GRASS, "result_amount": 1},
	{"name": "Charcoal", "ingredients": {BlockType.WOOD: 2}, "result_type": BlockType.COAL, "result_amount": 1},
	{"name": "Iron", "ingredients": {BlockType.STONE: 2, BlockType.COAL: 2}, "result_type": BlockType.IRON, "result_amount": 1},
	{"name": "Gold", "ingredients": {BlockType.IRON: 2, BlockType.COAL: 2}, "result_type": BlockType.GOLD, "result_amount": 1},
]

var inventory: Dictionary = {
	BlockType.GRASS: 64, BlockType.DIRT: 64, BlockType.STONE: 32,
	BlockType.COAL: 0, BlockType.IRON: 0, BlockType.COPPER: 0,
	BlockType.GOLD: 0, BlockType.DIAMOND: 0, BlockType.WOOD: 0, BlockType.LEAF: 0
}

var selected_index: int = 0
var slot_nodes: Array = []
var bg_panel: Panel = null

var inventory_open: bool = false
var inv_overlay: ColorRect = null
var inv_panel: Panel = null
var inv_slots: Array = []
var armor_slots: Array = []
var craft_buttons: Array = []

func _ready() -> void:
	visible = true
	_build_hotbar()
	_build_inventory_screen()
	inventory_open = false
	inv_panel.visible = false
	inv_overlay.visible = false
	_update_ui()

func _build_hotbar() -> void:
	bg_panel = Panel.new()
	bg_panel.name = "Bg"
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.16, 0.80)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 8
	bg_style.content_margin_bottom = 8
	bg_style.border_color = Color(0.3, 0.3, 0.35, 0.6)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var hbox = HBoxContainer.new()
	hbox.name = "Slots"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 4)
	bg_panel.add_child(hbox)

	for i in BLOCK_ORDER.size():
		var bt = BLOCK_ORDER[i]
		var slot = _create_slot(bt, false)
		hbox.add_child(slot)
		slot_nodes.append(slot)

	call_deferred("_position_hotbar")
	resized.connect(_position_hotbar)

func _create_slot(block_type: int, in_inventory: bool) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(50, 54) if not in_inventory else Vector2(46, 50)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_color = Color(0.25, 0.25, 0.3, 0.3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	slot.add_child(vbox)

	var icon = ColorRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(32, 32) if not in_inventory else Vector2(28, 28)
	icon.color = BLOCK_COLORS.get(block_type, Color.WHITE)
	vbox.add_child(icon)

	var count_label = Label.new()
	count_label.name = "Count"
	count_label.text = "0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	count_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(count_label)

	return slot

func _build_inventory_screen() -> void:
	inv_overlay = ColorRect.new()
	inv_overlay.name = "InvOverlay"
	inv_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	inv_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	inv_overlay.anchor_left = 0
	inv_overlay.anchor_top = 0
	inv_overlay.anchor_right = 1
	inv_overlay.anchor_bottom = 1
	add_child(inv_overlay)

	inv_panel = Panel.new()
	inv_panel.name = "InvPanel"
	inv_panel.custom_minimum_size = Vector2(540, 380)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.14, 0.14, 0.18, 0.92)
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	pstyle.border_color = Color(0.3, 0.3, 0.35, 0.7)
	pstyle.border_width_left = 2
	pstyle.border_width_right = 2
	pstyle.border_width_top = 2
	pstyle.border_width_bottom = 2
	pstyle.content_margin_left = 16
	pstyle.content_margin_right = 16
	pstyle.content_margin_top = 16
	pstyle.content_margin_bottom = 16
	inv_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(inv_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainLayout"
	main_vbox.add_theme_constant_override("separation", 12)
	inv_panel.add_child(main_vbox)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 24)
	main_vbox.add_child(top_row)

	var armor_vbox = VBoxContainer.new()
	armor_vbox.add_theme_constant_override("separation", 4)
	var armor_title = Label.new()
	armor_title.text = "Armor"
	armor_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	armor_title.add_theme_font_size_override("font_size", 10)
	armor_vbox.add_child(armor_title)
	for a in 4:
		var aslot = Panel.new()
		aslot.custom_minimum_size = Vector2(40, 40)
		var ast = StyleBoxFlat.new()
		ast.bg_color = Color(0.2, 0.2, 0.25, 0.9)
		ast.corner_radius_top_left = 4
		ast.corner_radius_top_right = 4
		ast.corner_radius_bottom_left = 4
		ast.corner_radius_bottom_right = 4
		ast.border_color = Color(0.3, 0.3, 0.35, 0.3)
		ast.border_width_left = 1
		ast.border_width_right = 1
		ast.border_width_top = 1
		ast.border_width_bottom = 1
		aslot.add_theme_stylebox_override("panel", ast)
		armor_vbox.add_child(aslot)
		armor_slots.append(aslot)
	top_row.add_child(armor_vbox)

	var stats_vbox = VBoxContainer.new()
	stats_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_vbox.add_theme_constant_override("separation", 4)
	var stats_title = Label.new()
	stats_title.text = "Player"
	stats_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stats_title.add_theme_font_size_override("font_size", 10)
	stats_vbox.add_child(stats_title)
	var hp_icon = ColorRect.new()
	hp_icon.custom_minimum_size = Vector2(80, 8)
	hp_icon.color = Color(0.3, 0.05, 0.05)
	var hp_fill = ColorRect.new()
	hp_fill.custom_minimum_size = Vector2(60, 8)
	hp_fill.color = Color(0.9, 0.15, 0.15)
	hp_fill.position = Vector2(0, 0)
	hp_icon.add_child(hp_fill)
	stats_vbox.add_child(hp_icon)
	var hp_label = Label.new()
	hp_label.text = "100 HP"
	hp_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hp_label.add_theme_font_size_override("font_size", 10)
	stats_vbox.add_child(hp_label)
	top_row.add_child(stats_vbox)

	var crafting_vbox = VBoxContainer.new()
	crafting_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	crafting_vbox.add_theme_constant_override("separation", 6)
	var craft_title = Label.new()
	craft_title.text = "Recipes"
	craft_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	craft_title.add_theme_font_size_override("font_size", 10)
	crafting_vbox.add_child(craft_title)

	for ri in RECIPES.size():
		var recipe = RECIPES[ri]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var ings = recipe["ingredients"]
		for bt in ings:
			var ing_box = VBoxContainer.new()
			ing_box.alignment = BoxContainer.ALIGNMENT_CENTER
			ing_box.add_theme_constant_override("separation", 1)
			var rect = ColorRect.new()
			rect.custom_minimum_size = Vector2(18, 18)
			rect.color = BLOCK_COLORS.get(bt, Color.WHITE)
			ing_box.add_child(rect)
			var amt = Label.new()
			amt.text = str(ings[bt])
			amt.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			amt.add_theme_font_size_override("font_size", 9)
			amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ing_box.add_child(amt)
			row.add_child(ing_box)

		var arrow = Label.new()
		arrow.text = "→"
		arrow.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		arrow.add_theme_font_size_override("font_size", 14)
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(arrow)

		var res_box = VBoxContainer.new()
		res_box.alignment = BoxContainer.ALIGNMENT_CENTER
		res_box.add_theme_constant_override("separation", 1)
		var res_rect = ColorRect.new()
		res_rect.custom_minimum_size = Vector2(22, 22)
		res_rect.color = BLOCK_COLORS.get(recipe["result_type"], Color.WHITE)
		res_box.add_child(res_rect)
		var res_amt = Label.new()
		res_amt.text = "x" + str(recipe["result_amount"])
		res_amt.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		res_amt.add_theme_font_size_override("font_size", 9)
		res_amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		res_box.add_child(res_amt)
		row.add_child(res_box)

		var btn = Button.new()
		btn.text = "Craft"
		btn.name = "CraftBtn" + str(ri)
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(50, 24)
		var bst = StyleBoxFlat.new()
		bst.bg_color = Color(0.25, 0.55, 0.25, 0.8)
		bst.corner_radius_top_left = 4
		bst.corner_radius_top_right = 4
		bst.corner_radius_bottom_left = 4
		bst.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", bst)
		btn.pressed.connect(_craft.bind(ri))
		row.add_child(btn)
		craft_buttons.append(btn)

		crafting_vbox.add_child(row)

	top_row.add_child(crafting_vbox)

	var separator = ColorRect.new()
	separator.custom_minimum_size = Vector2(0, 1)
	separator.color = Color(0.3, 0.3, 0.35, 0.5)
	main_vbox.add_child(separator)

	var grid_title = HBoxContainer.new()
	var grid_label = Label.new()
	grid_label.text = "Inventory"
	grid_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	grid_label.add_theme_font_size_override("font_size", 11)
	grid_title.add_child(grid_label)
	grid_title.add_spacer(true)
	var close_hint = Label.new()
	close_hint.text = "[I / ESC]"
	close_hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	close_hint.add_theme_font_size_override("font_size", 9)
	grid_title.add_child(close_hint)
	main_vbox.add_child(grid_title)

	var inv_grid = GridContainer.new()
	inv_grid.name = "ItemGrid"
	inv_grid.columns = 5
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	for i in BLOCK_ORDER.size():
		var bt = BLOCK_ORDER[i]
		var slot = _create_slot(bt, true)
		inv_grid.add_child(slot)
		inv_slots.append(slot)
	main_vbox.add_child(inv_grid)

	var inv_hotbar_label = Label.new()
	inv_hotbar_label.text = "Hotbar"
	inv_hotbar_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	inv_hotbar_label.add_theme_font_size_override("font_size", 9)
	main_vbox.add_child(inv_hotbar_label)

	var inv_hotbar_hbox = HBoxContainer.new()
	inv_hotbar_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_hotbar_hbox.add_theme_constant_override("separation", 3)
	for i in BLOCK_ORDER.size():
		var bt = BLOCK_ORDER[i]
		var slot = _create_slot(bt, false)
		inv_hotbar_hbox.add_child(slot)
	main_vbox.add_child(inv_hotbar_hbox)

func _position_hotbar() -> void:
	if not bg_panel or not get_parent():
		return
	var parent_size = get_parent().size
	var bg_size = bg_panel.size
	if bg_size == Vector2.ZERO:
		bg_size = Vector2(50 * BLOCK_ORDER.size() + 4 * (BLOCK_ORDER.size() - 1) + 16, 72)
	bg_panel.position = Vector2(
		(parent_size.x - bg_size.x) / 2,
		parent_size.y - bg_size.y - 12
	)

func _position_inventory() -> void:
	if not inv_panel or not get_parent():
		return
	var parent_size = get_parent().size
	var psize = inv_panel.size
	if psize == Vector2.ZERO:
		psize = inv_panel.custom_minimum_size
	inv_panel.position = Vector2(
		(parent_size.x - psize.x) / 2,
		(parent_size.y - psize.y) / 2 - 20
	)

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

func has_blocks(block_type: int, amount: int) -> bool:
	return inventory.get(block_type, 0) >= amount

func try_use_block_type(block_type: int) -> bool:
	if not has_block(block_type):
		return false
	inventory[block_type] -= 1
	_update_ui()
	return true

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

func toggle_inventory() -> void:
	inventory_open = not inventory_open
	inv_overlay.visible = inventory_open
	inv_panel.visible = inventory_open
	if inventory_open:
		call_deferred("_position_inventory")

func _update_slot_visual(slot: Panel, i: int, use_highlight: bool) -> void:
	if slot == null:
		return
	var bt: int = BLOCK_ORDER[i] if i < BLOCK_ORDER.size() else 0
	var count: int = inventory.get(bt, 0)
	var vbox: VBoxContainer = slot.get_child(0) if slot.get_child_count() > 0 else null
	if vbox != null:
		var icon = vbox.get_child(0) if vbox.get_child_count() > 0 else null
		if icon is ColorRect:
			icon.color = BLOCK_COLORS.get(bt, Color.WHITE)
			icon.visible = count > 0
		var clabel = vbox.get_child(1) if vbox.get_child_count() > 1 else null
		if clabel is Label:
			if count > 0:
				clabel.text = str(count)
			else:
				clabel.text = ""

	var style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	if use_highlight and i == selected_index:
		style.border_color = Color(1, 1, 1, 0.9)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
	else:
		style.border_color = Color(0.25, 0.25, 0.3, 0.3)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1

func _update_ui() -> void:
	for i in slot_nodes.size():
		_update_slot_visual(slot_nodes[i], i, true)
	for i in inv_slots.size():
		_update_slot_visual(inv_slots[i], i, false)

func _craft(recipe_index: int) -> void:
	if recipe_index < 0 or recipe_index >= RECIPES.size():
		return
	var recipe = RECIPES[recipe_index]
	var ingredients = recipe["ingredients"]
	for bt in ingredients:
		if inventory.get(bt, 0) < ingredients[bt]:
			return
	for bt in ingredients:
		inventory[bt] -= ingredients[bt]
	inventory[recipe["result_type"]] = inventory.get(recipe["result_type"], 0) + recipe["result_amount"]
	_update_ui()

func _input(event: InputEvent) -> void:
	if not inventory_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

func get_block_name(block_type: int) -> String:
	return BLOCK_NAMES.get(block_type, "Unknown")

func get_block_color(block_type: int) -> Color:
	return BLOCK_COLORS.get(block_type, Color.WHITE)
