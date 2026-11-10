class_name CommunityLinks
extends RefCounted

const PROFILE_PREFIX := "https://forgeplay.app/u/"

static func profile_url(handle: String) -> String:
	return PROFILE_PREFIX + handle.uri_encode()

static func profile_handle(content: String) -> String:
	content = content.strip_edges()
	if not content.begins_with(PROFILE_PREFIX):
		return ""
	var handle := content.substr(PROFILE_PREFIX.length()).uri_decode()
	if "/" in handle or "?" in handle or "#" in handle:
		return ""
	return handle
