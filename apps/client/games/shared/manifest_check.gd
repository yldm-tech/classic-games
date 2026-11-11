extends SceneTree

## The manifest schema check (make games-check): every directory under the games roots must be a loadable game. It fails on anything the launcher would only report at run time, and on what the launcher cannot see at all:
##   - the manifest is valid (games/shared/game_manifest.gd);
##   - a module's entry script loads and extends GameModule, and does not redefine a method that belongs to the base class;
##   - a module started with its default options and its largest player count reports every snapshot field its HUD names;
##   - a module has at least one *_test.gd of its own, at the top of its directory where the test runner looks;
##   - the website screenshot a manifest names (site.screenshot) is there;
##   - the directory has an ASSETS.md, and every file in it that is not source is named there;
##   - its media fit the budget (MEDIA_FILE_BYTES per file, MEDIA_BUDGET_BYTES per game), audio is in a format that loops cleanly, no image is larger than a GPU on the web or a phone takes, and on a stage that is not pixel art every image is imported with mipmaps.
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

## The media budget: what one asset file and what all the assets of one game may weigh in the repository. Every clone and every web build carries these bytes. The environment variables override them in kilobytes; the check's own test uses that to try the rule on files of a few kilobytes.
const MEDIA_FILE_BYTES := 4 * 1024 * 1024
const MEDIA_BUDGET_BYTES := 16 * 1024 * 1024
const MEDIA_FILE_ENV := "GAME_CHECK_MEDIA_FILE_KB"
const MEDIA_BUDGET_ENV := "GAME_CHECK_MEDIA_BUDGET_KB"
## Largest side of an image. Larger textures fail to load on WebGL and on many phones.
const MAX_IMAGE_SIDE := 4096
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
## Audio a game may ship: Ogg Vorbis for everything, WAV for short effects. The rest either cannot loop without a gap (MP3, AAC) or is not imported by the engine.
const AUDIO_EXTENSIONS := ["ogg", "wav"]
const OTHER_AUDIO_EXTENSIONS := ["mp3", "m4a", "aac", "flac", "opus", "wma", "aif", "aiff"]

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
	out.append_array(_media_problems(game, dir, files))
	return out

## Size, format and import settings of a game's asset files.
func _media_problems(game: Dictionary, dir: String, files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var file_limit := _limit(MEDIA_FILE_ENV, MEDIA_FILE_BYTES)
	var budget := _limit(MEDIA_BUDGET_ENV, MEDIA_BUDGET_BYTES)
	var smooth: bool = game["kind"] == Manifest.KIND_MODULE and not bool(Manifest.stage(game)["pixel_art"])
	# The key art and the website screenshot are shown by the launcher and the website at their own size, not drawn on the stage.
	var off_stage := [str((game.get("art", {}) as Dictionary).get("image", "")), str((game.get("site", {}) as Dictionary).get("screenshot", ""))]
	var total := 0
	for file in files:
		var extension := file.get_extension().to_lower()
		if extension in SOURCE_EXTENSIONS:
			continue
		var handle := FileAccess.open(dir.path_join(file), FileAccess.READ)
		var bytes := handle.get_length() if handle != null else 0
		total += bytes
		if bytes > file_limit:
			out.append("media: `%s` is %s; one asset file may be at most %s (a smaller picture, a lossy format for an opaque one, a shorter or lower-quality audio file)" % [file, _size_text(bytes), _size_text(file_limit)])
		if extension in OTHER_AUDIO_EXTENSIONS:
			out.append("media: `%s`: games ship audio as Ogg Vorbis (.ogg), which loops without a gap; convert it with scripts/assets/assets.py audio" % file)
		if extension in IMAGE_EXTENSIONS:
			var texture := load(dir.path_join(file)) as Texture2D
			if texture != null and maxi(texture.get_width(), texture.get_height()) > MAX_IMAGE_SIDE:
				out.append("media: `%s` is %dx%d; no side of an image may exceed %d pixels" % [file, texture.get_width(), texture.get_height(), MAX_IMAGE_SIDE])
			if smooth and not file in off_stage and not FileAccess.get_file_as_string(dir.path_join(file) + ".import").contains("mipmaps/generate=true"):
				out.append("media: `%s` is imported without mipmaps, so it shimmers when drawn smaller than it is; set mipmaps/generate=true in %s.import (new imports get it from the project's defaults) and run make import" % [file, file])
	if total > budget:
		out.append("media: the assets weigh %s in all; a game's budget is %s" % [_size_text(total), _size_text(budget)])
	return out

func _limit(variable: String, fallback: int) -> int:
	var text := OS.get_environment(variable)
	return int(text) * 1024 if text.is_valid_int() and int(text) > 0 else fallback

func _size_text(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0) if bytes >= 1048576 else "%.1f KB" % (float(bytes) / 1024.0)

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
