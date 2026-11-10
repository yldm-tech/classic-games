class_name CatalogRetryController
extends RefCounted

var router: Router
var _library_retry: Callable
var _library_generation := 0

func _init(p_router: Router) -> void:
	router = p_router

func remember_library(retry: Callable) -> int:
	_library_generation += 1
	_library_retry = retry
	return _library_generation

func complete_library(generation: int) -> void:
	if generation == _library_generation:
		_library_retry = Callable()

func retry(generic_screens: Array[ScreenBase], search: SearchScreen, fallback_retry: Callable) -> void:
	for screen: ScreenBase in generic_screens:
		screen._refreshed = false
	router.back()
	if router.view == "search":
		search.retry_current()
	elif router.view == "library" and _library_retry.is_valid():
		_library_retry.call()
	if fallback_retry.is_valid():
		fallback_retry.call()
