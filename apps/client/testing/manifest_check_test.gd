extends SceneTree

## Tests of the manifest check itself (games/shared/manifest_check.gd, `make games-check`): it has to fail, with a line that says why, for every way a game directory can be unfit to ship. The check is a script of its own, so it is run as a child process of this engine binary against the directories under unfit_games/ (each holds a valid manifest and exactly the problem it is named after) and against the fixture games, which must pass.

const CHECK := "res://games/shared/manifest_check.gd"
const UNFIT := "res://testing/unfit_games"
const FIT := "res://testing/games"

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var unfit := _run_check(UNFIT)
	var output: String = unfit["output"]
	_check("the check fails on unfit directories", int(unfit["code"]) != 0)
	_check("it still reaches its summary line", output.contains("manifest_check: 8 games, "))
	var expected := {
		"untested: tests: a game module needs at least one *_test.gd": "a module without a test",
		"no_assets_file: ASSETS.md: missing": "a directory without ASSETS.md",
		"unlisted_asset: ASSETS.md: does not list `level.bin`": "an asset ASSETS.md does not list",
		"own_process: entry: main.gd defines _process(), which belongs to GameModule": "an entry script with its own _process",
		"not_a_module: entry: main.gd must extend GameModule": "an entry script that is not a GameModule",
		"hud_typo: hud.clock.field: the snapshot has no \"time_remaining\"": "a clock field the snapshot lacks",
		"hud_typo: hud.stats[0]: the snapshot has no \"wave\"": "a shared counter the snapshot lacks",
		"hud_typo: hud.player_stats[0]: players[0] in the snapshot has no \"keys\"": "a per-player counter the snapshot lacks",
		"one_seat_reported: snapshot: players must be a list with one dictionary per seat (2)": "a two-seat game that reports one player",
		"no_site_screenshot: site.screenshot: \"site_screenshot.png\" does not exist": "a website screenshot that is not there",
	}
	for line: String in expected:
		_check("it reports %s" % expected[line], output.contains("manifest_check: " + line))
	for clean: String in ["hud_typo: hud.vital", "unlisted_asset: tests", "own_process: ASSETS.md", "no_site_screenshot: entry"]:
		_check("it reports nothing that is not wrong (%s)" % clean, not output.contains("manifest_check: " + clean))

	var fit := _run_check(FIT)
	_check("the fixture games pass the same check", int(fit["code"]) == 0 and str(fit["output"]).contains(" games, 0 problems"))
	var nowhere := _run_check("res://testing/does_not_exist")
	_check("a root without any game fails instead of passing vacuously", int(nowhere["code"]) != 0 and str(nowhere["output"]).contains("no game found there"))

	print("manifest_check_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

## Run the check on one games root in a child process: { code, output }.
func _run_check(games_root: String) -> Dictionary:
	OS.set_environment("GAME_CHECK_ROOTS", games_root)
	OS.set_environment("GAME_CHECK_MANIFESTS_ONLY", "")
	var lines: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CHECK], lines, true)
	return {"code": code, "output": "\n".join(PackedStringArray(lines))}

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + label)
