extends RefCounted

## Every sound of Crate Crew. Effects are specs for the shared synthesiser, one per event the world reports: library presets where one fits, layered definitions written for this game where the event is its own (a crate splintering, a boss's tell, a burrow). Music is named by what it plays under: the first map of a run, the map, each of the four places, the bosses, and three short fanfares. Each name is a hook a finished track can be dropped into; until then the names share the recorded placeholder files in audio/.

const DIR := "res://games/crate_crew/audio/"

## Looping music, by hook name, and the file that stands in for it now.
const TRACKS := {
	"title": "theme_bench.ogg",
	"map": "theme_bench.ogg",
	"kitchen": "theme_bench.ogg",
	"toyshop": "theme_bench.ogg",
	"sewer": "theme_shaft.ogg",
	"treehouse": "theme_shaft.ogg",
	"boss": "theme_boss.ogg",
}
## One-shot fanfares. Their names differ from the effect names on purpose: GameAudio counts both in the same table.
const STINGERS := {
	"clear": "fanfare_clear.ogg",
	"victory": "fanfare_won.ogg",
	"gameover": "fanfare_lost.ogg",
}

static var _names: Dictionary = {}

static func has_effect(name: String) -> bool:
	if _names.is_empty():
		for key: String in effects():
			_names[key] = true
	return _names.has(name)

static func effects() -> Dictionary:
	var crack := {"volume": 0.62, "normalize": true, "drive": 0.25, "vary": {"pitch": 0.12}, "layers": [
		{"wave": "pink", "duration": 0.22, "volume": 0.9, "attack": 0.001, "decay": 0.21, "sustain": 0.0, "curve": 2.0, "filter": {"type": "bandpass", "cutoff": 1300, "cutoff_end": 500, "q": 0.8}},
		{"wave": "sine", "freq": 190, "freq_end": 70, "glide": "exp", "duration": 0.1, "volume": 0.7, "attack": 0.001, "decay": 0.095, "sustain": 0.0},
		{"wave": "white", "duration": 0.02, "volume": 0.6, "attack": 0.0005, "release": 0.018, "filter": {"type": "bandpass", "cutoff": 2400, "q": 2.0}},
		{"wave": "white", "start": 0.05, "duration": 0.025, "volume": 0.45, "attack": 0.0005, "release": 0.02, "filter": {"type": "bandpass", "cutoff": 1800, "q": 2.5}},
		{"wave": "white", "start": 0.11, "duration": 0.03, "volume": 0.3, "attack": 0.0005, "release": 0.025, "filter": {"type": "bandpass", "cutoff": 1500, "q": 2.5}},
		{"wave": "triangle", "freq": 640, "freq_end": 310, "glide": "exp", "duration": 0.06, "volume": 0.3, "attack": 0.001, "decay": 0.055, "sustain": 0.0},
	]}
	var tell := {"volume": 0.42, "normalize": true, "vary": {"pitch": 0.05}, "layers": [
		{"wave": "square", "freq": 880, "steps": [1.0, 1.0, 1.335], "duration": 0.3, "volume": 0.5, "attack": 0.002, "decay": 0.28, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 3200}},
		{"wave": "saw", "freq": 110, "freq_end": 140, "duration": 0.3, "volume": 0.4, "attack": 0.01, "release": 0.06, "unison": 2, "detune": 20, "filter": {"type": "lowpass", "cutoff": 900}},
	]}
	return {
		"jump": GameSfx.preset("jump", {"volume": 0.32, "pitch": 1.1, "speed": 1.3}),
		"land": GameSfx.preset("land", {"volume": 0.26}),
		"lift": {"volume": 0.42, "normalize": true, "vary": {"pitch": 0.06}, "layers": [
			{"wave": "triangle", "freq": 210, "freq_end": 470, "glide": "exp", "duration": 0.13, "volume": 0.7, "attack": 0.004, "decay": 0.12, "sustain": 0.0},
			{"wave": "pulse", "duty": 0.3, "freq": 420, "freq_end": 940, "glide": "exp", "duration": 0.09, "volume": 0.22, "attack": 0.003, "decay": 0.085, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 2600}},
			{"wave": "pink", "duration": 0.06, "volume": 0.3, "attack": 0.002, "decay": 0.055, "sustain": 0.0, "filter": {"type": "bandpass", "cutoff": 900, "q": 0.9}},
		]},
		"put_down": GameSfx.preset("impact", {"volume": 0.34, "pitch": 1.35}),
		"clunk": GameSfx.preset("ui_cancel", {"volume": 0.3, "pitch": 0.8}),
		"throw": GameSfx.preset("whoosh", {"volume": 0.42, "pitch": 1.1}),
		"throw_up": GameSfx.preset("whoosh", {"volume": 0.42, "pitch": 1.5}),
		"break": crack,
		"crumble": GameSfx.preset("crumble", {"volume": 0.5}),
		"clang": {"volume": 0.5, "normalize": true, "vary": {"pitch": 0.07}, "reverb": {"mix": 0.18, "size": 0.4, "damp": 0.4}, "tail": 0.3, "layers": [
			{"wave": "sine", "freq": 1240, "duration": 0.3, "volume": 0.6, "attack": 0.0005, "decay": 0.29, "sustain": 0.0, "curve": 2.2, "fm": {"ratio": 2.76, "index": 3.0, "index_end": 0.3}},
			{"wave": "sine", "freq": 1870, "duration": 0.22, "volume": 0.35, "attack": 0.0005, "decay": 0.21, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 1.41, "index": 2.0, "index_end": 0.1}},
			{"wave": "white", "duration": 0.015, "volume": 0.5, "attack": 0.0005, "release": 0.012, "filter": {"type": "highpass", "cutoff": 3000}},
		]},
		"poof": {"volume": 0.3, "normalize": true, "vary": {"pitch": 0.1}, "layers": [
			{"wave": "pink", "duration": 0.16, "volume": 0.8, "attack": 0.004, "decay": 0.15, "sustain": 0.0, "curve": 1.6, "filter": {"type": "lowpass", "cutoff": 2200, "cutoff_end": 400, "q": 0.7}},
		]},
		"thud": GameSfx.preset("impact", {"volume": 0.5, "pitch": 0.8}),
		"foe_out": GameSfx.preset("explosion_small", {"volume": 0.55, "pitch": 1.35}),
		"foe_pop": GameSfx.preset("bounce", {"volume": 0.4, "pitch": 0.8}),
		"stomp": GameSfx.preset("bounce", {"volume": 0.42, "pitch": 1.2}),
		"bonk": GameSfx.preset("impact", {"volume": 0.5, "pitch": 1.6}),
		"dizzy": {"volume": 0.3, "normalize": true, "layers": [
			{"wave": "sine", "freq": 1320, "steps": [1.0, 1.26, 1.0, 1.26], "duration": 0.32, "volume": 0.6, "attack": 0.002, "decay": 0.3, "sustain": 0.0, "vibrato": {"rate": 14, "depth": 0.5}},
		]},
		"hop": GameSfx.preset("bounce", {"volume": 0.24}),
		"lunge": GameSfx.preset("whoosh", {"volume": 0.3, "pitch": 0.8}),
		"wind": {"volume": 0.32, "normalize": true, "layers": [
			{"wave": "noise", "freq": 2400, "duration": 0.4, "volume": 0.6, "attack": 0.01, "release": 0.05, "ring": {"freq": 30, "freq_end": 70, "mix": 0.9}, "filter": {"type": "bandpass", "cutoff": 2800, "q": 1.5}},
		]},
		"puff": GameSfx.preset("shot_light", {"volume": 0.3, "pitch": 0.7}),
		"aim": GameSfx.preset("ui_move", {"volume": 0.22, "pitch": 1.4}),
		"pop": GameSfx.preset("bounce", {"volume": 0.45, "pitch": 1.5}),
		"drip": GameSfx.preset("splash", {"volume": 0.25, "pitch": 1.8}),
		"splat": GameSfx.preset("splash", {"volume": 0.35, "pitch": 1.2}),
		"buzz": {"volume": 0.26, "normalize": true, "layers": [
			{"wave": "saw", "freq": 180, "freq_end": 240, "duration": 0.35, "volume": 0.6, "attack": 0.02, "release": 0.06, "vibrato": {"rate": 30, "depth": 0.6}, "filter": {"type": "lowpass", "cutoff": 1800}},
		]},
		"spawn": GameSfx.preset("door", {"volume": 0.22, "pitch": 1.4}),
		"hurt": GameSfx.preset("hurt", {"volume": 0.5}),
		"bump": GameSfx.preset("impact", {"volume": 0.38, "pitch": 1.1}),
		"die": {"volume": 0.55, "normalize": true, "drive": 0.2, "reverb": {"mix": 0.15, "size": 0.5, "damp": 0.5}, "tail": 0.4, "layers": [
			{"wave": "saw", "freq": 560, "freq_end": 52, "glide": "exp", "duration": 0.75, "volume": 0.6, "attack": 0.004, "decay": 0.7, "sustain": 0.0, "curve": 0.9, "unison": 2, "detune": 16, "filter": {"type": "lowpass", "cutoff": 3600, "cutoff_end": 220, "q": 1.4}},
			{"wave": "square", "freq": 880, "steps": [1.0, 0.75, 0.6, 0.5, 0.375], "duration": 0.5, "volume": 0.25, "attack": 0.002, "decay": 0.48, "sustain": 0.0},
		]},
		"respawn": GameSfx.preset("power_up", {"volume": 0.36, "pitch": 1.2, "speed": 1.5}),
		"acorn": GameSfx.preset("coin", {"volume": 0.28, "pitch": 1.1}),
		"bag": GameSfx.preset("coin", {"volume": 0.4, "pitch": 0.9, "delay": {"time": 0.06, "feedback": 0.4, "mix": 0.4}, "tail": 0.3}),
		"heart": GameSfx.preset("pickup", {"volume": 0.45, "pitch": 0.9}),
		"extra_life": GameSfx.preset("extra_life", {"volume": 0.5}),
		"flag": GameSfx.preset("ui_confirm", {"volume": 0.45, "reverb": {"mix": 0.2, "size": 0.5, "damp": 0.4}, "tail": 0.4}),
		"burrow": {"volume": 0.4, "normalize": true, "layers": [
			{"wave": "sine", "freq": 900, "freq_end": 180, "glide": "exp", "duration": 0.35, "volume": 0.7, "attack": 0.004, "decay": 0.33, "sustain": 0.0},
			{"wave": "pink", "duration": 0.3, "volume": 0.4, "attack": 0.01, "decay": 0.28, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 1400, "cutoff_end": 300}},
		]},
		"secret": {"volume": 0.4, "normalize": true, "reverb": {"mix": 0.3, "size": 0.7, "damp": 0.3}, "tail": 0.7, "layers": [
			{"wave": "sine", "freq": 1047, "steps": [1.0, 1.26, 1.5, 2.0, 2.52], "duration": 0.6, "volume": 0.5, "attack": 0.002, "decay": 0.58, "sustain": 0.0, "curve": 0.7},
		]},
		"map_move": GameSfx.preset("ui_move", {"volume": 0.35}),
		"map_pick": GameSfx.preset("ui_confirm", {"volume": 0.45}),
		"level_start": {"volume": 0.4, "normalize": true, "reverb": {"mix": 0.22, "size": 0.55, "damp": 0.4}, "tail": 0.5, "layers": [
			{"wave": "triangle", "freq": 392, "steps": [1.0, 1.5], "duration": 0.32, "volume": 0.6, "attack": 0.004, "decay": 0.3, "sustain": 0.0, "curve": 0.8},
			{"wave": "sine", "freq": 784, "steps": [1.0, 1.5], "duration": 0.32, "volume": 0.3, "attack": 0.004, "decay": 0.3, "sustain": 0.0},
		]},
		"level_clear": {"volume": 0.3, "normalize": true, "reverb": {"mix": 0.3, "size": 0.7, "damp": 0.3}, "tail": 0.7, "layers": [
			{"wave": "sine", "freq": 1568, "steps": [1.0, 1.25, 1.5, 2.0, 2.5, 3.0], "duration": 0.5, "volume": 0.5, "attack": 0.002, "decay": 0.48, "sustain": 0.0, "curve": 0.7},
			{"wave": "white", "duration": 0.5, "volume": 0.15, "attack": 0.1, "decay": 0.4, "sustain": 0.0, "filter": {"type": "highpass", "cutoff": 6000}},
		]},
		"boss_tell": tell,
		"boss_pop": GameSfx.preset("shot_heavy", {"volume": 0.5, "pitch": 1.4}),
		"boss_throw": GameSfx.preset("whoosh", {"volume": 0.5, "pitch": 0.7}),
		"boss_drop": GameSfx.preset("whoosh", {"volume": 0.4, "pitch": 0.9}),
		"boss_jump": GameSfx.preset("jump", {"volume": 0.45, "pitch": 0.5}),
		"boss_land": GameSfx.preset("land", {"volume": 0.4, "pitch": 0.7}),
		"boss_flap": GameSfx.preset("whoosh", {"volume": 0.35, "pitch": 0.6}),
		"boss_snap": GameSfx.preset("impact", {"volume": 0.6, "pitch": 1.8}),
		"boss_dive": GameSfx.preset("splash", {"volume": 0.5, "pitch": 0.7}),
		"boss_spit": GameSfx.preset("shot_blaster", {"volume": 0.45, "pitch": 0.9}),
		"boss_charge": {"volume": 0.5, "normalize": true, "drive": 0.5, "layers": [
			{"wave": "saw", "freq": 120, "freq_end": 430, "glide": "exp", "duration": 0.5, "volume": 0.7, "attack": 0.01, "release": 0.08, "unison": 2, "detune": 20, "ring": {"freq": 38, "freq_end": 84, "mix": 0.6}, "filter": {"type": "lowpass", "cutoff": 900, "cutoff_end": 3600, "q": 1.4}},
			{"wave": "white", "duration": 0.5, "volume": 0.2, "attack": 0.2, "release": 0.1, "filter": {"type": "bandpass", "cutoff": 1200, "cutoff_end": 3000, "q": 1.0}},
		]},
		"boss_slam": GameSfx.preset("explosion_small", {"volume": 0.7, "pitch": 0.7}),
		"boss_hit": {"volume": 0.6, "normalize": true, "drive": 0.3, "reverb": {"mix": 0.15, "size": 0.4, "damp": 0.4}, "tail": 0.3, "layers": [
			{"wave": "sine", "freq": 180, "freq_end": 52, "glide": "exp", "duration": 0.2, "volume": 0.8, "attack": 0.001, "decay": 0.19, "sustain": 0.0},
			{"wave": "sine", "freq": 980, "duration": 0.3, "volume": 0.4, "attack": 0.0005, "decay": 0.29, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 2.76, "index": 2.6, "index_end": 0.2}},
			{"wave": "square", "freq": 330, "freq_end": 990, "glide": "exp", "duration": 0.16, "volume": 0.25, "attack": 0.002, "decay": 0.15, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 3000}},
		]},
		"boss_rage": {"volume": 0.55, "normalize": true, "drive": 0.7, "reverb": {"mix": 0.2, "size": 0.7, "damp": 0.5}, "tail": 0.5, "layers": [
			{"wave": "saw", "freq": 86, "freq_end": 310, "glide": "exp", "duration": 0.8, "volume": 0.7, "attack": 0.03, "release": 0.12, "unison": 3, "detune": 28, "ring": {"freq": 31, "freq_end": 47, "mix": 0.8}, "filter": {"type": "lowpass", "cutoff": 700, "cutoff_end": 2800, "q": 2.0}},
			{"wave": "pink", "duration": 0.8, "volume": 0.3, "attack": 0.2, "release": 0.15, "filter": {"type": "bandpass", "cutoff": 500, "cutoff_end": 1800, "q": 1.0}},
		]},
		"boss_burst": GameSfx.preset("explosion_small", {"volume": 0.5}),
		"boss_down": GameSfx.preset("explosion_large", {"volume": 0.75}),
		"continue": {"volume": 0.4, "normalize": true, "reverb": {"mix": 0.25, "size": 0.6, "damp": 0.4}, "tail": 0.6, "layers": [
			{"wave": "triangle", "freq": 330, "steps": [1.0, 1.25, 1.5, 2.0], "duration": 0.6, "volume": 0.6, "attack": 0.004, "decay": 0.58, "sustain": 0.0, "curve": 0.7},
		]},
		"game_over": {"volume": 0.45, "normalize": true, "reverb": {"mix": 0.2, "size": 0.6, "damp": 0.5}, "tail": 0.5, "layers": [
			{"wave": "triangle", "freq": 300, "freq_end": 62, "glide": "exp", "duration": 0.9, "volume": 0.7, "attack": 0.006, "decay": 0.86, "sustain": 0.0, "curve": 0.9},
		]},
	}

## Register every effect, track and fanfare. Returns whether all the files loaded.
static func define_all(audio: GameAudio) -> bool:
	var specs := effects()
	for name: String in specs:
		audio.define(name, specs[name])
	var loaded := true
	for track: String in TRACKS:
		loaded = audio.load_music(track, DIR + str(TRACKS[track])) and loaded
	for stinger: String in STINGERS:
		loaded = audio.load_stinger(stinger, DIR + str(STINGERS[stinger])) and loaded
	return loaded
