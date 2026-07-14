extends Node

var muzica_player: AudioStreamPlayer = null
var muzica_started: bool = false

const MUZICA_FUNDAL: String = "res://assets/images/assest/background_music.mp3"

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

func start_music() -> void:
	if muzica_started:
		return
	if not ResourceLoader.exists(MUZICA_FUNDAL):
		return
	var s = load(MUZICA_FUNDAL) as AudioStream
	if not s:
		return
	muzica_player = AudioStreamPlayer.new()
	muzica_player.stream = s
	muzica_player.volume_db = -12.0
	muzica_player.autoplay = true
	add_child(muzica_player)
	muzica_player.play()
	muzica_started = true

func stop_music() -> void:
	if muzica_player:
		muzica_player.stop()
	muzica_started = false
