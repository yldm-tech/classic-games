class_name NetworkMatchRuntime
extends Node2D

## 权威联机快照的轻量可视化。这里不推进游戏规则，只投影服务端位置、生命、分数和胜负。

const LOCAL_COLOR := Color("5ce1e6")
const REMOTE_COLOR := Color("ff8a5b")

var local_user_id := ""
var players := Node2D.new()
var _entities: Dictionary = {}

func _init() -> void:
	name = "NetworkMatchRuntime"
	set_meta("summary", {"runtime":"network_match", "score":0, "cleared":false, "defeated":false})
	var arena := Polygon2D.new()
	arena.name = "Arena"
	arena.polygon = PackedVector2Array([Vector2(-460, -250), Vector2(460, -250), Vector2(460, 250), Vector2(-460, 250)])
	arena.color = Color("101a2b")
	add_child(arena)
	players.name = "Players"
	add_child(players)

func configure(p_local_user_id: String) -> void:
	local_user_id = p_local_user_id

func apply_snapshot(snapshot: Dictionary) -> void:
	var present := {}
	for value: Variant in snapshot.get("players", []):
		if value is not Dictionary:
			continue
		var user_id := str(value.get("user_id", ""))
		if user_id == "":
			continue
		present[user_id] = true
		var entity: Node2D = _entities.get(user_id)
		if entity == null:
			entity = _make_player(user_id)
			_entities[user_id] = entity
			players.add_child(entity)
		entity.position = Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
		entity.set_meta("hp", int(value.get("health", 0)))
		entity.set_meta("score", int(value.get("score", 0)))
		entity.set_meta("local", user_id == local_user_id)
		(entity.get_node("Body") as Polygon2D).color = LOCAL_COLOR if user_id == local_user_id else REMOTE_COLOR
		(entity.get_node("Name") as Label).text = "%s  HP %d" % [user_id, int(value.get("health", 0))]
	for user_id: String in _entities.keys():
		if not present.has(user_id):
			var stale: Node2D = _entities[user_id]
			_entities.erase(user_id)
			stale.queue_free()
	var local := _player(snapshot, local_user_id)
	var score := int(local.get("score", 0))
	set_meta("score", score)
	var finished := str(snapshot.get("status", "")) == "finished"
	var won := finished and str(snapshot.get("winner_id", "")) == local_user_id
	set_meta("summary", {"runtime":"network_match", "score":score, "cleared":won, "defeated":finished and not won})

func _player(snapshot: Dictionary, user_id: String) -> Dictionary:
	for value: Variant in snapshot.get("players", []):
		if value is Dictionary and str(value.get("user_id", "")) == user_id:
			return value
	return {}

func _make_player(user_id: String) -> Node2D:
	var entity := Node2D.new()
	entity.name = user_id.replace("/", "_").replace(":", "_")
	var body := Polygon2D.new()
	body.name = "Body"
	var points := PackedVector2Array()
	for i in 12:
		points.append(Vector2.from_angle(TAU * float(i) / 12.0) * 18.0)
	body.polygon = points
	entity.add_child(body)
	var label := Label.new()
	label.name = "Name"
	label.position = Vector2(-42, -42)
	label.add_theme_font_size_override("font_size", 12)
	entity.add_child(label)
	return entity
