extends RefCounted

## Every sound of Crate Crew as data for the shared synthesiser: one effect per event the world reports, and three tunes written for this game (two stage loops and the boss loop).

const EFFECTS := {
	"jump": {"wave": "square", "freq": 300, "freq_end": 620, "duration": 0.12, "volume": 0.28},
	"land": {"wave": "noise", "freq": 900, "freq_end": 300, "duration": 0.06, "volume": 0.2},
	"lift": {"wave": "triangle", "freq": 220, "freq_end": 440, "duration": 0.1, "volume": 0.5},
	"put_down": {"wave": "triangle", "freq": 330, "freq_end": 170, "duration": 0.1, "volume": 0.45},
	"throw": {"wave": "saw", "freq": 700, "freq_end": 240, "duration": 0.14, "volume": 0.3},
	"throw_up": {"wave": "saw", "freq": 320, "freq_end": 900, "duration": 0.16, "volume": 0.3},
	"break": {"wave": "noise", "freq": 2600, "freq_end": 500, "duration": 0.2, "volume": 0.45},
	"clang": {"wave": "pulse", "freq": 1500, "freq_end": 1100, "duration": 0.09, "volume": 0.3, "duty": 0.15},
	"poof": {"wave": "noise", "freq": 1400, "freq_end": 200, "duration": 0.12, "volume": 0.22},
	"thud": {"wave": "triangle", "freq": 130, "freq_end": 60, "duration": 0.12, "volume": 0.6},
	"foe_hit": {"wave": "square", "freq": 520, "freq_end": 260, "duration": 0.08, "volume": 0.35},
	"foe_out": {"wave": "square", "freq": 660, "freq_end": 110, "duration": 0.22, "volume": 0.38},
	"hop": {"wave": "sine", "freq": 240, "freq_end": 520, "duration": 0.1, "volume": 0.25},
	"shot": {"wave": "pulse", "freq": 1200, "freq_end": 500, "duration": 0.12, "volume": 0.25, "duty": 0.3},
	"drop": {"wave": "sine", "freq": 900, "freq_end": 300, "duration": 0.18, "volume": 0.25},
	"rev": {"wave": "saw", "freq": 90, "freq_end": 260, "duration": 0.4, "volume": 0.32},
	"hurt": {"wave": "square", "freq": 420, "freq_end": 120, "duration": 0.25, "volume": 0.42},
	"die": {"wave": "triangle", "freq": 600, "freq_end": 70, "duration": 0.7, "volume": 0.55},
	"respawn": {"wave": "sine", "freq": 400, "freq_end": 1000, "duration": 0.25, "volume": 0.35},
	"gear": {"wave": "square", "freq": 1320, "freq_end": 1760, "duration": 0.07, "volume": 0.22},
	"battery": {"wave": "triangle", "freq": 520, "freq_end": 1040, "duration": 0.22, "volume": 0.5},
	"core": {"wave": "square", "freq": 660, "freq_end": 1980, "duration": 0.4, "volume": 0.32},
	"cog": {"wave": "pulse", "freq": 880, "freq_end": 2640, "duration": 0.5, "volume": 0.32, "duty": 0.4},
	"flag": {"wave": "triangle", "freq": 660, "freq_end": 990, "duration": 0.3, "volume": 0.5},
	"chute": {"wave": "noise", "freq": 500, "freq_end": 1500, "duration": 0.15, "volume": 0.2},
	"stage_start": {"wave": "pulse", "freq": 392, "freq_end": 784, "duration": 0.35, "volume": 0.3, "duty": 0.5},
	"stage_clear": {"wave": "square", "freq": 523, "freq_end": 1568, "duration": 0.9, "volume": 0.34, "release": 0.3},
	"boss_start": {"wave": "saw", "freq": 180, "freq_end": 60, "duration": 0.9, "volume": 0.4},
	"boss_spit": {"wave": "noise", "freq": 700, "freq_end": 2200, "duration": 0.16, "volume": 0.36},
	"boss_inhale": {"wave": "noise", "freq": 300, "freq_end": 3200, "duration": 1.6, "volume": 0.22, "attack": 0.3, "release": 0.4},
	"boss_charge": {"wave": "saw", "freq": 140, "freq_end": 420, "duration": 0.5, "volume": 0.36},
	"boss_slam": {"wave": "noise", "freq": 400, "freq_end": 80, "duration": 0.35, "volume": 0.6},
	"boss_hit": {"wave": "square", "freq": 240, "freq_end": 960, "duration": 0.2, "volume": 0.45},
	"boss_angry": {"wave": "saw", "freq": 110, "freq_end": 330, "duration": 0.7, "volume": 0.4},
	"boss_burst": {"wave": "noise", "freq": 1800, "freq_end": 200, "duration": 0.25, "volume": 0.45},
	"boss_down": {"wave": "triangle", "freq": 880, "freq_end": 55, "duration": 1.2, "volume": 0.6, "release": 0.4},
	"continue": {"wave": "pulse", "freq": 330, "freq_end": 660, "duration": 0.6, "volume": 0.3, "duty": 0.5},
	"game_over": {"wave": "triangle", "freq": 392, "freq_end": 98, "duration": 1.4, "volume": 0.5, "release": 0.5},
}

static func define_all(audio: GameAudio) -> void:
	for name: String in EFFECTS:
		audio.define(name, EFFECTS[name])

## The tune of a stage: the two workshop floors share a bright loop, the shaft and the loft a darker one.
static func stage_music(stage: int) -> Dictionary:
	return _bench_tune() if stage % 2 == 0 else _shaft_tune()

static func _bench_tune() -> Dictionary:
	var lead := [
		["E4", 0.5], ["G4", 0.5], ["C5", 1], ["G4", 0.5], ["E4", 0.5], ["G4", 1],
		["A4", 0.5], ["C5", 0.5], ["A4", 1], ["G4", 2],
		["E4", 0.5], ["G4", 0.5], ["C5", 1], ["D5", 0.5], ["E5", 0.5], ["D5", 1],
		["C5", 1], ["A4", 1], ["G4", 2],
		["F4", 0.5], ["A4", 0.5], ["C5", 1], ["A4", 0.5], ["F4", 0.5], ["A4", 1],
		["G4", 0.5], ["B4", 0.5], ["D5", 1], ["B4", 2],
		["C5", 0.5], ["D5", 0.5], ["E5", 1], ["G5", 0.5], ["E5", 0.5], ["D5", 1],
		["C5", 1], ["G4", 1], ["C5", 1], ["-", 1],
	]
	var bass: Array = []
	for root: Array in [["C2", "G2"], ["A2", "E2"], ["C2", "G2"], ["F2", "G2"], ["F2", "C3"], ["G2", "D3"], ["C2", "G2"], ["C2", "G2"]]:
		bass.append_array([[root[0], 1], [root[1], 0.5], [root[0], 0.5], [root[1], 1], [root[0], 1]])
	var tick: Array = []
	for beat in 32:
		tick.append_array([["C7", 0.12], ["-", 0.38], ["C7", 0.06], ["-", 0.44]])
	return {"bpm": 132, "voices": [
		{"wave": "pulse", "volume": 0.2, "duty": 0.3, "notes": lead},
		{"wave": "triangle", "volume": 0.34, "notes": bass},
		{"wave": "noise", "volume": 0.05, "notes": tick},
	]}

static func _shaft_tune() -> Dictionary:
	var lead := [
		["A4", 1], ["C5", 0.5], ["E5", 0.5], ["D5", 1], ["C5", 1],
		["B4", 1], ["G4", 1], ["E4", 2],
		["A4", 0.5], ["B4", 0.5], ["C5", 1], ["E5", 1], ["D5", 1],
		["E5", 2], ["-", 1], ["E4", 1],
		["F4", 1], ["A4", 0.5], ["C5", 0.5], ["B4", 1], ["A4", 1],
		["G4", 1], ["B4", 1], ["D5", 2],
		["E5", 0.5], ["D5", 0.5], ["C5", 1], ["B4", 1], ["G#4", 1],
		["A4", 3], ["-", 1],
	]
	var bass: Array = []
	for root: String in ["A2", "E2", "A2", "E2", "F2", "G2", "E2", "A2"]:
		bass.append_array([[root, 0.5], ["-", 0.5], [root, 0.5], [root, 0.5], ["-", 0.5], [root, 0.5], [root, 1]])
	var tick: Array = []
	for beat in 16:
		tick.append_array([["-", 1], ["C7", 0.1], ["-", 0.9]])
	return {"bpm": 116, "voices": [
		{"wave": "square", "volume": 0.17, "notes": lead},
		{"wave": "triangle", "volume": 0.36, "notes": bass},
		{"wave": "noise", "volume": 0.05, "notes": tick},
	]}

static func boss_music() -> Dictionary:
	var lead := [
		["E4", 0.5], ["E4", 0.5], ["G4", 0.5], ["E4", 0.5], ["B4", 1], ["A4", 1],
		["G4", 0.5], ["G4", 0.5], ["A4", 0.5], ["G4", 0.5], ["F#4", 1], ["D4", 1],
		["E4", 0.5], ["E4", 0.5], ["G4", 0.5], ["B4", 0.5], ["D5", 1], ["C5", 1],
		["B4", 0.5], ["A4", 0.5], ["G4", 0.5], ["F#4", 0.5], ["E4", 2],
		["C5", 0.5], ["C5", 0.5], ["B4", 0.5], ["C5", 0.5], ["E5", 1], ["C5", 1],
		["D5", 0.5], ["D5", 0.5], ["C5", 0.5], ["D5", 0.5], ["F#5", 1], ["D5", 1],
		["E5", 0.5], ["D5", 0.5], ["B4", 0.5], ["G4", 0.5], ["A4", 1], ["F#4", 1],
		["E4", 1], ["B3", 1], ["E4", 1], ["-", 1],
	]
	var bass: Array = []
	for root: String in ["E2", "D2", "E2", "E2", "C2", "D2", "E2", "E2"]:
		for eighth in 8:
			bass.append([root, 0.5])
	var tick: Array = []
	for beat in 32:
		tick.append_array([["C7", 0.1], ["-", 0.4], ["C6", 0.12], ["-", 0.38]])
	return {"bpm": 164, "voices": [
		{"wave": "saw", "volume": 0.15, "notes": lead},
		{"wave": "square", "volume": 0.2, "notes": bass},
		{"wave": "noise", "volume": 0.06, "notes": tick},
	]}
