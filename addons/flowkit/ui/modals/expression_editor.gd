@tool
extends PopupPanel

signal expressions_confirmed(node_path: String, action_id: String, expressions: Dictionary)

var selected_node_path: String = ""
var selected_action_id: String = ""
var action_inputs: Array = []
var input_fields: Dictionary = {}

@onready var inputs_container := $MarginContainer/VBoxContainer/ScrollContainer/InputsContainer

func populate_inputs(node_path: String, action_id: String, inputs: Array, current_values: Dictionary = {}) -> void:
	"""Populate the expression editor with input fields for the action."""
	selected_node_path = node_path
	selected_action_id = action_id
	action_inputs = inputs
	
	if not inputs_container:
		return
	
	# Clear existing inputs
	for child in inputs_container.get_children():
		child.queue_free()
	
	input_fields.clear()
	
	# Create input fields for each parameter
	for input_data in inputs:
		var param_name: String = input_data.get("name", "Unknown")
		var param_type: String = input_data.get("type", "string")
		
		# Create label
		var label: Label = Label.new()
		label.text = param_name + " (" + param_type + "):"
		inputs_container.add_child(label)
		
		# Create input field
		var line_edit: LineEdit = LineEdit.new()
		line_edit.placeholder_text = "Enter expression (e.g., 100, 1+1, variable_name)"
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Set current value if editing
		if current_values.has(param_name):
			line_edit.text = str(current_values[param_name])
		
		inputs_container.add_child(line_edit)
		
		input_fields[param_name] = line_edit
		
		# Add spacing
		var spacer: Control = Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		inputs_container.add_child(spacer)

func _on_confirm_button_pressed() -> void:
	"""Collect all expressions and emit signal."""
	var expressions: Dictionary = {}
	
	for param_name in input_fields:
		var line_edit = input_fields[param_name]
		expressions[param_name] = line_edit.text
	
	print("Expressions confirmed: ", expressions)
	expressions_confirmed.emit(selected_node_path, selected_action_id, expressions)
	hide()

func _on_cancel_button_pressed() -> void:
	"""Cancel and close the editor."""
	hide()
