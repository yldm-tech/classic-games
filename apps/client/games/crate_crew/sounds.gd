extends RefCounted

## Every sound of Crate Crew. Effects are specs for the shared synthesiser, one per event the world reports: library presets where one fits, layered definitions written for this game where the event is its own (a crate splintering, the Dustmaw breathing in, a robot powering down). Music and the short fanfares are recorded files in audio/.

const DIR := "res://games/crate_crew/audio/"

## Looping themes: the workbench and the foundry share the bright one, the shaft and the loft the darker one, both bosses the third.
const TRACKS := {
	"theme_bench": "theme_bench.ogg",
	"theme_shaft": "theme_shaft.ogg",
	"theme_boss": "theme_boss.ogg",
}
## One-shot fanfares. Their names differ from the effect names on purpose: GameAudio counts both in the same table.
const STINGERS := {
	"fanfare_clear": "fanfare_clear.ogg",
	"fanfare_won": "fanfare_won.ogg",
	"fanfare_lost": "fanfare_lost.ogg",
}

static func stage_track(stage: int) -> String:
	return "theme_bench" if stage % 2 == 0 else "theme_shaft"

static func effects() -> Dictionary:
	return {
		"jump": GameSfx.preset("jump", {"volume": 0.34}),
		"land": GameSfx.preset("land", {"volume": 0.3}),
		"lift": {"volume": 0.42, "normalize": true, "vary": {"pitch": 0.06}, "layers": [
			{"wave": "triangle", "freq": 210, "freq_end": 470, "glide": "exp", "duration": 0.13, "volume": 0.7, "attack": 0.004, "decay": 0.12, "sustain": 0.0},
			{"wave": "pulse", "duty": 0.3, "freq": 420, "freq_end": 940, "glide": "exp", "duration": 0.09, "volume": 0.22, "attack": 0.003, "decay": 0.085, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 2600}},
			{"wave": "pink", "duration": 0.06, "volume": 0.3, "attack": 0.002, "decay": 0.055, "sustain": 0.0, "filter": {"type": "bandpass", "cutoff": 900, "q": 0.9}},
		]},
		"put_down": GameSfx.preset("impact", {"volume": 0.34, "pitch": 1.35}),
		"throw": GameSfx.preset("whoosh", {"volume": 0.42, "pitch": 1.1}),
		"throw_up": GameSfx.preset("whoosh", {"volume": 0.42, "pitch": 1.5}),
		"break": {"volume": 0.62, "normalize": true, "drive": 0.25, "vary": {"pitch": 0.12}, "layers": [
			{"wave": "pink", "duration": 0.22, "volume": 0.9, "attack": 0.001, "decay": 0.21, "sustain": 0.0, "curve": 2.0, "filter": {"type": "bandpass", "cutoff": 1300, "cutoff_end": 500, "q": 0.8}},
			{"wave": "sine", "freq": 190, "freq_end": 70, "glide": "exp", "duration": 0.1, "volume": 0.7, "attack": 0.001, "decay": 0.095, "sustain": 0.0},
			{"wave": "white", "duration": 0.02, "volume": 0.6, "attack": 0.0005, "release": 0.018, "filter": {"type": "bandpass", "cutoff": 2400, "q": 2.0}},
			{"wave": "white", "start": 0.05, "duration": 0.025, "volume": 0.45, "attack": 0.0005, "release": 0.02, "filter": {"type": "bandpass", "cutoff": 1800, "q": 2.5}},
			{"wave": "white", "start": 0.11, "duration": 0.03, "volume": 0.3, "attack": 0.0005, "release": 0.025, "filter": {"type": "bandpass", "cutoff": 1500, "q": 2.5}},
			{"wave": "triangle", "freq": 640, "freq_end": 310, "glide": "exp", "duration": 0.06, "volume": 0.3, "attack": 0.001, "decay": 0.055, "sustain": 0.0},
		]},
		"clang": {"volume": 0.5, "normalize": true, "vary": {"pitch": 0.07}, "reverb": {"mix": 0.18, "size": 0.4, "damp": 0.4}, "tail": 0.3, "layers": [
			{"wave": "sine", "freq": 1240, "duration": 0.3, "volume": 0.6, "attack": 0.0005, "decay": 0.29, "sustain": 0.0, "curve": 2.2, "fm": {"ratio": 2.76, "index": 3.0, "index_end": 0.3}},
			{"wave": "sine", "freq": 1870, "duration": 0.22, "volume": 0.35, "attack": 0.0005, "decay": 0.21, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 1.41, "index": 2.0, "index_end": 0.1}},
			{"wave": "white", "duration": 0.015, "volume": 0.5, "attack": 0.0005, "release": 0.012, "filter": {"type": "highpass", "cutoff": 3000}},
		]},
		"poof": {"volume": 0.3, "normalize": true, "vary": {"pitch": 0.1}, "layers": [
			{"wave": "pink", "duration": 0.16, "volume": 0.8, "attack": 0.004, "decay": 0.15, "sustain": 0.0, "curve": 1.6, "filter": {"type": "lowpass", "cutoff": 2200, "cutoff_end": 400, "q": 0.7}},
		]},
		"thud": GameSfx.preset("impact", {"volume": 0.5, "pitch": 0.8}),
		"foe_hit": GameSfx.preset("impact", {"volume": 0.5, "pitch": 1.5}),
		"foe_out": GameSfx.preset("explosion_small", {"volume": 0.55, "pitch": 1.35}),
		"hop": GameSfx.preset("bounce", {"volume": 0.28}),
		"shot": GameSfx.preset("shot_laser", {"volume": 0.34, "pitch": 0.85}),
		"drop": {"volume": 0.36, "normalize": true, "layers": [
			{"wave": "sine", "freq": 1250, "freq_end": 330, "glide": "exp", "duration": 0.28, "volume": 0.7, "attack": 0.01, "decay": 0.26, "sustain": 0.0, "curve": 0.8, "vibrato": {"rate": 22, "depth": 0.4}},
			{"wave": "triangle", "freq": 625, "freq_end": 165, "glide": "exp", "duration": 0.24, "volume": 0.25, "attack": 0.01, "decay": 0.22, "sustain": 0.0},
		]},
		"rev": {"volume": 0.45, "normalize": true, "drive": 0.5, "layers": [
			{"wave": "saw", "freq": 62, "freq_end": 230, "glide": "exp", "duration": 0.46, "volume": 0.7, "attack": 0.02, "release": 0.06, "unison": 2, "detune": 22, "ring": {"freq": 24, "freq_end": 58, "mix": 0.7}, "filter": {"type": "lowpass", "cutoff": 500, "cutoff_end": 2600, "q": 1.6}},
			{"wave": "pink", "duration": 0.46, "volume": 0.25, "attack": 0.1, "release": 0.08, "filter": {"type": "bandpass", "cutoff": 600, "cutoff_end": 2200, "q": 1.2}},
		]},
		"hurt": GameSfx.preset("hurt", {"volume": 0.5}),
		"die": {"volume": 0.55, "normalize": true, "drive": 0.2, "reverb": {"mix": 0.15, "size": 0.5, "damp": 0.5}, "tail": 0.4, "layers": [
			{"wave": "saw", "freq": 560, "freq_end": 52, "glide": "exp", "duration": 0.75, "volume": 0.6, "attack": 0.004, "decay": 0.7, "sustain": 0.0, "curve": 0.9, "unison": 2, "detune": 16, "filter": {"type": "lowpass", "cutoff": 3600, "cutoff_end": 220, "q": 1.4}},
			{"wave": "square", "freq": 880, "steps": [1.0, 0.75, 0.6, 0.5, 0.375], "duration": 0.5, "volume": 0.25, "attack": 0.002, "decay": 0.48, "sustain": 0.0},
			{"wave": "pink", "duration": 0.12, "volume": 0.5, "attack": 0.001, "decay": 0.11, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 1800}},
		]},
		"respawn": GameSfx.preset("power_up", {"volume": 0.36, "pitch": 1.2, "speed": 1.5}),
		"gear": GameSfx.preset("coin", {"volume": 0.3}),
		"battery": GameSfx.preset("pickup", {"volume": 0.45, "pitch": 0.9}),
		"core": GameSfx.preset("extra_life", {"volume": 0.5}),
		"cog": GameSfx.preset("coin", {"volume": 0.5, "pitch": 1.25, "delay": {"time": 0.11, "feedback": 0.45, "mix": 0.4}, "reverb": {"mix": 0.25, "size": 0.6, "damp": 0.3}, "tail": 0.8}),
		"flag": GameSfx.preset("ui_confirm", {"volume": 0.45, "reverb": {"mix": 0.2, "size": 0.5, "damp": 0.4}, "tail": 0.4}),
		"chute": GameSfx.preset("door", {"volume": 0.3, "pitch": 1.3}),
		"stage_start": {"volume": 0.4, "normalize": true, "reverb": {"mix": 0.22, "size": 0.55, "damp": 0.4}, "tail": 0.5, "layers": [
			{"wave": "triangle", "freq": 392, "steps": [1.0, 1.5], "duration": 0.32, "volume": 0.6, "attack": 0.004, "decay": 0.3, "sustain": 0.0, "curve": 0.8},
			{"wave": "sine", "freq": 784, "steps": [1.0, 1.5], "duration": 0.32, "volume": 0.3, "attack": 0.004, "decay": 0.3, "sustain": 0.0},
		]},
		"stage_clear": {"volume": 0.3, "normalize": true, "reverb": {"mix": 0.3, "size": 0.7, "damp": 0.3}, "tail": 0.7, "layers": [
			{"wave": "sine", "freq": 1568, "steps": [1.0, 1.25, 1.5, 2.0, 2.5, 3.0], "duration": 0.5, "volume": 0.5, "attack": 0.002, "decay": 0.48, "sustain": 0.0, "curve": 0.7},
			{"wave": "white", "duration": 0.5, "volume": 0.15, "attack": 0.1, "decay": 0.4, "sustain": 0.0, "filter": {"type": "highpass", "cutoff": 6000}},
		]},
		"boss_start": {"volume": 0.6, "normalize": true, "drive": 0.4, "reverb": {"mix": 0.3, "size": 0.85, "damp": 0.5}, "tail": 0.8, "layers": [
			{"wave": "saw", "freq": 110, "freq_end": 52, "glide": "exp", "duration": 1.1, "volume": 0.6, "attack": 0.01, "decay": 1.05, "sustain": 0.0, "curve": 1.2, "unison": 3, "detune": 25, "filter": {"type": "lowpass", "cutoff": 1800, "cutoff_end": 300, "q": 1.2}},
			{"wave": "pink", "duration": 0.9, "volume": 0.5, "attack": 0.002, "decay": 0.88, "sustain": 0.0, "curve": 2.0, "filter": {"type": "lowpass", "cutoff": 900, "cutoff_end": 200}},
			{"wave": "sine", "freq": 70, "freq_end": 34, "glide": "exp", "duration": 0.5, "volume": 0.7, "attack": 0.001, "decay": 0.48, "sustain": 0.0},
		]},
		"boss_spit": GameSfx.preset("shot_heavy", {"volume": 0.5, "pitch": 1.2}),
		"boss_inhale": {"volume": 0.34, "normalize": true, "layers": [
			{"wave": "pink", "duration": 1.6, "volume": 0.8, "attack": 0.35, "release": 0.4, "ring": {"freq": 13, "freq_end": 21, "mix": 0.35}, "filter": {"type": "bandpass", "cutoff": 320, "cutoff_end": 2600, "q": 2.2}},
			{"wave": "saw", "freq": 82, "freq_end": 140, "duration": 1.6, "volume": 0.3, "attack": 0.4, "release": 0.4, "unison": 2, "detune": 30, "filter": {"type": "lowpass", "cutoff": 500}},
		]},
		"boss_charge": {"volume": 0.5, "normalize": true, "drive": 0.5, "layers": [
			{"wave": "saw", "freq": 120, "freq_end": 430, "glide": "exp", "duration": 0.5, "volume": 0.7, "attack": 0.01, "release": 0.08, "unison": 2, "detune": 20, "ring": {"freq": 38, "freq_end": 84, "mix": 0.6}, "filter": {"type": "lowpass", "cutoff": 900, "cutoff_end": 3600, "q": 1.4}},
			{"wave": "white", "duration": 0.5, "volume": 0.2, "attack": 0.2, "release": 0.1, "filter": {"type": "bandpass", "cutoff": 1200, "cutoff_end": 3000, "q": 1.0}},
		]},
		"boss_slam": GameSfx.preset("explosion_small", {"volume": 0.72, "pitch": 0.7}),
		"boss_hit": {"volume": 0.6, "normalize": true, "drive": 0.3, "reverb": {"mix": 0.15, "size": 0.4, "damp": 0.4}, "tail": 0.3, "layers": [
			{"wave": "sine", "freq": 180, "freq_end": 52, "glide": "exp", "duration": 0.2, "volume": 0.8, "attack": 0.001, "decay": 0.19, "sustain": 0.0},
			{"wave": "sine", "freq": 980, "duration": 0.3, "volume": 0.4, "attack": 0.0005, "decay": 0.29, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 2.76, "index": 2.6, "index_end": 0.2}},
			{"wave": "square", "freq": 330, "freq_end": 990, "glide": "exp", "duration": 0.16, "volume": 0.25, "attack": 0.002, "decay": 0.15, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 3000}},
			{"wave": "pink", "duration": 0.1, "volume": 0.6, "attack": 0.001, "decay": 0.09, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 3000, "cutoff_end": 600}},
		]},
		"boss_angry": {"volume": 0.55, "normalize": true, "drive": 0.7, "reverb": {"mix": 0.2, "size": 0.7, "damp": 0.5}, "tail": 0.5, "layers": [
			{"wave": "saw", "freq": 86, "freq_end": 310, "glide": "exp", "duration": 0.8, "volume": 0.7, "attack": 0.03, "release": 0.12, "unison": 3, "detune": 28, "ring": {"freq": 31, "freq_end": 47, "mix": 0.8}, "filter": {"type": "lowpass", "cutoff": 700, "cutoff_end": 2800, "q": 2.0}},
			{"wave": "pink", "duration": 0.8, "volume": 0.3, "attack": 0.2, "release": 0.15, "filter": {"type": "bandpass", "cutoff": 500, "cutoff_end": 1800, "q": 1.0}},
		]},
		"boss_burst": GameSfx.preset("explosion_small", {"volume": 0.5}),
		"boss_down": GameSfx.preset("explosion_large", {"volume": 0.75}),
		"continue": {"volume": 0.4, "normalize": true, "reverb": {"mix": 0.25, "size": 0.6, "damp": 0.4}, "tail": 0.6, "layers": [
			{"wave": "triangle", "freq": 330, "steps": [1.0, 1.25, 1.5, 2.0], "duration": 0.6, "volume": 0.6, "attack": 0.004, "decay": 0.58, "sustain": 0.0, "curve": 0.7},
			{"wave": "sine", "freq": 660, "steps": [1.0, 1.25, 1.5, 2.0], "duration": 0.6, "volume": 0.25, "attack": 0.004, "decay": 0.58, "sustain": 0.0},
		]},
		"game_over": {"volume": 0.45, "normalize": true, "reverb": {"mix": 0.2, "size": 0.6, "damp": 0.5}, "tail": 0.5, "layers": [
			{"wave": "triangle", "freq": 300, "freq_end": 62, "glide": "exp", "duration": 0.9, "volume": 0.7, "attack": 0.006, "decay": 0.86, "sustain": 0.0, "curve": 0.9},
			{"wave": "pink", "duration": 0.2, "volume": 0.4, "attack": 0.002, "decay": 0.19, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 700}},
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
