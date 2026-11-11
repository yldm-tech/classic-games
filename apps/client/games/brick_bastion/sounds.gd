extends RefCounted

## The sound of Brick Bastion: every effect and the three tunes, all synthesised by the shared procedural audio. Nothing here is a recording.

const EFFECTS := {
	"fire": {"wave": "square", "freq": 720, "freq_end": 240, "duration": 0.09, "volume": 0.34},
	"raider_fire": {"wave": "pulse", "duty": 0.3, "freq": 420, "freq_end": 150, "duration": 0.1, "volume": 0.2},
	"boss_fire": {"wave": "saw", "freq": 300, "freq_end": 90, "duration": 0.16, "volume": 0.34},
	"volley": {"wave": "noise", "freq": 2400, "freq_end": 300, "duration": 0.4, "volume": 0.5, "release": 0.2},
	"charge": {"wave": "saw", "freq": 110, "freq_end": 660, "duration": 0.7, "volume": 0.3, "attack": 0.2},
	"brick_hit": {"wave": "noise", "freq": 1800, "freq_end": 900, "duration": 0.06, "volume": 0.26},
	"brick_break": {"wave": "noise", "freq": 1400, "freq_end": 260, "duration": 0.16, "volume": 0.36, "release": 0.1},
	"plate_hit": {"wave": "triangle", "freq": 1900, "freq_end": 1500, "duration": 0.07, "volume": 0.3},
	"plate_break": {"wave": "pulse", "duty": 0.15, "freq": 1300, "freq_end": 200, "duration": 0.22, "volume": 0.36},
	"clank": {"wave": "pulse", "duty": 0.12, "freq": 900, "freq_end": 500, "duration": 0.08, "volume": 0.3},
	"deflect": {"wave": "triangle", "freq": 1500, "freq_end": 2200, "duration": 0.06, "volume": 0.26},
	"boom": {"wave": "noise", "freq": 900, "freq_end": 90, "duration": 0.32, "volume": 0.5, "release": 0.2},
	"boom_big": {"wave": "noise", "freq": 600, "freq_end": 50, "duration": 0.55, "volume": 0.6, "release": 0.3},
	"rover_down": {"wave": "saw", "freq": 520, "freq_end": 50, "duration": 0.6, "volume": 0.44, "release": 0.25},
	"spawn": {"wave": "sine", "freq": 260, "freq_end": 780, "duration": 0.22, "volume": 0.2},
	"chip_drop": {"wave": "sine", "freq": 990, "freq_end": 1480, "duration": 0.2, "volume": 0.3},
	"power": {"wave": "square", "freq": 440, "freq_end": 1320, "duration": 0.26, "volume": 0.34},
	"shield": {"wave": "sine", "freq": 330, "freq_end": 990, "duration": 0.34, "volume": 0.36},
	"freeze": {"wave": "triangle", "freq": 1760, "freq_end": 440, "duration": 0.45, "volume": 0.36},
	"thaw": {"wave": "triangle", "freq": 440, "freq_end": 880, "duration": 0.18, "volume": 0.22},
	"fortify": {"wave": "pulse", "duty": 0.4, "freq": 196, "freq_end": 392, "duration": 0.32, "volume": 0.36},
	"surge": {"wave": "noise", "freq": 3000, "freq_end": 120, "duration": 0.8, "volume": 0.6, "release": 0.4},
	"life": {"wave": "square", "freq": 660, "freq_end": 1320, "duration": 0.4, "volume": 0.32, "release": 0.2},
	"lay": {"wave": "pulse", "duty": 0.5, "freq": 180, "freq_end": 120, "duration": 0.08, "volume": 0.36},
	"deny": {"wave": "square", "freq": 140, "freq_end": 110, "duration": 0.1, "volume": 0.22},
	"core_hit": {"wave": "saw", "freq": 880, "freq_end": 110, "duration": 0.5, "volume": 0.5, "release": 0.2},
	"core_lost": {"wave": "noise", "freq": 500, "freq_end": 30, "duration": 1.4, "volume": 0.7, "release": 0.8},
	"intro": {"wave": "triangle", "freq": 392, "freq_end": 784, "duration": 0.5, "volume": 0.32, "attack": 0.05, "release": 0.25},
	"alarm": {"wave": "square", "freq": 520, "freq_end": 780, "duration": 0.34, "volume": 0.3},
	"boss_in": {"wave": "saw", "freq": 70, "freq_end": 210, "duration": 0.9, "volume": 0.46, "attack": 0.2, "release": 0.3},
	"boss_hit": {"wave": "pulse", "duty": 0.2, "freq": 300, "freq_end": 180, "duration": 0.09, "volume": 0.36},
	"enrage": {"wave": "saw", "freq": 180, "freq_end": 720, "duration": 0.6, "volume": 0.4},
	"boss_down": {"wave": "noise", "freq": 700, "freq_end": 24, "duration": 1.6, "volume": 0.72, "release": 0.9},
	"stage_clear": {"wave": "square", "freq": 523, "freq_end": 1047, "duration": 0.6, "volume": 0.34, "release": 0.3},
	"tally": {"wave": "triangle", "freq": 1320, "freq_end": 1320, "duration": 0.05, "volume": 0.26},
	"tally_done": {"wave": "square", "freq": 880, "freq_end": 1760, "duration": 0.3, "volume": 0.3, "release": 0.15},
	"victory": {"wave": "square", "freq": 392, "freq_end": 1568, "duration": 1.2, "volume": 0.36, "attack": 0.05, "release": 0.5},
	"defeat": {"wave": "saw", "freq": 330, "freq_end": 55, "duration": 1.3, "volume": 0.4, "release": 0.6},
}

static func define_all(audio: GameAudio) -> void:
	for sound: String in EFFECTS:
		audio.define(sound, EFFECTS[sound])

## A bar of bass: root, root, fifth, root, twice, in eighth notes.
static func _bass_bar(root: String, fifth: String) -> Array:
	var bar: Array = []
	for half in 2:
		bar.append_array([[root, 0.5], [root, 0.5], [fifth, 0.5], [root, 0.5]])
	return bar

## A bar of noise percussion: a low thump on one and three, a bright tick on the off-beats.
static func _drum_bar(busy: bool) -> Array:
	var bar: Array = []
	for beat in 4:
		bar.append(["C3" if beat % 2 == 0 else "C6", 0.25])
		bar.append(["-", 0.25])
		bar.append(["C7", 0.125 if busy else 0.25])
		bar.append(["-", 0.375 if busy else 0.25])
	return bar

static func _bars(parts: Array) -> Array:
	var out: Array = []
	for part: Array in parts:
		out.append_array(part)
	return out

## The tune of a name the simulation asks for: "stage", "dusk" or "boss".
static func tune(tune_name: String) -> Dictionary:
	match tune_name:
		"dusk":
			return {"bpm": 116, "voices": [
				{"wave": "triangle", "volume": 0.3, "notes": [
					["D4", 1.5], ["F4", 0.5], ["A4", 1], ["G4", 1], ["F4", 0.5], ["E4", 0.5], ["D4", 1], ["C4", 1], ["E4", 1],
					["D4", 1.5], ["F4", 0.5], ["A4", 1], ["C5", 1], ["B4", 0.5], ["A4", 0.5], ["G4", 1], ["A4", 2],
					["F4", 1.5], ["A4", 0.5], ["C5", 1], ["D5", 1], ["C5", 0.5], ["A4", 0.5], ["G4", 1], ["E4", 1], ["G4", 1],
					["D4", 1], ["E4", 1], ["F4", 1], ["G4", 1], ["A4", 1.5], ["E4", 0.5], ["D4", 2],
				]},
				{"wave": "pulse", "duty": 0.2, "volume": 0.1, "notes": _bars([
					[["D3", 0.5], ["A3", 0.5], ["D4", 0.5], ["A3", 0.5], ["D3", 0.5], ["A3", 0.5], ["F4", 0.5], ["A3", 0.5]],
					[["C3", 0.5], ["G3", 0.5], ["C4", 0.5], ["G3", 0.5], ["C3", 0.5], ["G3", 0.5], ["E4", 0.5], ["G3", 0.5]],
					[["D3", 0.5], ["A3", 0.5], ["D4", 0.5], ["A3", 0.5], ["D3", 0.5], ["A3", 0.5], ["F4", 0.5], ["A3", 0.5]],
					[["G2", 0.5], ["D3", 0.5], ["G3", 0.5], ["D3", 0.5], ["A2", 0.5], ["E3", 0.5], ["A3", 0.5], ["E3", 0.5]],
					[["F2", 0.5], ["C3", 0.5], ["F3", 0.5], ["C3", 0.5], ["F2", 0.5], ["C3", 0.5], ["A3", 0.5], ["C3", 0.5]],
					[["C3", 0.5], ["G3", 0.5], ["C4", 0.5], ["G3", 0.5], ["C3", 0.5], ["G3", 0.5], ["E4", 0.5], ["G3", 0.5]],
					[["D3", 0.5], ["A3", 0.5], ["D4", 0.5], ["A3", 0.5], ["G2", 0.5], ["D3", 0.5], ["G3", 0.5], ["D3", 0.5]],
					[["A2", 0.5], ["E3", 0.5], ["A3", 0.5], ["E3", 0.5], ["D3", 0.5], ["A3", 0.5], ["D4", 0.5], ["A3", 0.5]],
				])},
				{"wave": "noise", "volume": 0.07, "notes": _bars([_drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(false)])},
			]}
		"boss":
			return {"bpm": 164, "voices": [
				{"wave": "saw", "volume": 0.2, "notes": [
					["E4", 0.5], ["-", 0.5], ["E4", 0.5], ["F4", 0.5], ["E4", 1], ["B4", 1],
					["A4", 0.5], ["-", 0.5], ["G4", 0.5], ["F4", 0.5], ["E4", 2],
					["E4", 0.5], ["-", 0.5], ["E4", 0.5], ["F4", 0.5], ["G4", 1], ["D5", 1],
					["C5", 0.5], ["B4", 0.5], ["A4", 0.5], ["G4", 0.5], ["F4", 1], ["E4", 1],
				]},
				{"wave": "triangle", "volume": 0.4, "notes": _bars([_bass_bar("E2", "B2"), _bass_bar("F2", "C3"), _bass_bar("E2", "B2"), _bass_bar("D2", "A2")])},
				{"wave": "noise", "volume": 0.1, "notes": _bars([_drum_bar(true), _drum_bar(true), _drum_bar(true), _drum_bar(true)])},
			]}
		_:
			return {"bpm": 136, "voices": [
				{"wave": "pulse", "duty": 0.25, "volume": 0.2, "notes": [
					["A4", 0.5], ["C5", 0.5], ["E5", 1], ["D5", 0.5], ["C5", 0.5], ["B4", 1],
					["A4", 0.5], ["B4", 0.5], ["C5", 1], ["E5", 1], ["-", 1],
					["F4", 0.5], ["A4", 0.5], ["C5", 1], ["B4", 0.5], ["A4", 0.5], ["G4", 1],
					["E4", 1], ["G4", 1], ["A4", 2],
					["A4", 0.5], ["C5", 0.5], ["E5", 1], ["G5", 0.5], ["E5", 0.5], ["D5", 1],
					["C5", 0.5], ["D5", 0.5], ["E5", 1], ["A5", 1], ["-", 1],
					["F5", 0.5], ["E5", 0.5], ["D5", 1], ["C5", 0.5], ["B4", 0.5], ["G#4", 1],
					["A4", 1.5], ["E4", 0.5], ["A4", 2],
				]},
				{"wave": "triangle", "volume": 0.36, "notes": _bars([_bass_bar("A2", "E3"), _bass_bar("A2", "E3"), _bass_bar("F2", "C3"), _bass_bar("E2", "B2"), _bass_bar("A2", "E3"), _bass_bar("C3", "G3"), _bass_bar("F2", "C3"), _bass_bar("A2", "E3")])},
				{"wave": "noise", "volume": 0.08, "notes": _bars([_drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(true), _drum_bar(false), _drum_bar(false), _drum_bar(false), _drum_bar(true)])},
			]}
