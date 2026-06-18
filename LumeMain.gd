extends Node3D

@onready var _NM = get_node("/root/NetworkManager")
@onready var _GJ = get_node("/root/GestiuneJoc")

const REMOTE_PLAYER = preload("res://RemotePlayer.tscn")


func _ready() -> void:
	_GJ.initializare(self)
	var spawner = get_node_or_null("MultiplayerSpawner")
	if spawner and (_NM == null or _NM.peer == null):
		spawner.queue_free()

	call_deferred("_on_peer_change")

	if _NM and _NM.peer != null:
		if not multiplayer.peer_connected.is_connected(_spawn_player):
			multiplayer.peer_connected.connect(_spawn_player)
		if not multiplayer.peer_disconnected.is_connected(_remove_player):
			multiplayer.peer_disconnected.connect(_remove_player)
		get_tree().create_timer(0.5).timeout.connect(_on_peer_change)


func _spawn_player(peer_id: int) -> void:
	var players = get_node_or_null("Players")
	if not players:
		return
	var key = str(peer_id)
	if players.get_node_or_null(key):
		return
	var p = REMOTE_PLAYER.instantiate()
	p.name = key
	p.set_multiplayer_authority(peer_id)
	players.add_child(p)


func _remove_player(peer_id: int) -> void:
	var players = get_node_or_null("Players")
	if not players:
		return
	var p = players.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()


func _on_peer_change() -> void:
	if _NM == null or _NM.peer == null:
		return
	if multiplayer.multiplayer_peer == null:
		return
	var players = get_node_or_null("Players")
	if not players:
		return
	for peer_id in multiplayer.get_peers():
		var key = str(peer_id)
		if players.get_node_or_null(key):
			continue
		var p = REMOTE_PLAYER.instantiate()
		p.name = key
		p.set_multiplayer_authority(peer_id)
		players.add_child(p)
