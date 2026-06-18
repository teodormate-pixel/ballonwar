extends Control

@onready var _WC = get_node("/root/WorldConfig")

func _ready() -> void:
	_load_from_config()
	_setup_slider($VBox/FreqRow/FreqSlider, $VBox/FreqRow/FreqVal, 0.005, 0.05, 0.001)
	_setup_slider($VBox/HeightMinRow/HMinSlider, $VBox/HeightMinRow/HMinVal, 60, 200, 1)
	_setup_slider($VBox/HeightMaxRow/HMaxSlider, $VBox/HeightMaxRow/HMaxVal, 120, 500, 1)
	_setup_slider($VBox/WarpRow/WarpSlider, $VBox/WarpRow/WarpVal, 0.0, 15.0, 0.5)
	_setup_slider($VBox/CurveRow/CurveSlider, $VBox/CurveRow/CurveVal, 0.3, 1.0, 0.05)
	_setup_slider($VBox/RidgeRow/RidgeSlider, $VBox/RidgeRow/RidgeVal, 0.0, 1.5, 0.05)
	_setup_slider($VBox/BiomeRow/BiomeSlider, $VBox/BiomeRow/BiomeVal, 0.002, 0.02, 0.001)
	_setup_slider($VBox/TreeRow/TreeSlider, $VBox/TreeRow/TreeVal, 0.0, 3.0, 0.1)
	$VBox/SeedRow/RandomBtn.pressed.connect(_on_random_seed)
	$VBox/ButtonRow/StartBtn.pressed.connect(_on_start)
	$VBox/ButtonRow/StructBtn.pressed.connect(_on_structure_editor)
	$VBox/ButtonRow/BackBtn.pressed.connect(_on_back)

func _setup_slider(slider: HSlider, label: Label, min_v: float, max_v: float, step_v: float) -> void:
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value_changed.connect(func(v): label.text = str(v))

func _load_from_config() -> void:
	$VBox/SeedRow/SeedInput.text = str(_WC.world_seed)
	$VBox/FreqRow/FreqSlider.value = _WC.terrain_frequency
	$VBox/FreqRow/FreqVal.text = str(_WC.terrain_frequency)
	$VBox/HeightMinRow/HMinSlider.value = _WC.surface_min_height
	$VBox/HeightMinRow/HMinVal.text = str(_WC.surface_min_height)
	$VBox/HeightMaxRow/HMaxSlider.value = _WC.surface_max_height
	$VBox/HeightMaxRow/HMaxVal.text = str(_WC.surface_max_height)
	$VBox/WarpRow/WarpSlider.value = _WC.terrain_warp_strength
	$VBox/WarpRow/WarpVal.text = str(_WC.terrain_warp_strength)
	$VBox/CurveRow/CurveSlider.value = _WC.terrain_curve
	$VBox/CurveRow/CurveVal.text = str(_WC.terrain_curve)
	$VBox/RidgeRow/RidgeSlider.value = _WC.ridge_strength
	$VBox/RidgeRow/RidgeVal.text = str(_WC.ridge_strength)
	$VBox/BiomeRow/BiomeSlider.value = _WC.biome_frequency
	$VBox/BiomeRow/BiomeVal.text = str(_WC.biome_frequency)
	$VBox/TreeRow/TreeSlider.value = _WC.tree_density
	$VBox/TreeRow/TreeVal.text = str(_WC.tree_density)

func _save_to_config() -> void:
	_WC.world_seed = int($VBox/SeedRow/SeedInput.text) if $VBox/SeedRow/SeedInput.text.is_valid_int() else randi()
	_WC.terrain_frequency = $VBox/FreqRow/FreqSlider.value
	_WC.surface_min_height = int($VBox/HeightMinRow/HMinSlider.value)
	_WC.surface_max_height = int($VBox/HeightMaxRow/HMaxSlider.value)
	_WC.terrain_warp_strength = $VBox/WarpRow/WarpSlider.value
	_WC.terrain_curve = $VBox/CurveRow/CurveSlider.value
	_WC.ridge_strength = $VBox/RidgeRow/RidgeSlider.value
	_WC.biome_frequency = $VBox/BiomeRow/BiomeSlider.value
	_WC.tree_density = $VBox/TreeRow/TreeSlider.value

func _on_random_seed() -> void:
	$VBox/SeedRow/SeedInput.text = str(randi())

func _on_start() -> void:
	_save_to_config()
	get_tree().change_scene_to_file("res://lume.tscn")

func _on_structure_editor() -> void:
	get_tree().change_scene_to_file("res://StructureEditor.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://Meniu.tscn")
