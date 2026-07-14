extends Button

@onready var _NM = get_node("/root/NetworkManager")

func _ready() -> void:
	pressed.connect(_on_Button_pressed)
	_NM.delete_account_result.connect(_on_delete_result)

func _on_Button_pressed() -> void:
	if not _NM.is_logged_in():
		print("[Eroare] Nu ești logat.")
		return
	_NM.delete_account()

func _on_delete_result(success: bool, message: String) -> void:
	if success:
		print("[Succes] Contul a fost șters!")
		GlobalSettings.bani = 0
		get_tree().change_scene_to_file("res://scenes/menu/fundal_i_meniu_principal.tscn")
	else:
		print("[Eroare Server] ", message)
