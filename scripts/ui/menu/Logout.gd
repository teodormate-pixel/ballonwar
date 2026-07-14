extends Button

const CREDENTIALS_FILE = "user://credentials.dat"

func _ready() -> void:
	# Sintaxă curată de Godot 4 pentru conectarea butonului
	pressed.connect(_on_Button_pressed)

func _on_Button_pressed() -> void:
	# Verificăm dacă fișierul există local
	if FileAccess.file_exists(CREDENTIALS_FILE):
		# CORECTURĂ GODOT 4: Se folosește DirAccess.remove_absolute pentru ștergere directă
		var eroare = DirAccess.remove_absolute(CREDENTIALS_FILE)
		
		if eroare == OK:
			print("[Log Out] Fișierul de credențiale a fost șters cu succes.")
		else:
			print("[Eroare Log Out] Nu s-a putut șterge fișierul. Cod eroare: ", eroare)
	else:
		print("[Log Out] Nu s-a găsit niciun fișier de credențiale salvat.")
	
	# PASUL IMPORTANT: Resetăm datele din sesiunea curentă ca jucătorul să nu mai aibă banii vechi
	GlobalSettings.bani = 0
	print("[Sistem] Datele din GlobalSettings au fost resetate la 0.")
	
	# Trimitem jucătorul înapoi la scena de autentificare (înlocuiește cu calea exactă a scenei tale de Login)
	var tree: SceneTree = get_tree()
	
	tree.change_scene_to_file("res://scenes/menu/fundal_i_meniu_principal.tscn") 
	
