extends Button

const CREDENTIALS_FILE = "user://credentials.dat"

func _ready() -> void:
	pressed.connect(_on_Button_pressed)
	database.stergere_rezultat.connect(_pe_rezultat_stergere)

func _on_Button_pressed() -> void:
	print("[Sistem] Inițiere proces ștergere definitivă...")
	
	if FileAccess.file_exists(CREDENTIALS_FILE):
		var file = FileAccess.open(CREDENTIALS_FILE, FileAccess.READ)
		if file:
			var base64_str = file.get_as_text()
			file.close()
			
			var cred_dict = Marshalls.base64_to_variant(base64_str)
			# Curățăm textul (.strip_edges()) pentru a elimina spațiile goale care blochează Supabase
			if cred_dict is Dictionary and cred_dict.has("text1"):
				var nume_utilizator = str(cred_dict["text1"]).strip_edges()
				var parola = str(cred_dict["text2"]).strip_edges()
				if nume_utilizator != "":
					print("[Sistem] Se trimite comanda DELETE către Cloud pentru utilizatorul: '" + nume_utilizator + "'")
					database.sterge_jucator_curent()
					return
				
	print("[Eroare] Datele locale sunt corupte sau inexistente. Ștergerea nu a putut fi trimisă.")

func _pe_rezultat_stergere(succes: bool, mesaj: String) -> void:
	if succes:
		print("[Succes] Supabase a confirmat eliminarea contului!")
		
		# Curățăm fișierul local doar DUPĂ ce baza de date a fost ștearsă cu succes
		if FileAccess.file_exists(CREDENTIALS_FILE):
			DirAccess.remove_absolute(CREDENTIALS_FILE)
			print("[Sistem] Fișierul credentials.dat a fost șters local.")
			
		GlobalSettings.bani = 0
		
		var tree = Engine.get_main_loop() as SceneTree
		if tree:
			tree.change_scene_to_file("res://fundal_i_meniu_principal.tscn")
	else:
		print("[Eroare Server] Serverul a respins ștergerea: ", mesaj)
