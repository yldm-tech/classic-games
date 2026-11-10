class_name ScreenRegistry
extends RefCounted

var routes: Dictionary = {}
var _factories: Dictionary = {}
var _instances: Dictionary = {}

func register_factory(key: String, factory: Callable) -> bool:
	if key.is_empty() or not factory.is_valid() or _factories.has(key):
		return false
	_factories[key] = factory
	return true

func has_factory(key:String)->bool:
	return _factories.has(key)

func build(key: String) -> Node:
	if _instances.has(key):
		return _instances[key]
	if not _factories.has(key):
		return null
	var instance: Node = (_factories[key] as Callable).call()
	if instance != null:
		_instances[key] = instance
	return instance

func create(view_name: String, factory: Callable, title_key: String = "") -> Node:
	if routes.has(view_name):
		return routes[view_name]["screen"]
	var instance: Node = factory.call()
	register(view_name, instance, title_key)
	return instance

func register(view_name: String, instance: Node, title_key: String = "") -> bool:
	if view_name == "" or instance == null or routes.has(view_name):
		return false
	routes[view_name] = {"screen": instance, "title": title_key}
	return true

func screen(view_name: String) -> Node:
	return routes.get(view_name, {}).get("screen")

func title(view_name: String) -> String:
	return str(routes.get(view_name, {}).get("title", ""))

func dispose_detached() -> void:
	var candidates: Array = routes.values().map(func(entry: Dictionary): return entry.get("screen"))
	candidates.append_array(_instances.values())
	var seen: Dictionary = {}
	for instance: Variant in candidates:
		if is_instance_valid(instance) and seen.has(instance.get_instance_id()):
			continue
		if is_instance_valid(instance) and instance.get_parent() == null:
			seen[instance.get_instance_id()] = true
			instance.free()
	routes.clear()
	_instances.clear()
	_factories.clear()
