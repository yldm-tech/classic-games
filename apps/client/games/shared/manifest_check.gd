extends SceneTree

## The manifest schema check (make games-check): every directory under the games roots must be a loadable game. It fails on anything the launcher would only report at run time, and on what the launcher cannot see at all:
##   - the manifest is valid (games/shared/game_manifest.gd);
##   - a module's entry script loads and extends GameModule;
##   - a module has at least one *_test.gd of its own;
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
			if node is Node:
				(node as Node).free()
		var tested := false
		for file in files:
			tested = tested or file.ends_with("_test.gd")
		if not tested:
			out.append("tests: a game module needs at least one *_test.gd in its directory")
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

## Every file under `dir`, as paths relative to it.
func _files(dir: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		out.append(prefix + file)
	for folder in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(folder), prefix + folder + "/"))
	return out
