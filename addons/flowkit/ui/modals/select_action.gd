@tool
extends PopupPanel

signal action_selected(node_path: String, action_id: String, action_inputs: Array)

var selected_node_path: String = ""
var selected_node_class: String = ""
var available_actions: Array = []

@onready var item_list := $ItemList

func _ready() -> void:
	if item_list:
		item_list.item_activated.connect(_on_item_activated)
	
	# Load all available actions
	_load_available_actions()

func _load_available_actions() -> void:
	"""Load all action scripts from the actions folder."""
	available_actions.clear()
	var actions_path: String = "res://addons/flowkit/actions"
	_scan_directory_recursive(actions_path)
	print("Loaded ", available_actions.size(), " actions")

func _scan_directory_recursive(path: String) -> void:
	"""Recursively scan directories for action scripts."""
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		var full_path: String = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Recursively scan subdirectory
			_scan_directory_recursive(full_path)
		elif file_name.ends_with(".gd") and not file_name.ends_with(".gd.uid"):
			var action_script: GDScript = load(full_path)
			if action_script:
				var action_instance: Variant = action_script.new()
				available_actions.append(action_instance)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func populate_actions(node_path: String, node_class: String) -> void:
	"""Populate the list with actions compatible with the selected node."""
	selected_node_path = node_path
	selected_node_class = node_class
	
	if not item_list:
		return
	
	item_list.clear()
	
	# Filter actions that support this node type
	for action in available_actions:
		var supported_types = action.get_supported_types()
		if _is_node_compatible(node_class, supported_types):
			var action_name = action.get_name()
			var action_id = action.get_id()
			
			item_list.add_item(action_name)
			var index = item_list.item_count - 1
			item_list.set_item_metadata(index, {"id": action_id, "inputs": action.get_inputs()})
	
	if item_list.item_count == 0:
		item_list.add_item("No actions available for this node type")
		item_list.set_item_disabled(0, true)

func _is_node_compatible(node_class: String, supported_types: Array) -> bool:
	"""Check if a node class is compatible with the supported types."""
	if supported_types.is_empty():
		return false
	
	# Check for exact match
	if node_class in supported_types:
		return true
	
	# Check for "Node" which should match all nodes
	if "Node" in supported_types:
		return true
	
	# Check inheritance
	for supported_type in supported_types:
		if ClassDB.is_parent_class(node_class, supported_type):
			return true
	
	return false

func _on_item_activated(index: int) -> void:
	"""Handle action selection."""
	if item_list.is_item_disabled(index):
		return
	
	var metadata = item_list.get_item_metadata(index)
	var action_id = metadata["id"]
	var inputs = metadata["inputs"]
	
	print("Action selected: ", action_id, " for node: ", selected_node_path)
	action_selected.emit(selected_node_path, action_id, inputs)
	hide()
