@tool
extends MarginContainer

signal insert_condition_requested(condition_node)
signal replace_condition_requested(condition_node)
signal delete_condition_requested(condition_node)
signal negate_condition_requested(condition_node)
signal edit_condition_requested(condition_node)

var condition_data: FKEventCondition
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
		# Make the Negate item checkable
		context_menu.set_item_as_checkable(4, true)
		context_menu.set_item_checked(4, condition_data.negated if condition_data else false)

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
		0: # Insert Condition Below
			insert_condition_requested.emit(self)
		1: # Replace Condition
			replace_condition_requested.emit(self)
		2: # Edit Condition
			edit_condition_requested.emit(self)
		3: # Delete Condition
			delete_condition_requested.emit(self)
		4: # Negate
			negate_condition_requested.emit(self)
			print("Negate condition requested for: ", condition_data.condition_id if condition_data else "unknown")

func set_condition_data(data: FKEventCondition) -> void:
	condition_data = data
	_update_label()

func set_registry(reg: Node) -> void:
	registry = reg
	_update_label()

func get_condition_data() -> FKEventCondition:
	"""Return the internal condition data."""
	return condition_data

func _update_label() -> void:
	if not label:
		label = get_node_or_null("Panel/MarginContainer/HBoxContainer/Label")
	
	if label and condition_data:
		var display_name = condition_data.condition_id
		
		# Try to get the provider's display name
		if registry:
			for provider in registry.condition_providers:
				if provider.has_method("get_id") and provider.get_id() == condition_data.condition_id:
					if provider.has_method("get_name"):
						display_name = provider.get_name()
					break
		
		var params_text = ""
		if not condition_data.inputs.is_empty():
			var param_pairs = []
			for key in condition_data.inputs:
				param_pairs.append("%s: %s" % [key, condition_data.inputs[key]])
			params_text = " (" + ", ".join(param_pairs) + ")"
		
		var negation_prefix = "NOT " if condition_data.negated else ""
		label.text = "%s%s%s" % [negation_prefix, display_name, params_text]
	
	# Update context menu checkmark
	if context_menu:
		context_menu.set_item_checked(4, condition_data.negated if condition_data else false)

func update_display() -> void:
	"""Refresh the label display."""
	_update_label()

func _get_drag_data(at_position: Vector2):
	# Create a simple preview control
	var preview_label := Label.new()
	preview_label.text = label.text if label else "Condition"
	preview_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85, 0.7))
	
	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 8)
	preview_margin.add_theme_constant_override("margin_top", 4)
	preview_margin.add_theme_constant_override("margin_right", 8)
	preview_margin.add_theme_constant_override("margin_bottom", 4)
	preview_margin.add_child(preview_label)
	
	set_drag_preview(preview_margin)
	
	# Return drag data with type information
	return {
		"type": "condition",
		"node": self
	}

func _can_drop_data(at_position: Vector2, data) -> bool:
	return false  # VBoxContainer handles drops

func _drop_data(at_position: Vector2, data) -> void:
	pass  # VBoxContainer handles drops
