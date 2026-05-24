class_name Callbacks

signal sdk_initialized
signal adblock_detection_result(has_adblock: bool)
signal ad_status_change
signal ad_started
signal ad_finished
signal ad_error(error: Dictionary)
signal auth_listener_complete(user: Dictionary)
signal show_auth_prompt_complete(user: Dictionary)
signal show_account_link_prompt_complete(response: Dictionary)
signal get_user_complete(user: Dictionary)
signal get_user_token_complete(token: String)
signal get_xsolla_user_token_complete(token: String)

var onSdkInitialized = JavaScriptBridge.create_callback(_on_sdk_initialized)
var onAdblockDetectionResult = JavaScriptBridge.create_callback(_on_adblock_detection_result)
var onAuthListener = JavaScriptBridge.create_callback(_on_auth_listener)
var adStatusChange = JavaScriptBridge.create_callback(_on_ad_status_change)
var adStarted = JavaScriptBridge.create_callback(_on_ad_started)
var adFinished = JavaScriptBridge.create_callback(_on_ad_finished)
var adError = JavaScriptBridge.create_callback(_on_ad_error)
var showAuthPrompt = JavaScriptBridge.create_callback(_on_show_auth_prompt_callback)
var showAccountLinkPrompt = JavaScriptBridge.create_callback(_on_show_account_link_prompt_callback)
var getUser = JavaScriptBridge.create_callback(_on_get_user_callback)
var getUserToken = JavaScriptBridge.create_callback(_on_get_user_token_callback)
var getXsollaUserToken = JavaScriptBridge.create_callback(_on_get_xsolla_user_token_callback)

func init():
	var window = JavaScriptBridge.get_interface("window")
	
	window.onSdkInitialized = onSdkInitialized	
	window.onAdblockDetectionResult = onAdblockDetectionResult
	window.onAuthListener = onAuthListener
	window.onAdStatusChange = adStatusChange
	window.onAdStarted = adStarted
	window.onAdFinished = adFinished
	window.onAdError = adError
	window.onShowAuthPrompt = showAuthPrompt
	window.onShowAccountLinkPrompt = showAccountLinkPrompt
	window.onGetUser = getUser
	window.onGetUserToken = getUserToken
	window.onGetXsollaUserToken = getXsollaUserToken
	

func _on_sdk_initialized(_args):
	emit_signal("sdk_initialized")

func _on_adblock_detection_result(args):
	emit_signal("adblock_detection_result", args[0])

func _on_ad_status_change(args):
	var data = JSON.parse_string(args[0])
	
	if "state" in data:
		ad_status_change.emit(data)
		if (data["state"] == "started"):
			emit_signal("ad_started")
		elif (data["state"] == "finished"):
			emit_signal("ad_finished")
		else:
			emit_signal("ad_error", JSON.parse_string(data["error"]))
	else:
		emit_signal("ad_error", JSON.parse_string("{ \"error\": \"invalid JSON\" }"))

func _on_ad_started(_args):
	emit_signal("ad_started")

func _on_ad_finished(_args):
	emit_signal("ad_finished")

func _on_ad_error(args):
	var error_dict = JSON.parse_string(args[0])
	emit_signal("ad_error", error_dict)

func _on_auth_listener(args):
	var user_dict = JSON.parse_string(args[0])
	emit_signal("auth_listener", user_dict)

func _on_show_auth_prompt_callback(args):
	var data = JSON.parse_string(args[0])
	if data.has("user"):
		var user_dict = JSON.parse_string(data["user"])
		emit_signal("show_auth_prompt_complete", user_dict)
	elif data.has("error"):
		var error_dict = JSON.parse_string(data["error"])
		emit_signal("show_auth_prompt_complete", error_dict)

func _on_show_account_link_prompt_callback(args):
	var data = JSON.parse_string(args[0])
	if data.has("response"):
		var response_dict = JSON.parse_string(data["response"])
		emit_signal("show_account_link_prompt_complete", response_dict)
	elif data.has("error"):
		var error_dict = JSON.parse_string(data["error"])
		emit_signal("show_account_link_prompt_complete", error_dict)

func _on_get_user_callback(args):
	var data = JSON.parse_string(args[0])
	if data.has("user"):
		var user_dict = JSON.parse_string(data["user"])
		emit_signal("get_user_complete", user_dict)
	elif data.has("error"):
		var error_dict = JSON.parse_string(data["error"])
		emit_signal("get_user_complete", error_dict)

func _on_get_user_token_callback(args):
	var data = JSON.parse_string(args[0])
	if data.has("token"):
		emit_signal("get_user_token_complete", data["token"])
	elif data.has("error"):
		emit_signal("get_user_token_complete", data["error"])

func _on_get_xsolla_user_token_callback(args):
	var data = args[0]
	if data.has("token"):
		emit_signal("get_xsolla_user_token_complete", data["token"])
	elif data.has("error"):
		emit_signal("get_xsolla_user_token_complete", data["error"])
