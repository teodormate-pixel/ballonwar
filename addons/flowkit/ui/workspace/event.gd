@tool
extends MarginContainer

signal insert_condition_requested(event_node)
signal replace_event_requested(event_node)
signal delete_event_requested(event_node)
signal edit_event_requested(event_node)

var event_data: FKEventBlock
var registry: Node

var context_menu: PopupMenu
var label: Label

func _ready() -> void:
	label = get_node_or_null("Panel/MarginContainer/HBoxContainer/Label")
	
	# Connect gui_input for right-click detection
	gui_input.connect(_on_gui_input)
	
	# Try to get context menu and connect if available
	call_deferred("_setup_context_menu")

func _setup_context_menu() -> void:
	context_menu = get_node_or_null("ContextMenu")
	if context_menu:
		context_menu.id_pressed.connect(_on_context_menu_id_pressed)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Try to get context menu if we don't have it yet
			if not context_menu:
				context_menu = get_node_or_null("ContextMenu")
				if context_menu and not context_menu.id_pressed.is_connected(_on_context_menu_id_pressed):
					context_menu.id_pressed.connect(_on_context_menu_id_pressed)
			
			if context_menu:
				context_menu.position = get_global_mouse_position()
				context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Insert Condition
			insert_condition_requested.emit(self)
		1: # Replace Event
			replace_event_requested.emit(self)
		2: # Edit Event
			edit_event_requested.emit(self)
		3: # Delete Event
			delete_event_requested.emit(self)

func set_event_data(data: FKEventBlock) -> void:
	event_data = data
	_update_label()

func set_registry(reg: Node) -> void:
	registry = reg
	_update_label()

func get_event_data() -> FKEventBlock:
	"""Return the internal event data."""
	return event_data

func _update_label() -> void:
	if not label:
		label = get_node_or_null("Panel/MarginContainer/HBoxContainer/Label")
	
	if label and event_data:
		var display_name = event_data.event_id
		
		# Try to get the provider's display name
		if registry:
			for provider in registry.event_providers:
				if provider.has_method("get_id") and provider.get_id() == event_data.event_id:
					if provider.has_method("get_name"):
						display_name = provider.get_name()
					break
		
		var params_text = ""
		if not event_data.inputs.is_empty():
			var param_pairs = []
			for key in event_data.inputs:
				param_pairs.append("%s: %s" % [key, event_data.inputs[key]])
			params_text = " (" + ", ".join(param_pairs) + ")"
		
		var node_name = String(event_data.target_node).get_file()
		label.text = "%s on %s%s" % [display_name, node_name, params_text]

func update_display() -> void:
	"""Refresh the label display."""
	_update_label()

func _get_drag_data(at_position: Vector2):
	# Create a simple preview control
	var preview_label := Label.new()
	preview_label.text = label.text if label else "Event"
	preview_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9, 0.7))
	
	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 8)
	preview_margin.add_theme_constant_override("margin_top", 4)
	preview_margin.add_theme_constant_override("margin_right", 8)
	preview_margin.add_theme_constant_override("margin_bottom", 4)
	preview_margin.add_child(preview_label)
	
	set_drag_preview(preview_margin)
	
	# Return drag data with type information
	return {
		"type": "event",
		"node": self
	}

func _can_drop_data(at_position: Vector2, data) -> bool:
	return false  # VBoxContainer handles drops

func _drop_data(at_position: Vector2, data) -> void:
	pass  # VBoxContainer handles drops
