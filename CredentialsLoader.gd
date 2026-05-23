extends Node
class_name CredentialsLoader

func _ready() -> void:
	# Încarcă credentialele din fișier și realizează logarea automată
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
				
				# Îi oferim lui Godot un moment să încarce tot arborele global
				await get_tree().process_frame
				
				# Conectăm semnalul în mod securizat înainte de pornire
				database.login_rezultat.connect(func(succes: bool, _mesaj: String):
					if succes:
						print("[Auto-Login] Autentificare reușită, schimbăm scena spre Meniu.")
						get_tree().change_scene_to_file("res://Meniu.tscn")
					else:
						print("[Auto-Login] Datele salvate nu mai sunt valide pe server.")
				, CONNECT_ONE_SHOT)
				
				# Lansăm funcția din scriptul global (Autoload)
				database.logheaza_jucator(saved_text1, saved_text2)
				return 
				
	# Eliberăm nodul curent în siguranță dacă nu avem fișier de logare
	queue_free.call_deferred()
