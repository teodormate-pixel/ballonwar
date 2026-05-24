class_name UserModule

func is_user_account_available() -> bool:
	return CrazyGamesBridge.is_user_account_available()
	
func show_auth_prompt_async() -> Dictionary:
	CrazyGamesBridge.show_auth_prompt()
	var signal_result = await CrazyGamesBridge.callbacks.show_auth_prompt_complete
	return signal_result

func show_account_link_prompt_async () -> Dictionary:
	CrazyGamesBridge.show_account_link_prompt();
	var signal_result = await CrazyGamesBridge.callbacks.show_account_link_prompt_complete
	return signal_result
	
func get_user_async() -> Dictionary:
	CrazyGamesBridge.get_user()
	var signal_result = await CrazyGamesBridge.callbacks.get_user_complete
	return signal_result

func get_user_token_async() -> String:
	CrazyGamesBridge.get_user_token()
	var signal_result = await CrazyGamesBridge.callbacks.get_user_token_complete
	return signal_result
	
func get_xsolla_user_token_async() -> String:
	CrazyGamesBridge.get_xsolla_user_token()
	var signal_result = await CrazyGamesBridge.callbacks.get_xsolla_user_token_complete
	return signal_result
