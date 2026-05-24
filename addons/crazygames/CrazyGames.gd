extends Node

const version = "1.0.1"
var godot_version = Engine.get_version_info().string
var is_initialised: bool = false
var has_adblock: bool = false

var Game: GameModule = GameModule.new()
var User: UserModule = UserModule.new()
var Data: DataModule = DataModule.new()
var Ad: AdModule = AdModule.new()

func _ready():
	if not OS.has_feature("web"):
		is_initialised = true
		return
	call_deferred("_init_sdk")


func _init_sdk() -> void:
	CrazyGamesBridge.callbacks.sdk_initialized.connect(self._on_sdk_initialized)
	CrazyGamesBridge.init_sdk(version)
	has_adblock = await CrazyGamesBridge.callbacks.adblock_detection_result


func _on_sdk_initialized():
	is_initialised = true;
	
	
func is_initialised_async():
	while (is_initialised == false):
		await get_tree().process_frame
