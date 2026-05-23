extends Node

# Semnale globale pentru comunicarea cu restul scripturilor din joc
signal date_incarcate_primite(date: Dictionary)
signal login_rezultat(succes: bool, mesaj: String)
signal stergere_rezultat(succes: bool, mesaj: String)

# ADRESA PROIECTULUI TĂU
var supabase_url: String = "https://vqcfxbaxzxqubzfwqupy.supabase.co"
# Cheia ta secretă adăugată corect
var supabase_cheie: String = "sb_secret_cLGlpoQoidPwL-VHjiYRnQ_KoqO83tG"

# VARIABILE GLOBALE STOCATE LA LOGIN (Accesibile din orice scenă)
var id_jucator_logat: Variant = null
var nume_jucator_logat: String = ""

func _ready() -> void:
	print("[Supabase Cloud] Managerul de conturi și progres este activ.")


# --- UTILITARE LOCALE (Salvare / Ștergere Fișier Credențiale) ---
func salveaza_credentiale_local(nume: String, pas: String) -> void:
	var file = FileAccess.open("user://credentials.dat", FileAccess.WRITE)
	if file:
		var cred_dict = {
			"text1": nume,
			"text2": pas
		}
		var base64_str: String = Marshalls.variant_to_base64(cred_dict)
		file.store_string(base64_str)
		file.close()
		print("[Local Storage] Datele de logare au fost salvate local în credentials.dat.")

func sterge_credentiale_local() -> void:
	if DirAccess.remove_absolute("user://credentials.dat") == OK:
		print("[Local Storage] Fișierul credentials.dat a fost șters de pe disc.")
	else:
		print("[Local Storage] Nu s-a putut șterge fișierul local sau nu exista.")


# --- 1. ÎNREGISTRARE / SALVARE (Trimite Username, Parolă și Progresul JSON) ---
func salveaza_sau_inregistreaza(nume: String, pas: String, progres_complex: Dictionary = {}) -> void:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.set_max_redirects(5)
	
	# Prevenire Cod 0
	await get_tree().process_frame
	
	http_request.request_completed.connect(func(_result, response_code, _headers, _body):
		if response_code >= 200 and response_code < 300:
			print("[Supabase] Înregistrare/Salvare reușită pentru '" + nume + "'. Executăm logarea automată...")
			# După înregistrare, îl logăm automat pentru a salva ID-ul și fișierul local
			logheaza_jucator(nume, pas)
		else:
			print("[Supabase] Eroare la salvare/înregistrare. Cod HTTP: ", response_code)
			login_rezultat.emit(false, "Eroare la salvare. Cod: " + str(response_code))
		http_request.queue_free()
	)
	
	var date_pachet = {
		"username": nume.strip_edges(),
		"password": pas,
		"date_salvare": progres_complex
	}
	
	var json_data = JSON.stringify(date_pachet)
	var headers = [
		"Content-Type: application/json",
		"apikey: " + supabase_cheie,
		"Authorization: Bearer " + supabase_cheie,
		"Prefer: resolution=merge-duplicates"
	]
	
	var url = supabase_url + "/rest/v1/progres_jucatori"
	http_request.request(url, headers, HTTPClient.METHOD_POST, json_data)


# --- 2. AUTENTIFICARE / ÎNCĂRCARE (Verifică datele și creează fișierul local la succes) ---
func logheaza_jucator(nume: String, pas: String) -> void:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.set_max_redirects(5)
	
	# Prevenire Cod 0
	await get_tree().process_frame
	
	http_request.request_completed.connect(func(_result, response_code, _headers, body):
		print("[Supabase Debug] Cod HTTP primit la Logare: ", response_code)
		
		if response_code == 200:
			var json = JSON.new()
			var parse_error = json.parse(body.get_string_from_utf8())
			
			if parse_error == OK:
				var date_baza = json.get_data()
				
				if date_baza is Array and date_baza.size() > 0:
					var cont_jucator = date_baza[0] # Extragem primul rând găsit
					
					if cont_jucator.has("password") and cont_jucator["password"] == pas:
						# Salvare date în memoria globală Autoload
						if cont_jucator.has("id"):
							id_jucator_logat = int(cont_jucator["id"]) # Prevenire Cod 400
						
						if cont_jucator.has("username"):
							nume_jucator_logat = str(cont_jucator["username"])
						
						# SALVARE LOCALĂ FIȘIER: Se execută doar acum, când datele sunt validate de server
						salveaza_credentiale_local(nume_jucator_logat, pas)
						
						print("[Supabase Success] Date stocate permanent în memorie. Nume: ", nume_jucator_logat)
						login_rezultat.emit(true, "Autentificare reușită!")
						
						if cont_jucator.has("date_salvare") and cont_jucator["date_salvare"] is Dictionary:
							date_incarcate_primite.emit(cont_jucator["date_salvare"])
						else:
							date_incarcate_primite.emit({})
						
						http_request.queue_free()
						return
					else:
						print("[Supabase] Parolă incorectă!")
						login_rezultat.emit(false, "Parolă incorectă!")
				else:
					print("[Supabase] Utilizatorul nu există!")
					login_rezultat.emit(false, "Utilizatorul nu a fost găsit!")
			else:
				print("[Supabase] Eroare decodare JSON.")
				login_rezultat.emit(false, "Eroare la procesarea datelor.")
		else:
			print("[Supabase] Eroare conexiune server. Cod: ", response_code)
			login_rezultat.emit(false, "Eroare rețea. Cod: " + str(response_code))
			
		http_request.queue_free()
	)
	
	var headers = [
		"apikey: " + supabase_cheie,
		"Authorization: Bearer " + supabase_cheie
	]
	
	var url = supabase_url + "/rest/v1/progres_jucatori?username=ilike." + nume.strip_edges().uri_encode()
	http_request.request(url, headers, HTTPClient.METHOD_GET)


# --- 3. ȘTERGERE CONT (Șterge rândul de pe server și curăță fișierul de pe hard disk) ---
func sterge_jucator_curent() -> void:
	if id_jucator_logat == null:
		print("[Supabase Eroare] Nu se poate șterge! Niciun jucător nu este logat.")
		stergere_rezultat.emit(false, "Trebuie să fii logat pentru a-ți șterge contul.")
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.set_max_redirects(5)
	
	# Prevenire Cod 0
	await get_tree().process_frame
	
	http_request.request_completed.connect(func(_result, response_code, _headers, body):
		var raspuns_text = body.get_string_from_utf8()
		print("[Supabase Debug] Serverul a răspuns la ștergere cu Cod HTTP: ", response_code)
		
		if response_code == 200 or response_code == 204:
			print("[Supabase] Contul cu ID-ul ", id_jucator_logat, " a fost șters din baza de date.")
			
			# ȘTERGERE LOCALĂ FIȘIER: Înlăturăm credențialele salvate de pe PC
			sterge_credentiale_local()
			
			stergere_rezultat.emit(true, "Cont șters cu succes!")
			
			# Resetăm variabilele
			id_jucator_logat = null 
			nume_jucator_logat = ""
		else:
			print("[Supabase Eroare] Nu s-a putut șterge. Cod: ", response_code, " Răspuns: ", raspuns_text)
			stergere_rezultat.emit(false, "Eroare server la ștergere.")
			
		http_request.queue_free()
	)
	
	var headers = [
		"apikey: " + supabase_cheie,
		"Authorization: Bearer " + supabase_cheie
	]
	
	var id_curat: int = int(id_jucator_logat)
	var url = supabase_url + "/rest/v1/progres_jucatori?id=eq." + str(id_curat)
	print("[Supabase] Se trimite cerere DELETE la URL: ", url)
	
	http_request.request(url, headers, HTTPClient.METHOD_DELETE)
