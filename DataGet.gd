extends Node

# VARIABILELE DIN JOC ÎN CARE SE VOR SALVA DATELE EXTRASE DIN CLOUD
var nivel: int = 1
var bani: int = 0
var inventar: Array = []

func _ready() -> void:
	# 1. Ascultăm semnalul global pentru date permanent (conectat o singură dată)
	database.date_incarcate_primite.connect(_pe_date_extrase_din_cloud)
	
	# 2. Ascultăm când se încarcă o scenă nouă în joc
	get_tree().root.child_entered_tree.connect(_on_scene_changed)

func _on_scene_changed(node: Node) -> void:
	# Așteptăm un cadru pentru a ne asigura că arborele de scene s-a actualizat corect
	await get_tree().process_frame
	
	# Verificăm dacă nodul nou încărcat este scena curentă și dacă este Meniul
	# NOTĂ: Înlocuiește "Meniu" cu numele exact al nodului rădăcină (Root Node) al scenei tale de meniu
	if node == get_tree().current_scene and node.name == "Meniu":
		print("[Extractor] Am detectat scena de Meniu. Pornim logarea...")
		executa_extragere_date()

func executa_extragere_date() -> void:
	# Pornim logarea și extragerea pentru contul testat de tine
	print("[Extractor] Cerem datele din cloud...")
	database.logheaza_jucator("Teo", "1234")

# FUNCȚIA CARE EXTRAGE PROPRIU-ZIS DATELE ÎN VARIABILE
func _pe_date_extrase_din_cloud(date_brute: Dictionary) -> void:
	print("[Extractor] Datele au sosit! Începe extragerea în variabile...")
	
	if date_brute.is_empty():
		print("[Extractor] Cloud-ul este gol pentru acest user. Variabilele rămân neschimbate.")
		return
	
	# Extragem datele din JSON-ul din cloud direct în variabilele noastre din Godot
	nivel = date_brute.get("nivel", 1)
	bani = date_brute.get("bani", 0)
	inventar = date_brute.get("inventar", [])
	
	# AFISĂM REZULTATUL ÎN CONSOLĂ PENTRU CONFIRMARE
	print("\n=== VARIABILE EXTRASE CU SUCCES ===")
	print("Nivelul extras: ", nivel)
	print("Banii extrași: ", bani)
	print("Inventarul extras: ", inventar)
	print("===================================\n")
