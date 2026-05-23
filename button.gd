extends Button

# Folosim get_parent() pentru a căuta căsuțele de text în aceeași scenă
@onready var input_username: LineEdit = get_parent().get_node("LineEdit")
@onready var input_password: LineEdit = get_parent().get_node("LineEdit2")

func _ready() -> void:
	# 1. Ne conectăm la semnalul global din database ca să știm când răspunde serverul
	if not database.login_rezultat.is_connected(_on_database_login_rezultat):
		database.login_rezultat.connect(_on_database_login_rezultat)
	
	# 2. Conectăm apăsarea acestui buton (self) la propria funcție de procesare
	if not self.pressed.is_connected(_on_self_pressed):
		self.pressed.connect(_on_self_pressed)


# Funcția care rulează când apeși pe acest buton
func _on_self_pressed() -> void:
	var nume = input_username.text.strip_edges()
	var parola = input_password.text.strip_edges()
	
	if nume == "" or parola == "":
		print("[Buton] Introdu un username și o parolă!")
		return
		
	print("[Buton] Se trimit datele... Dezactivăm butonul pentru a preveni dublu-click.")
	self.disabled = true # Dezactivăm butonul curent
	
	# Trimitem datele la Supabase
	database.salveaza_sau_inregistreaza(nume, parola)


# Funcția care rulează doar când serverul trimite răspunsul înapoi
func _on_database_login_rezultat(succes: bool, mesaj: String) -> void:
	# Reactivăm butonul imediat ce serverul a răspuns (indiferent dacă e succes sau eroare)
	self.disabled = false
	
	if succes:
		print("[Buton] Serverul a răspuns cu succes! Schimbăm scena.")
		get_tree().change_scene_to_file("res://Meniu.tscn")
	else:
		print("[Buton] Eroare de la server: ", mesaj)
