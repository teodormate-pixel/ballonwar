class_name AdModule

func request_ad_async (ad_type: String) -> Dictionary:
	CrazyGamesBridge.request_ad(ad_type)
	var stateDict: Dictionary = await CrazyGamesBridge.callbacks.ad_status_change
	if (stateDict.has("state") and stateDict["state"] == "started"):
		stateDict = await CrazyGamesBridge.callbacks.ad_status_change
		return stateDict;
	return stateDict;
	

func request_banners (banners: Array):
	CrazyGamesBridge.request_banners(banners)
	
var _registered_banners: Array[CrazyBanner] = []

func register_banner(banner: CrazyBanner):
	if not _registered_banners.has(banner):
		_registered_banners.append(banner)

func unregister_banner(banner: CrazyBanner):
	if _registered_banners.has(banner):
		_registered_banners.erase(banner)

func refresh_banners():
	var visible_banners_data = []
	for banner in _registered_banners:
		if banner.is_visible_in_tree():
			banner.regenerate_id()
			visible_banners_data.append(banner.get_data_for_sdk())
	
	if visible_banners_data.is_empty():
		print("No visible banners to refresh.")
		return
	
	print("Refreshing %s banners." % visible_banners_data.size())
	request_banners(visible_banners_data)
