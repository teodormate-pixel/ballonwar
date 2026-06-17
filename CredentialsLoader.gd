extends Node
class_name CredentialsLoader

func _ready() -> void:
	var file: FileAccess = FileAccess.open("user://credentials.dat", FileAccess.READ)
	if file:
		var base64_str: String = file.get_as_text()
		file.close()
		var credentials: Variant = Marshalls.base64_to_variant(base64_str)
		if credentials is Dictionary:
			var cred_dict: Dictionary = credentials
			var saved_text1: String = cred_dict.get("text1", "")
			var saved_text2: String = cred_dict.get("text2", "")
			if saved_text1 != "" and saved_text2 != "":
				await get_tree().process_frame
				database.login_rezultat.connect(func(succes: bool, _mesaj: String):
					if succes:
						print("[Auto-Login] Autentificare reușită.")
						var scena_curenta: String = get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
						if scena_curenta != "res://lume.tscn":
							print("[Auto-Login] Schimbăm scena spre Meniu.")
							get_tree().change_scene_to_file("res://Meniu.tscn")
						else:
							print("[Auto-Login] Suntem pe lume.tscn, nu redirecționăm.")
					else:
						print("[Auto-Login] Datele salvate nu mai sunt valide pe server.")
				, CONNECT_ONE_SHOT)
				database.logheaza_jucator(saved_text1, saved_text2)
				return
	queue_free.call_deferred()
