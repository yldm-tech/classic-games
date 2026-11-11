extends SceneTree

## The manifest schema check (make games-check): every directory under the games roots must be a loadable game. It fails on anything the launcher would only report at run time, and on what the launcher cannot see at all:
##   - the manifest is valid (games/shared/game_manifest.gd);
##   - a module's entry script loads and extends GameModule, and does not redefine a method that belongs to the base class;
##   - a module started with its default options and its largest player count reports every snapshot field its HUD names;
##   - a module has at least one *_test.gd of its own, at the top of its directory where the test runner looks;
##   - the website screenshot a manifest names (site.screenshot) is there;
##   - the directory has an ASSETS.md, and every file in it that is not source is named there.
## Prints one line per problem and ends with "manifest_check: <n> games, <m> problems".

const Registry := preload("res://games/shared/game_registry.gd")
const Manifest := preload("res://games/shared/game_manifest.gd")
const Module := preload("res://games/shared/game_module.gd")

const ASSETS_FILE := "ASSETS.md"
## Environment variable with the games roots to check, comma-separated. The Makefile passes the shipped games and the test fixture, which is held to the same rules; without it only the shipped games are checked.
const ROOTS_ENV := "GAME_CHECK_ROOTS"
## Set to 1 to check the manifests alone. An exported pack holds no ASSETS.md and no tests, so the export check (scripts/check-export-discovery.sh) runs this script inside the pack that way.
const MANIFESTS_ONLY_ENV := "GAME_CHECK_MANIFESTS_ONLY"
## Methods of GameModule that a game must not define itself: the frame loop and what the host calls. Redefining one silently replaces the contract (a game with its own _process is never stepped).
const BASE_METHODS := ["_process", "_physics_process", "start", "set_paused", "snapshot", "feed", "release_inputs", "join", "leave", "advance", "finish", "input", "active_players", "player_count", "is_player_active", "is_running", "is_finished", "is_paused", "_tick"]
## Files that are code, data written for the game, or engine bookkeeping. Anything else is an asset and needs a line in ASSETS.md.
const SOURCE_EXTENSIONS := ["gd", "uid", "import", "json", "md", "tscn", "tres", "gdshader", "gdshaderinc", "txt", "cfg"]

func _initialize() -> void:
	var games := 0
	var problems := PackedStringArray()
	var roots := OS.get_environment(ROOTS_ENV).split(",", false)
	if roots.is_empty():
		roots = PackedStringArray([Registry.GAMES_ROOT])
	for root_dir: String in roots:
		root_dir = root_dir.strip_edges()
		var found := Registry.discover(root_dir)
		problems.append_array(Registry.problem_lines(found["problems"]))
		if (found["games"] as Array).is_empty() and (found["problems"] as Array).is_empty():
			problems.append("%s: no game found there" % root_dir)
		for game: Dictionary in found["games"]:
			games += 1
			if OS.get_environment(MANIFESTS_ONLY_ENV) == "1":
				continue
			for line in _directory_problems(game):
				problems.append("%s: %s" % [game["id"], line])
	for line in problems:
		printerr("manifest_check: " + line)
	print("manifest_check: %d games, %d problems" % [games, problems.size()])
	quit.call_deferred(0 if problems.is_empty() and games > 0 else 1)

func _directory_problems(game: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := str(game["dir"])
	var files := _files(dir, "")
	if game["kind"] == Manifest.KIND_MODULE:
		var script: Variant = load(str(game["entry_path"]))
		if not script is GDScript or not (script as GDScript).can_instantiate():
			out.append("entry: %s does not load" % game["entry"])
		else:
			var node: Variant = (script as GDScript).new()
			if not node is Module:
				out.append("entry: %s must extend GameModule" % game["entry"])
			else:
				out.append_array(_redefined_methods(game))
				out.append_array(_hud_problems(game, node))
			if node is Node:
				(node as Node).free()
		# The test runner (scripts/run-game-tests.sh) runs the *_test.gd files at the top of a game's directory and no others, so a test further down would count for nothing while looking like coverage.
		var tested := false
		for file in files:
			if not file.ends_with("_test.gd"):
				continue
			if file.contains("/"):
				out.append("tests: %s is in a sub-directory and would never run; test files go at the top of the game's directory" % file)
			else:
				tested = true
		if not tested:
			out.append("tests: a game module needs at least one *_test.gd at the top of its directory")
	# The website's screenshot is not shipped with the game, so the manifest schema does not require it to exist; in the source tree it must.
	var site: Dictionary = game.get("site", {})
	if site.has("screenshot") and not files.has(str(site["screenshot"])):
		out.append("site.screenshot: \"%s\" does not exist in %s" % [site["screenshot"], dir])
	if not files.has(ASSETS_FILE):
		out.append("%s: missing; it records the source and licence of every asset" % ASSETS_FILE)
		return out
	var listed := FileAccess.get_file_as_string(dir.path_join(ASSETS_FILE))
	for file in files:
		if not file.get_extension().to_lower() in SOURCE_EXTENSIONS and not listed.contains("`%s`" % file):
			out.append("%s: does not list `%s`" % [ASSETS_FILE, file])
	return out

## Base-class methods the entry script defines itself, read from its source: a subclass method of the same name replaces the base one without any error.
func _redefined_methods(game: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(str(game["entry_path"])).split("\n"):
		if not line.begins_with("func ") and not line.begins_with("static func "):
			continue
		var method := line.trim_prefix("static ").trim_prefix("func ").get_slice("(", 0).strip_edges()
		if method in BASE_METHODS:
			out.append("entry: %s defines %s(), which belongs to GameModule; put game logic in _game_step and presentation in _game_frame" % [game["entry"], method])
	return out

## Start the module once, with its default options and as many players as it seats, and require every snapshot field its HUD names. A misspelt field would otherwise show as a zero or an empty corner and nothing would say why. The boss bar is exempt: its field is there only while a boss is.
func _hud_problems(game: Dictionary, module: Module) -> PackedStringArray:
	var out := PackedStringArray()
	var options := {}
	for option: Dictionary in game.get("options", []):
		options[option["id"]] = option["default"]
	var seats := int(game["players"]["max"])
	root.add_child(module)
	module.start({"options": options, "players": seats, "seed": 1, "locale": "zh", "stage_size": Manifest.stage(game)["size"]})
	module.advance(Module.STEP)
	var state := module.snapshot()
	root.remove_child(module)
	var per_player: Array = []
	if state.has("players"):
		var listed: Variant = state["players"]
		var shaped := listed is Array and (listed as Array).size() >= seats
		if shaped:
			for slot in seats:
				shaped = shaped and listed[slot] is Dictionary
		if not shaped:
			out.append("snapshot: players must be a list with one dictionary per seat (%d)" % seats)
			return out
		per_player = listed
	elif seats > 1:
		out.append("snapshot: a game that seats %d players must report players[0] .. players[%d]" % [seats, seats - 1])
		return out
	var hud: Dictionary = game["hud"]
	var clock: Dictionary = hud["clock"]
	if str(clock["mode"]) != "none":
		for key in ["field", "total"]:
			if clock.has(key) and not state.has(str(clock[key])):
				out.append("hud.clock.%s: the snapshot has no \"%s\"" % [key, clock[key]])
	for stat_index in (hud.get("stats", []) as Array).size():
		for field: String in hud["stats"][stat_index]["fields"]:
			if not state.has(field):
				out.append("hud.stats[%d]: the snapshot has no \"%s\"" % [stat_index, field])
	# Per-player fields are read from players[slot]; a game that reports no players list is read from the top level.
	var wanted: Array = []
	if hud.has("vital"):
		wanted.append(["hud.vital.field", str(hud["vital"]["field"])])
		wanted.append(["hud.vital.max", str(hud["vital"]["max"])])
	for stat_index in (hud.get("player_stats", []) as Array).size():
		for field: String in hud["player_stats"][stat_index]["fields"]:
			wanted.append(["hud.player_stats[%d]" % stat_index, field])
	for pair: Array in wanted:
		var vital: bool = str(pair[0]).begins_with("hud.vital")
		if per_player.is_empty():
			if not state.has(pair[1]):
				out.append("%s: the snapshot has no \"%s\"" % pair)
			continue
		for slot in seats:
			# The vital bar falls back to the top level for player one, the counters do not.
			if not (per_player[slot] as Dictionary).has(pair[1]) and not (vital and slot == 0 and state.has(pair[1])):
				out.append("%s: players[%d] in the snapshot has no \"%s\"" % [pair[0], slot, pair[1]])
	return out

## Every file under `dir`, as paths relative to it.
func _files(dir: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		out.append(prefix + file)
	for folder in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(folder), prefix + folder + "/"))
	return out
