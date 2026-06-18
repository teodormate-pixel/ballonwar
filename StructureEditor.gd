extends Control

enum Tool { ADD, REMOVE, MOVE }

var tool_mode: int = Tool.ADD
var block_type_curent: int = 1
var blocks_editor: Dictionary = {}
var block_nodes: Dictionary = {}
var structura: StructureData = StructureData.new()
var selected_node: Node3D = null
var camera_rot_x: float = 0.0
var camera_rot_y: float = 0.0
var camera_dist: float = 8.0
var dragging: bool = false
var drag_origin: Vector2 = Vector2.ZERO
var palette_buttons: Array = []

const BLOCK_COLORS: Dictionary = {
	0: Color(0,0,0,0), 1: Color(0.28, 0.70, 0.24), 2: Color(0.58, 0.40, 0.24),
	3: Color(0.52, 0.52, 0.52), 4: Color(0.15, 0.15, 0.15), 5: Color(0.70, 0.55, 0.35),
	6: Color(0.85, 0.50, 0.25), 7: Color(0.85, 0.72, 0.15), 8: Color(0.20, 0.60, 0.80),
	9: Color(0.50, 0.30, 0.15), 10: Color(0.15, 0.55, 0.15)
}

const BLOCK_NAMES: Dictionary = {
	0: "Air", 1: "Grass", 2: "Dirt", 3: "Stone", 4: "Coal", 5: "Iron",
	6: "Copper", 7: "Gold", 8: "Diamond", 9: "Wood", 10: "Leaf"
}

@onready var viewport_container: SubViewportContainer = $ViewportContainer
@onready var viewport: SubViewport = $ViewportContainer/SubViewport
@onready var camera: Camera3D = $ViewportContainer/SubViewport/Camera3D
@onready var grid: Node3D = $ViewportContainer/SubViewport/Grid
@onready var blocks_root: Node3D = $ViewportContainer/SubViewport/Blocks
@onready var name_edit: LineEdit = $Panel/VBox/NameEdit
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var tool_add_btn: Button = $Panel/VBox/ToolBar/AddBtn
@onready var tool_remove_btn: Button = $Panel/VBox/ToolBar/RemoveBtn
@onready var palette_container: GridContainer = $Panel/VBox/Palette
@onready var save_btn: Button = $Panel/VBox/Actions/SaveBtn
@onready var load_btn: Button = $Panel/VBox/Actions/LoadBtn
@onready var clear_btn: Button = $Panel/VBox/Actions/ClearBtn

func _ready() -> void:
	_center_camera()
	_build_palette()
	_update_info()
	_apply_tool_style()
	tool_add_btn.connect("pressed", Callable(self, "_on_add_btn_pressed"))
	tool_remove_btn.connect("pressed", Callable(self, "_on_remove_btn_pressed"))
	name_edit.connect("text_changed", Callable(self, "_on_name_edit_text_changed"))
	save_btn.connect("pressed", Callable(self, "_on_save_btn_pressed"))
	load_btn.connect("pressed", Callable(self, "_on_load_btn_pressed"))
	clear_btn.connect("pressed", Callable(self, "_on_clear_btn_pressed"))

func _center_camera() -> void:
	camera.position = Vector3(0, 5, 8)
	camera.look_at(Vector3.ZERO)

func _build_palette() -> void:
	for bt in range(1, 12):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		var c = BLOCK_COLORS.get(bt, Color.WHITE)
		var style = StyleBoxFlat.new()
		style.bg_color = c
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)
		var label = Label.new()
		label.text = BLOCK_NAMES.get(bt, "")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(1,1,1))
		label.add_theme_font_size_override("font_size", 9)
		btn.add_child(label)
		btn.connect("pressed", Callable(self, "_select_palette_block").bind(bt))
		palette_container.add_child(btn)
		palette_buttons.append(btn)
	_select_palette_block(1)

func _select_palette_block(bt: int) -> void:
	block_type_curent = bt
	for i in palette_buttons.size():
		var btn = palette_buttons[i]
		var style = btn.get_theme_stylebox("normal") as StyleBoxFlat
		if (i + 1) == bt:
			style.border_color = Color(1, 1, 1)
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

func _input(event: InputEvent) -> void:
	if not viewport_container.get_global_rect().has_point(get_global_mouse_position()):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_ui_click(event):
			_handle_viewport_click(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = true
			drag_origin = get_global_mouse_position()
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event is InputEventMouseMotion and dragging:
		var delta = get_global_mouse_position() - drag_origin
		camera_rot_y -= delta.x * 0.01
		camera_rot_x = clamp(camera_rot_x - delta.y * 0.01, -1.5, 1.5)
		drag_origin = get_global_mouse_position()
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_dist = clamp(camera_dist - 0.5, 3.0, 20.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_dist = clamp(camera_dist + 0.5, 3.0, 20.0)
			_update_camera()

func _is_ui_click(event: InputEvent) -> bool:
	return event.position.y > get_viewport_rect().size.y * 0.65

func _handle_viewport_click(event: InputEvent) -> void:
	var space = viewport.world_3d.direct_space_state
	var cam = camera
	var from = cam.global_position
	var to = from - cam.global_transform.basis.z * 50.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result.is_empty():
		return
	var pos = Vector3(
		floor(result.position.x + result.normal.x * 0.5) + 0.5,
		floor(result.position.y + result.normal.y * 0.5) + 0.5,
		floor(result.position.z + result.normal.z * 0.5) + 0.5
	)
	if tool_mode == Tool.ADD:
		_add_block(pos.x, pos.y, pos.z, block_type_curent)
	elif tool_mode == Tool.REMOVE:
		_remove_block(pos.x, pos.y, pos.z)

func _add_block(x: float, y: float, z: float, bt: int) -> void:
	var key = str(Vector3(x, y, z))
	if key in blocks_editor:
		return
	blocks_editor[key] = {"x": x, "y": y, "z": z, "type": bt}
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(x, y, z)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = BLOCK_COLORS.get(bt, Color.WHITE)
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	mesh.add_child(body)
	blocks_root.add_child(mesh)
	block_nodes[key] = mesh
	_sync_structura()
	_update_info()

func _remove_block(x: float, y: float, z: float) -> void:
	var key = str(Vector3(x, y, z))
	if not key in blocks_editor:
		return
	blocks_editor.erase(key)
	if key in block_nodes:
		block_nodes[key].queue_free()
		block_nodes.erase(key)
	_sync_structura()
	_update_info()

func _sync_structura() -> void:
	structura.blocks = []
	for key in blocks_editor:
		structura.blocks.append(blocks_editor[key].duplicate())
	structura.structure_name = name_edit.text if name_edit.text.strip_edges() != "" else "Structure"

func _update_info() -> void:
	var count = blocks_editor.size()
	info_label.text = "Blocuri: " + str(count)

func _update_camera() -> void:
	var offset = Vector3(0, 0, camera_dist)
	var rot = Basis.from_euler(Vector3(camera_rot_x, camera_rot_y, 0))
	camera.position = rot * offset
	camera.look_at(Vector3.ZERO)

func _apply_tool_style() -> void:
	var add_style = StyleBoxFlat.new()
	var rem_style = StyleBoxFlat.new()
	add_style.bg_color = Color(0.2, 0.6, 0.2) if tool_mode == Tool.ADD else Color(0.3, 0.3, 0.3)
	rem_style.bg_color = Color(0.6, 0.2, 0.2) if tool_mode == Tool.REMOVE else Color(0.3, 0.3, 0.3)
	tool_add_btn.add_theme_stylebox_override("normal", add_style)
	tool_remove_btn.add_theme_stylebox_override("normal", rem_style)

func _on_add_btn_pressed() -> void:
	tool_mode = Tool.ADD
	_apply_tool_style()

func _on_remove_btn_pressed() -> void:
	tool_mode = Tool.REMOVE
	_apply_tool_style()

func _on_name_edit_text_changed(_new_text: String) -> void:
	_sync_structura()

func _on_clear_btn_pressed() -> void:
	for key in block_nodes:
		block_nodes[key].queue_free()
	block_nodes.clear()
	blocks_editor.clear()
	structura.blocks = []
	_update_info()

func _on_save_btn_pressed() -> void:
	_sync_structura()
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.json", "Structure Blueprint JSON")
	dialog.current_dir = "res://blueprints"
	dialog.current_file = structura.structure_name.replace(" ", "_") + ".json"
	dialog.file_selected.connect(_on_save_file_selected)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup()

func _on_save_file_selected(path: String) -> void:
	_sync_structura()
	if not path.ends_with(".json"):
		path += ".json"
	structura.save_to_file(path)

func _on_load_btn_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.json", "Structure Blueprint JSON")
	dialog.current_dir = "res://blueprints"
	dialog.file_selected.connect(_on_load_file_selected)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup()

func _on_load_file_selected(path: String) -> void:
	var loaded = StructureData.load_from_file(path)
	if loaded == null:
		return
	_on_clear_btn_pressed()
	structura = loaded
	name_edit.text = loaded.structure_name
	for bd in loaded.blocks:
		_add_block(bd.x, bd.y, bd.z, bd.type)
	_sync_structura()
