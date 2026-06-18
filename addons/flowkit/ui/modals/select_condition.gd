@tool
extends PopupPanel

signal condition_selected(node_path: String, condition_id: String, condition_inputs: Array)

var selected_node_path: String = ""
var selected_node_class: String = ""
var available_conditions: Array = []

@onready var item_list := $ItemList

func _ready() -> void:
	if item_list:
		item_list.item_activated.connect(_on_item_activated)
	
	# Load all available conditions
	_load_available_conditions()

func _load_available_conditions() -> void:
	"""Load all condition scripts from the conditions folder."""
	available_conditions.clear()
	var conditions_path: String = "res://addons/flowkit/conditions"
	_scan_directory_recursive(conditions_path)
	print("Loaded ", available_conditions.size(), " conditions")

func _scan_directory_recursive(path: String) -> void:
	"""Recursively scan directories for condition scripts."""
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
			var condition_script: GDScript = load(full_path)
			if condition_script:
				var condition_instance: Variant = condition_script.new()
				available_conditions.append(condition_instance)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func populate_conditions(node_path: String, node_class: String) -> void:
	"""Populate the list with conditions compatible with the selected node."""
	selected_node_path = node_path
	selected_node_class = node_class
	
	if not item_list:
		return
	
	item_list.clear()
	
	# Filter conditions that support this node type
	for condition in available_conditions:
		var supported_types = condition.get_supported_types()
		if _is_node_compatible(node_class, supported_types):
			var condition_name = condition.get_name()
			var condition_id = condition.get_id()
			
			item_list.add_item(condition_name)
			var index = item_list.item_count - 1
			item_list.set_item_metadata(index, {"id": condition_id, "inputs": condition.get_inputs()})
	
	if item_list.item_count == 0:
		item_list.add_item("No conditions available for this node type")
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
	"""Handle condition selection."""
	if item_list.is_item_disabled(index):
		return
	
	var metadata = item_list.get_item_metadata(index)
	var condition_id = metadata["id"]
	var inputs = metadata["inputs"]
	
	print("Condition selected: ", condition_id, " for node: ", selected_node_path)
	condition_selected.emit(selected_node_path, condition_id, inputs)
	hide()
