@tool
class_name CrazyBanner
extends Control

enum BannerSize {
	LEADERBOARD_728x90,
	MEDIUM_300x250,
	MOBILE_320x50,
	MAIN_BANNER_468x60,
	LARGE_MOBILE_320x100
}

@export var banner_size: BannerSize = BannerSize.LEADERBOARD_728x90:
	get:
		return banner_size
	set(new_value):
		if banner_size == new_value:
			return

		banner_size = new_value
		_update_control_size()


var banner_id: String = ""


func _ready():
	_update_control_size()
	regenerate_id()

	if not Engine.is_editor_hint():
		if CrazyGames and is_visible_in_tree():
			CrazyGames.Ad.register_banner(self)


func _exit_tree():
	if not Engine.is_editor_hint():
		if Engine.has_singleton("CrazyGames"):
			CrazyGames.Ad.unregister_banner(self)


func _update_control_size():
	match banner_size:
		BannerSize.LEADERBOARD_728x90:
			size = Vector2(728, 90)
		BannerSize.MEDIUM_300x250:
			size = Vector2(300, 250)
		BannerSize.MOBILE_320x50:
			size = Vector2(320, 50)
		BannerSize.MAIN_BANNER_468x60:
			size = Vector2(468, 60)
		BannerSize.LARGE_MOBILE_320x100:
			size = Vector2(320, 100)


func regenerate_id():
	var random_bytes = Marshalls.variant_to_base64(Time.get_unix_time_from_system() + randi())
	banner_id = random_bytes.sha1_text()


func get_data_for_sdk() -> Dictionary:
	var size_string: String
	match banner_size:
		BannerSize.LEADERBOARD_728x90: size_string = "728x90"
		BannerSize.MEDIUM_300x250: size_string = "300x250"
		BannerSize.MOBILE_320x50: size_string = "320x50"
		BannerSize.MAIN_BANNER_468x60: size_string = "468x60"
		BannerSize.LARGE_MOBILE_320x100: size_string = "320x100"

	var anchor_center = Vector2((anchor_left + anchor_right) / 2.0, (anchor_top + anchor_bottom) / 2.0)
	var normalized_pivot = Vector2(0.5, 0.5)
	var center_position = position + (size / 2.0)

	return {
		"id": banner_id,
		"size": size_string,
		"position": { "x": center_position.x, "y": center_position.y },
		"anchor": { "x": anchor_center.x, "y": anchor_center.y },
		"pivot": { "x": normalized_pivot.x, "y": normalized_pivot.y }
	}
