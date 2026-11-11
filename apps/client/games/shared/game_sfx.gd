class_name GameSfx
extends RefCounted

## Ready-made sound effects for GameSynth: specs a game passes to GameAudio.define() as they are, or after changing a few values.
##   audio.define("coin", GameSfx.preset("coin"))
##   audio.define("big_jump", GameSfx.preset("jump", {"volume": 0.4, "pitch": 0.8}))
## The second argument overrides top-level keys of the spec (volume, drive, delay, reverb, tail, vary, layers); two extra keys shape the whole effect without touching its layers: "pitch" multiplies every frequency in it, and "speed" divides every time in it (2 plays the same shape in half the time).
## Every preset is normalised, so `volume` is its peak level, and carries a small random pitch variation per play where repeating the effect exactly would sound mechanical.

const PRESETS := {
	# ---- hits and explosions ----
	"impact": {"volume": 0.6, "normalize": true, "drive": 0.25, "vary": {"pitch": 0.08}, "layers": [
		{"wave": "sine", "freq": 170, "freq_end": 46, "glide": "exp", "glide_time": 0.6, "duration": 0.2, "volume": 0.7, "attack": 0.001, "decay": 0.19, "sustain": 0.0, "curve": 1.6},
		{"wave": "triangle", "freq": 520, "freq_end": 140, "glide": "exp", "duration": 0.07, "volume": 0.45, "attack": 0.001, "decay": 0.065, "sustain": 0.0, "curve": 1.5},
		{"wave": "pink", "duration": 0.1, "volume": 0.7, "attack": 0.001, "decay": 0.09, "sustain": 0.0, "curve": 2.0, "filter": {"type": "lowpass", "cutoff": 4000, "cutoff_end": 600, "q": 0.8}},
		{"wave": "white", "duration": 0.014, "volume": 0.35, "attack": 0.0005, "release": 0.012, "filter": {"type": "highpass", "cutoff": 2500}},
	]},
	"explosion_small": {"volume": 0.65, "normalize": true, "drive": 0.45, "vary": {"pitch": 0.1}, "reverb": {"mix": 0.16, "size": 0.45, "damp": 0.5}, "tail": 0.35, "layers": [
		{"wave": "pink", "duration": 0.48, "volume": 0.9, "attack": 0.001, "decay": 0.46, "sustain": 0.0, "curve": 2.2, "filter": {"type": "lowpass", "cutoff": 6000, "cutoff_end": 500, "q": 0.7}},
		{"wave": "sine", "freq": 120, "freq_end": 38, "glide": "exp", "duration": 0.36, "volume": 0.45, "attack": 0.001, "decay": 0.35, "sustain": 0.0, "curve": 1.5},
		{"wave": "white", "duration": 0.06, "volume": 0.6, "attack": 0.0005, "decay": 0.058, "sustain": 0.0, "curve": 1.5, "filter": {"type": "highpass", "cutoff": 1500}},
		{"wave": "noise", "freq": 2600, "freq_end": 300, "glide": "exp", "duration": 0.22, "volume": 0.3, "attack": 0.001, "decay": 0.21, "sustain": 0.0, "curve": 2.0},
	]},
	"explosion_large": {"volume": 0.75, "normalize": true, "drive": 0.6, "vary": {"pitch": 0.08}, "reverb": {"mix": 0.28, "size": 0.85, "damp": 0.55}, "tail": 0.7, "layers": [
		{"wave": "pink", "duration": 1.2, "volume": 0.9, "attack": 0.001, "decay": 1.15, "sustain": 0.0, "curve": 2.4, "filter": {"type": "lowpass", "cutoff": 5000, "cutoff_end": 250, "q": 0.7}},
		{"wave": "sine", "freq": 86, "freq_end": 26, "glide": "exp", "duration": 0.95, "volume": 0.5, "attack": 0.002, "decay": 0.9, "sustain": 0.0, "curve": 1.4},
		{"wave": "white", "duration": 0.9, "volume": 0.5, "attack": 0.01, "decay": 0.85, "sustain": 0.0, "curve": 1.8, "ring": {"freq": 27, "freq_end": 9, "mix": 0.9}, "filter": {"type": "bandpass", "cutoff": 2400, "cutoff_end": 700, "q": 1.2}},
		{"wave": "white", "duration": 0.08, "volume": 0.6, "attack": 0.0005, "decay": 0.078, "sustain": 0.0, "curve": 1.5, "filter": {"type": "highpass", "cutoff": 1200}},
		{"wave": "noise", "freq": 3200, "freq_end": 240, "glide": "exp", "duration": 0.3, "volume": 0.3, "attack": 0.001, "decay": 0.29, "sustain": 0.0, "curve": 2.0},
	]},
	"crumble": {"volume": 0.55, "normalize": true, "drive": 0.2, "vary": {"pitch": 0.12}, "reverb": {"mix": 0.12, "size": 0.35, "damp": 0.6}, "tail": 0.25, "layers": [
		{"wave": "white", "duration": 0.62, "volume": 0.8, "attack": 0.004, "decay": 0.6, "sustain": 0.0, "curve": 1.6, "ring": {"freq": 34, "freq_end": 11, "mix": 1.0}, "filter": {"type": "lowpass", "cutoff": 5000, "cutoff_end": 900, "q": 0.9}},
		{"wave": "noise", "freq": 1100, "freq_end": 160, "glide": "exp", "duration": 0.5, "volume": 0.4, "attack": 0.002, "decay": 0.48, "sustain": 0.0, "curve": 1.5},
		{"wave": "sine", "freq": 140, "freq_end": 60, "glide": "exp", "duration": 0.12, "volume": 0.4, "attack": 0.001, "decay": 0.11, "sustain": 0.0, "curve": 1.8},
		{"wave": "sine", "freq": 110, "freq_end": 50, "glide": "exp", "start": 0.19, "duration": 0.12, "volume": 0.3, "attack": 0.001, "decay": 0.11, "sustain": 0.0, "curve": 1.8},
		{"wave": "sine", "freq": 95, "freq_end": 44, "glide": "exp", "start": 0.37, "duration": 0.14, "volume": 0.25, "attack": 0.001, "decay": 0.13, "sustain": 0.0, "curve": 1.8},
	]},
	"break": {"volume": 0.65, "normalize": true, "vary": {"pitch": 0.1}, "layers": [
		{"wave": "white", "duration": 0.2, "volume": 0.7, "attack": 0.0005, "decay": 0.19, "sustain": 0.0, "curve": 2.4, "filter": {"type": "highpass", "cutoff": 1800, "cutoff_end": 4200, "q": 0.8}},
		{"wave": "sine", "freq": 2350, "duration": 0.24, "volume": 0.35, "attack": 0.0005, "decay": 0.23, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 2.76, "index": 2.4, "index_end": 0.2}},
		{"wave": "sine", "freq": 3520, "start": 0.03, "duration": 0.2, "volume": 0.25, "attack": 0.0005, "decay": 0.19, "sustain": 0.0, "curve": 2.0, "fm": {"ratio": 1.41, "index": 1.8, "index_end": 0.1}},
		{"wave": "sine", "freq": 210, "freq_end": 90, "glide": "exp", "duration": 0.07, "volume": 0.5, "attack": 0.0005, "decay": 0.065, "sustain": 0.0},
	]},
	# ---- shots ----
	"shot_laser": {"volume": 0.6, "normalize": true, "vary": {"pitch": 0.05}, "layers": [
		{"wave": "saw", "freq": 1900, "freq_end": 240, "glide": "exp", "duration": 0.17, "volume": 0.6, "attack": 0.001, "decay": 0.16, "sustain": 0.0, "curve": 1.3, "unison": 2, "detune": 18, "filter": {"type": "lowpass", "cutoff": 7000, "cutoff_end": 1100, "q": 1.4}},
		{"wave": "sine", "freq": 2700, "freq_end": 480, "glide": "exp", "duration": 0.12, "volume": 0.4, "attack": 0.001, "decay": 0.11, "sustain": 0.0, "fm": {"ratio": 0.5, "index": 2.0, "index_end": 0.0}},
	]},
	"shot_blaster": {"volume": 0.55, "normalize": true, "drive": 0.2, "vary": {"pitch": 0.06}, "layers": [
		{"wave": "square", "freq": 640, "freq_end": 130, "glide": "exp", "duration": 0.13, "volume": 0.6, "attack": 0.001, "decay": 0.12, "sustain": 0.0, "curve": 1.4, "filter": {"type": "lowpass", "cutoff": 5200, "cutoff_end": 900, "q": 1.0}},
		{"wave": "white", "duration": 0.04, "volume": 0.45, "attack": 0.0005, "decay": 0.038, "sustain": 0.0, "curve": 2.0, "filter": {"type": "bandpass", "cutoff": 3200, "q": 0.9}},
		{"wave": "sine", "freq": 190, "freq_end": 70, "glide": "exp", "duration": 0.09, "volume": 0.5, "attack": 0.001, "decay": 0.085, "sustain": 0.0},
	]},
	"shot_heavy": {"volume": 0.65, "normalize": true, "drive": 0.5, "vary": {"pitch": 0.07}, "reverb": {"mix": 0.12, "size": 0.4, "damp": 0.5}, "tail": 0.25, "layers": [
		{"wave": "pink", "duration": 0.26, "volume": 0.9, "attack": 0.001, "decay": 0.25, "sustain": 0.0, "curve": 2.2, "filter": {"type": "lowpass", "cutoff": 7000, "cutoff_end": 700, "q": 0.8}},
		{"wave": "sine", "freq": 165, "freq_end": 44, "glide": "exp", "duration": 0.28, "volume": 0.5, "attack": 0.001, "decay": 0.27, "sustain": 0.0, "curve": 1.4},
		{"wave": "white", "duration": 0.03, "volume": 0.7, "attack": 0.0005, "release": 0.026, "filter": {"type": "highpass", "cutoff": 2200}},
	]},
	"shot_light": {"volume": 0.4, "normalize": true, "vary": {"pitch": 0.06}, "layers": [
		{"wave": "triangle", "freq": 1500, "freq_end": 620, "glide": "exp", "duration": 0.075, "volume": 0.7, "attack": 0.001, "decay": 0.07, "sustain": 0.0},
		{"wave": "white", "duration": 0.02, "volume": 0.25, "attack": 0.0005, "release": 0.018, "filter": {"type": "bandpass", "cutoff": 4200, "q": 1.2}},
	]},
	"zap": {"volume": 0.6, "normalize": true, "vary": {"pitch": 0.08}, "layers": [
		{"wave": "saw", "freq": 880, "freq_end": 220, "glide": "exp", "duration": 0.22, "volume": 0.5, "attack": 0.001, "decay": 0.21, "sustain": 0.0, "ring": {"freq": 96, "freq_end": 41, "mix": 1.0}, "filter": {"type": "bandpass", "cutoff": 2600, "cutoff_end": 900, "q": 2.0}},
		{"wave": "white", "duration": 0.2, "volume": 0.4, "attack": 0.001, "decay": 0.19, "sustain": 0.0, "ring": {"freq": 63, "mix": 1.0}, "filter": {"type": "highpass", "cutoff": 3200}},
	]},
	# ---- movement ----
	"jump": {"volume": 0.45, "normalize": true, "vary": {"pitch": 0.04}, "layers": [
		{"wave": "sine", "freq": 250, "freq_end": 640, "glide": "exp", "duration": 0.17, "volume": 0.7, "attack": 0.006, "decay": 0.16, "sustain": 0.0, "curve": 0.8},
		{"wave": "triangle", "freq": 500, "freq_end": 1280, "glide": "exp", "duration": 0.13, "volume": 0.25, "attack": 0.004, "decay": 0.12, "sustain": 0.0},
		{"wave": "pink", "duration": 0.05, "volume": 0.2, "attack": 0.002, "decay": 0.045, "sustain": 0.0, "filter": {"type": "bandpass", "cutoff": 1400, "q": 0.8}},
	]},
	"land": {"volume": 0.45, "normalize": true, "vary": {"pitch": 0.1}, "layers": [
		{"wave": "sine", "freq": 150, "freq_end": 58, "glide": "exp", "duration": 0.11, "volume": 0.8, "attack": 0.001, "decay": 0.1, "sustain": 0.0, "curve": 1.5},
		{"wave": "pink", "duration": 0.09, "volume": 0.5, "attack": 0.001, "decay": 0.085, "sustain": 0.0, "curve": 1.8, "filter": {"type": "lowpass", "cutoff": 1100, "cutoff_end": 240, "q": 0.7}},
	]},
	"bounce": {"volume": 0.45, "normalize": true, "vary": {"pitch": 0.06}, "layers": [
		{"wave": "sine", "freq": 210, "freq_end": 520, "glide": "exp", "glide_time": 0.35, "duration": 0.14, "volume": 0.8, "attack": 0.002, "decay": 0.13, "sustain": 0.0},
		{"wave": "triangle", "freq": 420, "freq_end": 1040, "glide": "exp", "glide_time": 0.35, "duration": 0.09, "volume": 0.2, "attack": 0.002, "decay": 0.085, "sustain": 0.0},
	]},
	"whoosh": {"volume": 0.5, "normalize": true, "vary": {"pitch": 0.1}, "layers": [
		{"wave": "white", "duration": 0.34, "volume": 0.8, "attack": 0.14, "release": 0.2, "curve": 1.5, "filter": {"type": "bandpass", "cutoff": 700, "cutoff_end": 4200, "q": 1.6}},
		{"wave": "pink", "duration": 0.34, "volume": 0.25, "attack": 0.16, "release": 0.18, "curve": 1.5, "filter": {"type": "lowpass", "cutoff": 900, "cutoff_end": 2600, "q": 0.7}},
	]},
	"splash": {"volume": 0.6, "normalize": true, "vary": {"pitch": 0.1}, "reverb": {"mix": 0.18, "size": 0.4, "damp": 0.3}, "tail": 0.3, "layers": [
		{"wave": "white", "duration": 0.42, "volume": 0.9, "attack": 0.004, "decay": 0.4, "sustain": 0.0, "curve": 1.8, "filter": {"type": "bandpass", "cutoff": 1200, "cutoff_end": 4200, "q": 1.1}},
		{"wave": "pink", "duration": 0.5, "volume": 0.35, "attack": 0.01, "decay": 0.48, "sustain": 0.0, "curve": 1.6, "filter": {"type": "lowpass", "cutoff": 2500, "cutoff_end": 600, "q": 0.7}},
		{"wave": "sine", "freq": 330, "freq_end": 110, "glide": "exp", "duration": 0.09, "volume": 0.25, "attack": 0.001, "decay": 0.085, "sustain": 0.0},
		{"wave": "sine", "freq": 520, "freq_end": 1500, "glide": "exp", "start": 0.12, "duration": 0.06, "volume": 0.25, "attack": 0.003, "decay": 0.055, "sustain": 0.0},
		{"wave": "sine", "freq": 700, "freq_end": 1900, "glide": "exp", "start": 0.21, "duration": 0.05, "volume": 0.18, "attack": 0.003, "decay": 0.045, "sustain": 0.0},
	]},
	"door": {"volume": 0.55, "normalize": true, "drive": 0.15, "reverb": {"mix": 0.22, "size": 0.6, "damp": 0.5}, "tail": 0.45, "layers": [
		{"wave": "pink", "duration": 0.46, "volume": 0.7, "attack": 0.05, "release": 0.08, "ring": {"freq": 19, "freq_end": 31, "mix": 0.7}, "filter": {"type": "bandpass", "cutoff": 380, "cutoff_end": 620, "q": 3.0}},
		{"wave": "saw", "freq": 95, "freq_end": 140, "duration": 0.46, "volume": 0.3, "attack": 0.05, "release": 0.08, "filter": {"type": "lowpass", "cutoff": 1100, "q": 1.0}},
		{"wave": "sine", "freq": 130, "freq_end": 48, "glide": "exp", "start": 0.46, "duration": 0.2, "volume": 0.6, "attack": 0.001, "decay": 0.19, "sustain": 0.0, "curve": 1.6},
		{"wave": "pink", "start": 0.46, "duration": 0.09, "volume": 0.7, "attack": 0.001, "decay": 0.085, "sustain": 0.0, "curve": 2.0, "filter": {"type": "lowpass", "cutoff": 3600, "cutoff_end": 500, "q": 0.8}},
	]},
	# ---- rewards ----
	"pickup": {"volume": 0.42, "normalize": true, "vary": {"pitch": 0.03}, "layers": [
		{"wave": "sine", "freq": 880, "steps": [1.0, 1.5], "duration": 0.15, "volume": 0.7, "attack": 0.002, "decay": 0.14, "sustain": 0.25, "release": 0.04, "fm": {"ratio": 2.0, "index": 1.2, "index_end": 0.1}},
		{"wave": "triangle", "freq": 1760, "steps": [1.0, 1.5], "duration": 0.15, "volume": 0.2, "attack": 0.002, "decay": 0.12, "sustain": 0.0},
	]},
	"coin": {"volume": 0.42, "normalize": true, "vary": {"pitch": 0.02}, "delay": {"time": 0.085, "feedback": 0.25, "mix": 0.16}, "tail": 0.25, "layers": [
		{"wave": "sine", "freq": 1245, "steps": [1.0, 1.0, 1.335, 1.335, 1.335, 1.335, 1.335], "duration": 0.34, "volume": 0.7, "attack": 0.001, "decay": 0.33, "sustain": 0.0, "curve": 1.3, "fm": {"ratio": 3.5, "index": 1.4, "index_end": 0.0}},
		{"wave": "sine", "freq": 2490, "steps": [1.0, 1.0, 1.335, 1.335, 1.335, 1.335, 1.335], "duration": 0.22, "volume": 0.25, "attack": 0.001, "decay": 0.21, "sustain": 0.0, "curve": 1.6},
		{"wave": "white", "duration": 0.012, "volume": 0.2, "attack": 0.0005, "release": 0.01, "filter": {"type": "highpass", "cutoff": 5000}},
	]},
	"power_up": {"volume": 0.48, "normalize": true, "delay": {"time": 0.09, "feedback": 0.4, "mix": 0.22}, "reverb": {"mix": 0.14, "size": 0.5, "damp": 0.3}, "tail": 0.6, "layers": [
		{"wave": "triangle", "freq": 392, "steps": [1.0, 1.26, 1.5, 2.0, 2.52, 3.0, 4.0], "duration": 0.56, "volume": 0.7, "attack": 0.003, "release": 0.14},
		{"wave": "pulse", "duty": 0.3, "duty_end": 0.5, "freq": 784, "steps": [1.0, 1.26, 1.5, 2.0, 2.52, 3.0, 4.0], "duration": 0.56, "volume": 0.22, "attack": 0.003, "release": 0.14, "unison": 2, "detune": 14, "filter": {"type": "lowpass", "cutoff": 1800, "cutoff_end": 7000, "q": 0.9}},
		{"wave": "sine", "freq": 196, "freq_end": 392, "glide": "exp", "duration": 0.56, "volume": 0.3, "attack": 0.01, "release": 0.14},
	]},
	"extra_life": {"volume": 0.48, "normalize": true, "delay": {"time": 0.11, "feedback": 0.3, "mix": 0.2}, "reverb": {"mix": 0.12, "size": 0.5, "damp": 0.3}, "tail": 0.5, "layers": [
		{"wave": "sine", "freq": 659, "steps": [1.0, 1.26, 1.5, 1.26, 1.5, 2.0, 2.0, 2.0], "duration": 0.72, "volume": 0.7, "attack": 0.002, "release": 0.2, "fm": {"ratio": 2.0, "index": 0.9, "index_end": 0.3}},
		{"wave": "triangle", "freq": 1318, "steps": [1.0, 1.26, 1.5, 1.26, 1.5, 2.0, 2.0, 2.0], "duration": 0.72, "volume": 0.2, "attack": 0.002, "release": 0.2},
	]},
	"hurt": {"volume": 0.5, "normalize": true, "drive": 0.3, "vary": {"pitch": 0.06}, "layers": [
		{"wave": "saw", "freq": 430, "freq_end": 105, "glide": "exp", "duration": 0.25, "volume": 0.6, "attack": 0.002, "decay": 0.24, "sustain": 0.0, "curve": 1.2, "ring": {"freq": 58, "mix": 0.55}, "filter": {"type": "lowpass", "cutoff": 2800, "cutoff_end": 600, "q": 1.2}},
		{"wave": "square", "freq": 215, "freq_end": 52, "glide": "exp", "duration": 0.25, "volume": 0.3, "attack": 0.002, "decay": 0.24, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 1400, "q": 0.8}},
		{"wave": "white", "duration": 0.05, "volume": 0.4, "attack": 0.0005, "decay": 0.048, "sustain": 0.0, "curve": 2.0, "filter": {"type": "bandpass", "cutoff": 1900, "q": 0.9}},
	]},
	# ---- interface ----
	"ui_move": {"volume": 0.3, "normalize": true, "layers": [
		{"wave": "sine", "freq": 1250, "duration": 0.04, "volume": 0.7, "attack": 0.001, "decay": 0.038, "sustain": 0.0, "curve": 1.5},
		{"wave": "triangle", "freq": 625, "duration": 0.03, "volume": 0.3, "attack": 0.001, "decay": 0.028, "sustain": 0.0},
	]},
	"ui_confirm": {"volume": 0.38, "normalize": true, "delay": {"time": 0.07, "feedback": 0.2, "mix": 0.12}, "tail": 0.18, "layers": [
		{"wave": "sine", "freq": 784, "steps": [1.0, 1.5], "duration": 0.13, "volume": 0.7, "attack": 0.001, "decay": 0.12, "sustain": 0.2, "release": 0.03, "fm": {"ratio": 2.0, "index": 0.8, "index_end": 0.0}},
		{"wave": "triangle", "freq": 1568, "steps": [1.0, 1.5], "duration": 0.1, "volume": 0.2, "attack": 0.001, "decay": 0.09, "sustain": 0.0},
	]},
	"ui_cancel": {"volume": 0.34, "normalize": true, "layers": [
		{"wave": "sine", "freq": 660, "steps": [1.0, 0.749], "duration": 0.13, "volume": 0.7, "attack": 0.001, "decay": 0.12, "sustain": 0.2, "release": 0.03, "fm": {"ratio": 1.0, "index": 0.6, "index_end": 0.0}},
		{"wave": "triangle", "freq": 330, "steps": [1.0, 0.749], "duration": 0.11, "volume": 0.25, "attack": 0.001, "decay": 0.1, "sustain": 0.0},
	]},
}

## Keys of a layer that are times in seconds, and the keys that are frequencies in Hz: what "speed" and "pitch" rescale.
const _TIMES := ["start", "duration", "attack", "decay", "release"]
const _PITCHES := ["freq", "freq_end"]

static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in PRESETS:
		out.append(key)
	return out

static func has(preset_name: String) -> bool:
	return PRESETS.has(preset_name)

## A copy of a preset's spec with `overrides` applied, ready for GameAudio.define(). An unknown name gives a quiet click and reports the mistake, so a typo is heard about once and never crashes a game.
static func preset(preset_name: String, overrides: Dictionary = {}) -> Dictionary:
	if not PRESETS.has(preset_name):
		push_error("GameSfx: there is no preset \"%s\"" % preset_name)
		return {"wave": "sine", "freq": 440, "duration": 0.03, "volume": 0.1}
	var spec: Dictionary = (PRESETS[preset_name] as Dictionary).duplicate(true)
	var pitch := maxf(0.05, float(overrides.get("pitch", 1.0)))
	var speed := maxf(0.05, float(overrides.get("speed", 1.0)))
	for key: String in overrides:
		if key != "pitch" and key != "speed":
			spec[key] = overrides[key] if not overrides[key] is Dictionary and not overrides[key] is Array else overrides[key].duplicate(true)
	if not is_equal_approx(pitch, 1.0) or not is_equal_approx(speed, 1.0):
		for layer: Dictionary in spec["layers"]:
			for key: String in _PITCHES:
				if layer.has(key):
					layer[key] = float(layer[key]) * pitch
			for key: String in _TIMES:
				if layer.has(key):
					layer[key] = float(layer[key]) / speed
			for part: String in ["ring", "filter"]:
				if layer.get(part) is Dictionary:
					for key: String in ["freq", "freq_end", "cutoff", "cutoff_end"]:
						if (layer[part] as Dictionary).has(key):
							layer[part][key] = float(layer[part][key]) * pitch
		if spec.has("tail"):
			spec["tail"] = float(spec["tail"]) / speed
	return spec
