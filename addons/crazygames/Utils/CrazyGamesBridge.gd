extends Node

var callbacks: Callbacks = Callbacks.new()

func init_sdk(version: String):
	callbacks.init()

	var js = """
		window.GodotSDK = {
			version: '%s',
			pointerLockElement: undefined,
			unlockPointer: function () {
				this.pointerLockElement = document.pointerLockElement || null;
				if (this.pointerLockElement && document.exitPointerLock) {
					document.exitPointerLock();
				}
			},
			lockPointer: function () {
				if (this.pointerLockElement && this.pointerLockElement.requestPointerLock) {
					this.pointerLockElement.requestPointerLock();
				}
			}
		};

		var initOptions = {
			wrapper: {
				engine: 'godot',
				sdkVersion: '%s'
			}
		};

		var script = document.createElement('script');
		script.src = 'https://sdk.crazygames.com/crazygames-sdk-v3.js';
		document.head.appendChild(script);
		script.addEventListener('load', async function () {
			await window.CrazyGames.SDK.init(initOptions);
			window.onSdkInitialized();
			window.CrazyGames.SDK.ad.hasAdblock().then(function (result) {
				window.onAdblockDetectionResult(result);
			})
			.catch(function (error) {
				window.onAdblockDetectionResult(false);
			});
			window.CrazyGames.SDK.user.addAuthListener(function (user) {
				window.onAuthListener(JSON.stringify(user));
			});
		});
	""" % [version, version]
	JavaScriptBridge.eval(js)

## ------------------------------------------------------------------
## Ad Module
## ------------------------------------------------------------------

func request_ad(ad_type: String):
	var js = """
		var callbacks = {
			adStarted: function () {
				window.GodotSDK.unlockPointer();
				window.onAdStarted();
				window.onAdStatusChange(JSON.stringify({ "state" : "started"}));
			},
			adFinished: function () {
				window.GodotSDK.lockPointer();
				window.onAdFinished();
				window.onAdStatusChange(JSON.stringify({ "state" : "finished"}));
			},
			adError: function (error) {
				window.onAdError(JSON.stringify(error));
				window.onAdStatusChange(JSON.stringify({ "state" : "started", "error" : error}));
			}
		};
		window.CrazyGames.SDK.ad.requestAd('%s', callbacks);
	""" % ad_type
	JavaScriptBridge.eval(js)


## ------------------------------------------------------------------
## Banner Module
## ------------------------------------------------------------------

func request_banners(banners: Array):
	var banners_json = JSON.stringify(banners)
	var js = "window.CrazyGames.SDK.banner.requestOverlayBanners(%s);" % banners_json
	JavaScriptBridge.eval(js)


## ------------------------------------------------------------------
## Game Module
## ------------------------------------------------------------------

func happy_time():
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.happytime();")

func gameplay_start():
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.gameplayStart();")

func gameplay_stop():
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.gameplayStop();")

func request_invite_url(params: Dictionary) -> String:
	var params_json = JSON.stringify(params)
	var url = JavaScriptBridge.eval("window.CrazyGames.SDK.game.inviteLink(JSON.parse('%s'));" % params_json)
	return url as String

func get_invite_link_param(param_name: String) -> String:
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s');" % param_name)
	if value == null:
		return ""
	return value as String

func show_invite_button(params: Dictionary) -> String:
	var params_json = JSON.stringify(params)
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.showInviteButton(JSON.parse('%s'));" % params_json)
	return request_invite_url(params)

func hide_invite_button():
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.hideInviteButton();")

func get_game_settings() -> Dictionary:
	var settings_json = JavaScriptBridge.eval("JSON.stringify(window.CrazyGames.SDK.game.settings);")
	if typeof(settings_json) == TYPE_STRING and not settings_json.is_empty():
		var result = JSON.parse_string(settings_json)
		if result is Dictionary:
			return result
	return {}


## ------------------------------------------------------------------
## User Module
## ------------------------------------------------------------------

func is_user_account_available() -> bool:
	return JavaScriptBridge.eval("window.CrazyGames.SDK.user.isUserAccountAvailable;") as bool

func show_auth_prompt():
	var js = """
		window.CrazyGames.SDK.user
			.showAuthPrompt()
			.then(function (user) {
				window.onShowAuthPrompt(JSON.stringify({ user: user }));
			})
			.catch(function (error) {
				window.onShowAuthPrompt(JSON.stringify({ error: error }));
			});
	"""
	JavaScriptBridge.eval(js)

func show_account_link_prompt():
	var js = """
		window.CrazyGames.SDK.user
			.showAccountLinkPrompt()
			.then(function (response) {
				window.onShowAccountLinkPrompt(JSON.stringify({ response: response }));
			})
			.catch(function (error) {
				window.onShowAccountLinkPrompt(JSON.stringify({ error: error }));
			});
	"""
	JavaScriptBridge.eval(js)

func get_user():
	var js = """
		window.CrazyGames.SDK.user
			.getUser()
			.then(function (user) {
				window.onGetUser(JSON.stringify({ user: user }));
			})
			.catch(function (error) {
				window.onGetUser(JSON.stringify({ error: error }));
			});
	"""
	JavaScriptBridge.eval(js)

func get_user_token():
	var js = """
		window.CrazyGames.SDK.user
			.getUserToken()
			.then(function (token) {
				window.onGetUserToken(JSON.stringify({ token: token }));
			})
			.catch(function (error) {
				window.onGetUserToken(JSON.stringify({ error: error }));
			});
	"""
	JavaScriptBridge.eval(js)

func get_xsolla_user_token():
	var js = """
		window.CrazyGames.SDK.user
			.getXsollaUserToken()
			.then(function (token) {
				window.onGetXsollaUserToken(JSON.stringify({ token: token }));
			})
			.catch(function (error) {
				window.onGetXsollaUserToken(JSON.stringify({ error: error }));
			});
	"""
	JavaScriptBridge.eval(js)


## ------------------------------------------------------------------
## Data Module
## ------------------------------------------------------------------

func data_clear():
	JavaScriptBridge.eval("window.CrazyGames.SDK.data.clear();")

func data_get_item(key: String) -> String:
	var value = JavaScriptBridge.eval("window.CrazyGames.SDK.data.getItem('%s');" % key)
	if value != null:
		return value as String
	return ""

func data_has_key(key: String) -> bool:
	return JavaScriptBridge.eval("window.CrazyGames.SDK.data.getItem('%s') !== null;" % key) as bool

func data_remove_item(key: String):
	JavaScriptBridge.eval("window.CrazyGames.SDK.data.removeItem('%s');" % key)

func data_set_item(key: String, value: String):
	JavaScriptBridge.eval("window.CrazyGames.SDK.data.setItem('%s', '%s');" % [key, value])

## ------------------------------------------------------------------
## Analytics Module
## ------------------------------------------------------------------

func analytics_track_order(provider: String, order: Dictionary):
	var order_json = JSON.stringify(order)
	JavaScriptBridge.eval("window.CrazyGames.SDK.analytics.trackOrder('%s', JSON.parse('%s'));" % [provider, order_json])


## ------------------------------------------------------------------
## Other
## ------------------------------------------------------------------

func copy_to_clipboard(text: String):
	JavaScriptBridge.eval("navigator.clipboard.writeText('%s');" % text)

func get_environment() -> String:
	return JavaScriptBridge.eval("window.CrazyGames.SDK.environment;") as String

func get_system_info() -> Dictionary:
	var info_json = JavaScriptBridge.eval("JSON.stringify(window.CrazyGames.SDK.user.systemInfo);")
	if typeof(info_json) == TYPE_STRING and not info_json.is_empty():
		var result = JSON.parse_string(info_json)
		if result is Dictionary:
			return result
	return {}
