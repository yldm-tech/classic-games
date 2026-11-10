class_name CatalogLinks
extends RefCounted

const GAME_PREFIX := "https://forgeplay.app/g/"

static func game_url(id: String) -> String:
	return GAME_PREFIX + id.uri_encode()
