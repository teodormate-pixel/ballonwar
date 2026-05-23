extends Label

func _ready() -> void:
	# Îi oferim lui Godot un cadru (frame) timp pentru a procesa corect ordinea variabilelor
	await get_tree().process_frame
	
	_afiseaza_text_curent()
	
	# Ne conectăm la semnal pentru modificări sau logări ulterioare
	if not database.login_rezultat.is_connected(_on_login_schimbat):
		database.login_rezultat.connect(_on_login_schimbat)

func _on_login_schimbat(succes: bool, _mesaj: String) -> void:
	if "%" in name or not is_inside_tree(): return # Protecție la schimbarea scenelor
	await get_tree().process_frame
	_afiseaza_text_curent()

func _afiseaza_text_curent() -> void:
	if database.nume_jucator_logat != "":
		self.text = "Username: " + database.nume_jucator_logat
	else:
		self.text = "Username: Nelogat"
