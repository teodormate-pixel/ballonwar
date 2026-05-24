@tool
extends EditorPlugin

func _enter_tree():
	add_autoload_singleton("CrazyGamesBridge", "res://addons/crazygames/Utils/CrazyGamesBridge.gd")
	add_autoload_singleton("CrazyGames", "res://addons/crazygames/CrazyGames.gd")


func _exit_tree():
	remove_autoload_singleton("CrazyGames")
	remove_autoload_singleton("CrazyGamesBridge")
