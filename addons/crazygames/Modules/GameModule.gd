class_name GameModule

func happy_time():
	CrazyGamesBridge.happy_time()

func gameplay_start():
	CrazyGamesBridge.gameplay_start()
	
func gameplay_stop():
	CrazyGamesBridge.gameplay_stop()
	
func request_invite_url(params: Dictionary) -> String:
	return CrazyGamesBridge.request_invite_url(params)
	
func get_invite_link_param(param_name: String) -> String:
	return CrazyGamesBridge.get_invite_link_param(param_name);
	
func show_invite_button(params: Dictionary):
	CrazyGamesBridge.show_invite_button(params)
	
func hide_invite_button():
	CrazyGamesBridge.hide_invite_button()

func get_game_settings() -> Dictionary:
	return CrazyGamesBridge.get_game_settings()
