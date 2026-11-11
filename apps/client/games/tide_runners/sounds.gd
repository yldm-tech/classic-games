extends RefCounted

## Every sound of the game as data for the shared synthesiser: one effect per event, a tune for each stage and one for the bosses. All of it is original and nothing is loaded from disk.

const EFFECTS := {
	"jump": {"wave": "square", "freq": 260, "freq_end": 520, "duration": 0.11, "volume": 0.3},
	"shot0": {"wave": "pulse", "freq": 980, "freq_end": 520, "duration": 0.06, "volume": 0.28, "duty": 0.3},
	"shot1": {"wave": "pulse", "freq": 760, "freq_end": 380, "duration": 0.09, "volume": 0.3, "duty": 0.5},
	"shot2": {"wave": "sine", "freq": 520, "freq_end": 1040, "duration": 0.1, "volume": 0.4},
	"shot3": {"wave": "triangle", "freq": 300, "freq_end": 140, "duration": 0.14, "volume": 0.5},
	"shot4": {"wave": "saw", "freq": 1500, "freq_end": 300, "duration": 0.16, "volume": 0.3},
	"shot5": {"wave": "square", "freq": 620, "freq_end": 930, "duration": 0.08, "volume": 0.28},
	"hit": {"wave": "noise", "freq": 3200, "freq_end": 1600, "duration": 0.05, "volume": 0.32},
	"clang": {"wave": "square", "freq": 1800, "freq_end": 1500, "duration": 0.04, "volume": 0.2},
	"boom_small": {"wave": "noise", "freq": 900, "freq_end": 120, "duration": 0.22, "volume": 0.5, "release": 0.15},
	"boom_big": {"wave": "noise", "freq": 500, "freq_end": 40, "duration": 0.7, "volume": 0.7, "release": 0.5},
	"thud": {"wave": "noise", "freq": 400, "freq_end": 90, "duration": 0.12, "volume": 0.35},
	"foe_shot": {"wave": "saw", "freq": 300, "freq_end": 180, "duration": 0.1, "volume": 0.22},
	"lob": {"wave": "triangle", "freq": 180, "freq_end": 420, "duration": 0.18, "volume": 0.4},
	"ring": {"wave": "pulse", "freq": 240, "freq_end": 720, "duration": 0.25, "volume": 0.3, "duty": 0.2},
	"splash": {"wave": "noise", "freq": 2400, "freq_end": 500, "duration": 0.25, "volume": 0.3, "attack": 0.03, "release": 0.18},
	"die": {"wave": "saw", "freq": 700, "freq_end": 70, "duration": 0.55, "volume": 0.5, "release": 0.2},
	"respawn": {"wave": "triangle", "freq": 330, "freq_end": 990, "duration": 0.25, "volume": 0.4},
	"pickup": {"wave": "square", "freq": 660, "freq_end": 1320, "duration": 0.16, "volume": 0.35},
	"shield_pop": {"wave": "sine", "freq": 1200, "freq_end": 300, "duration": 0.2, "volume": 0.5},
	"extra_life": {"wave": "pulse", "freq": 880, "freq_end": 1760, "duration": 0.4, "volume": 0.35, "duty": 0.4},
	"alarm": {"wave": "square", "freq": 440, "freq_end": 660, "duration": 0.45, "volume": 0.3, "attack": 0.05},
	"go": {"wave": "pulse", "freq": 520, "freq_end": 1040, "duration": 0.3, "volume": 0.3},
	"lunge": {"wave": "saw", "freq": 200, "freq_end": 600, "duration": 0.3, "volume": 0.4},
	"slam": {"wave": "noise", "freq": 300, "freq_end": 50, "duration": 0.4, "volume": 0.7, "release": 0.3},
	"fanfare": {"wave": "pulse", "freq": 523, "freq_end": 1568, "duration": 1.1, "volume": 0.4, "attack": 0.02, "release": 0.5, "duty": 0.4},
}

static func define_all(audio: GameAudio) -> void:
	for sound: String in EFFECTS:
		if not audio.has_sound(sound):
			audio.define(sound, EFFECTS[sound])

## "D5:.5 F5:.5 -:1" -> [["D5", 0.5], ["F5", 0.5], ["-", 1.0]]
static func notes(text: String) -> Array:
	var out: Array = []
	for token in text.split(" ", false):
		out.append([token.get_slice(":", 0), token.get_slice(":", 1).to_float()])
	return out

static func _repeat(text: String, times: int) -> Array:
	var out: Array = []
	for index in times:
		out.append_array(notes(text))
	return out

static func stage_music(stage: int) -> Dictionary:
	match stage:
		0:
			return _boulevard()
		1:
			return _tower()
		_:
			return _dockyard()

## Stage one: a determined march in D minor.
static func _boulevard() -> Dictionary:
	var lead := "D5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:1 F5:.5 E5:.5 D5:1 A4:1 -:1 Bb4:.5 D5:.5 F5:1 E5:.5 D5:.5 C5:1 D5:.5 C5:.5 A4:1 A4:1 -:1 "
	lead += "D5:.5 F5:.5 A5:1 C6:.5 A5:.5 G5:1 A5:.5 G5:.5 F5:1 D5:1 -:1 Bb4:.5 C5:.5 D5:.5 E5:.5 F5:1 G5:1 A5:1.5 G5:.5 A5:2"
	var bass := "D2:1 D3:1 D2:1 D3:1 D2:1 D3:1 D2:1 D3:1 Bb1:1 Bb2:1 Bb1:1 Bb2:1 A1:1 A2:1 A1:1 A2:1 D2:1 D3:1 D2:1 D3:1 F2:1 F3:1 F2:1 F3:1 Bb1:1 Bb2:1 Bb1:1 Bb2:1 A1:1 A2:1 A2:1 A1:1"
	return {"bpm": 140, "voices": [
		{"wave": "pulse", "duty": 0.3, "volume": 0.22, "notes": notes(lead)},
		{"wave": "triangle", "volume": 0.34, "notes": notes(bass)},
		{"wave": "noise", "volume": 0.1, "release": 0.02, "notes": _repeat("C4:.25 -:.75 C7:.25 -:.75", 16)},
	]}

## Stage two: climbing arpeggios in E minor with a slow line over the second half.
static func _tower() -> Dictionary:
	var climb := "E4:.5 G4:.5 B4:.5 E5:.5 B4:.5 G4:.5 E4:.5 G4:.5 D4:.5 F#4:.5 A4:.5 D5:.5 A4:.5 F#4:.5 D4:.5 F#4:.5 C4:.5 E4:.5 G4:.5 C5:.5 G4:.5 E4:.5 C4:.5 E4:.5 B3:.5 D#4:.5 F#4:.5 B4:.5 F#4:.5 D#4:.5 B3:1"
	var line := "-:16 E5:1.5 D5:.5 B4:2 A4:1.5 B4:.5 D5:2 C5:1 E5:1 G5:1.5 F#5:.5 F#5:2 D#5:2"
	return {"bpm": 126, "voices": [
		{"wave": "square", "volume": 0.16, "notes": _repeat(climb, 2)},
		{"wave": "pulse", "duty": 0.25, "volume": 0.2, "notes": notes(line)},
		{"wave": "triangle", "volume": 0.34, "notes": _repeat("E2:2 E2:2 D2:2 D2:2 C2:2 C2:2 B1:2 B1:2", 2)},
	]}

## Stage three: a driving line in A minor.
static func _dockyard() -> Dictionary:
	var lead := "A4:.5 A4:.5 C5:.5 A4:.5 E5:1 D5:.5 C5:.5 B4:.5 B4:.5 D5:.5 B4:.5 G5:1 E5:1 A4:.5 A4:.5 C5:.5 E5:.5 A5:1 G5:.5 E5:.5 G5:.5 F5:.5 E5:.5 D5:.5 E5:2 "
	lead += "F5:1 A5:1 G5:.5 F5:.5 E5:1 D5:1 F5:1 E5:.5 D5:.5 C5:1 B4:.5 C5:.5 D5:.5 E5:.5 F5:.5 E5:.5 D5:.5 B4:.5 A4:1 E5:1 A5:2"
	var bass := "A1:.5 A2:.5 A1:.5 A2:.5 A1:.5 A2:.5 A1:.5 A2:.5 G1:.5 G2:.5 G1:.5 G2:.5 G1:.5 G2:.5 G1:.5 G2:.5 F1:.5 F2:.5 F1:.5 F2:.5 F1:.5 F2:.5 F1:.5 F2:.5 E1:.5 E2:.5 E1:.5 E2:.5 E1:.5 E2:.5 E1:.5 E2:.5 "
	bass += "F1:.5 F2:.5 F1:.5 F2:.5 F1:.5 F2:.5 F1:.5 F2:.5 D2:.5 D3:.5 D2:.5 D3:.5 D2:.5 D3:.5 D2:.5 D3:.5 E2:.5 E3:.5 E2:.5 E3:.5 E2:.5 E3:.5 E2:.5 E3:.5 A1:.5 A2:.5 A1:.5 A2:.5 A1:1 A2:1"
	return {"bpm": 152, "voices": [
		{"wave": "pulse", "duty": 0.4, "volume": 0.2, "notes": notes(lead)},
		{"wave": "triangle", "volume": 0.34, "notes": notes(bass)},
		{"wave": "noise", "volume": 0.1, "release": 0.02, "notes": _repeat("C4:.25 -:.25 C7:.25 -:.25 C5:.25 -:.25 C7:.25 -:.25", 16)},
	]}

## The bosses: a tight, restless figure that keeps stepping up.
static func boss_music() -> Dictionary:
	var lead := "E5:.5 -:.5 E5:.5 F5:.5 E5:.5 -:.5 D5:.5 E5:.5 G5:1 F5:.5 E5:.5 D5:1 -:1 E5:.5 -:.5 E5:.5 F5:.5 G5:.5 -:.5 A5:.5 G5:.5 Bb5:1 A5:.5 G5:.5 F5:1 E5:1 "
	lead += "A5:.5 -:.5 A5:.5 Bb5:.5 A5:.5 -:.5 G5:.5 A5:.5 C6:1 Bb5:.5 A5:.5 G5:1 -:1 F5:.5 G5:.5 A5:.5 Bb5:.5 A5:.5 G5:.5 F5:.5 E5:.5 D5:1 E5:1 E5:2"
	var bass := "E2:.5 E2:.5 E3:.5 E2:.5 E2:.5 E2:.5 E3:.5 E2:.5 E2:.5 E2:.5 E3:.5 E2:.5 E2:.5 E2:.5 E3:.5 E2:.5 E2:.5 E2:.5 E3:.5 E2:.5 E2:.5 E2:.5 E3:.5 E2:.5 F2:.5 F2:.5 F3:.5 F2:.5 F2:.5 F2:.5 F3:.5 F2:.5 "
	bass += "A2:.5 A2:.5 A3:.5 A2:.5 A2:.5 A2:.5 A3:.5 A2:.5 A2:.5 A2:.5 A3:.5 A2:.5 A2:.5 A2:.5 A3:.5 A2:.5 Bb2:.5 Bb2:.5 Bb3:.5 Bb2:.5 Bb2:.5 Bb2:.5 Bb3:.5 Bb2:.5 E2:.5 E2:.5 E3:.5 E2:.5 E2:1 E3:1"
	return {"bpm": 164, "voices": [
		{"wave": "saw", "volume": 0.16, "notes": notes(lead)},
		{"wave": "square", "volume": 0.18, "notes": notes(bass)},
		{"wave": "noise", "volume": 0.1, "release": 0.02, "notes": _repeat("C4:.25 -:.25 C7:.25 -:.25", 32)},
	]}
