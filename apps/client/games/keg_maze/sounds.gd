extends RefCounted

## Every sound of Keg Burrow, synthesised by the shared procedural audio: the effects, the short jingles (sequences of one plucked note at different pitches) and four looping tunes written for this game (one per depth and one for the bosses).

const EFFECTS := {
	"place": {"wave": "square", "freq": 240, "freq_end": 150, "duration": 0.08, "volume": 0.4},
	"deny": {"wave": "square", "freq": 110, "freq_end": 100, "duration": 0.06, "volume": 0.25},
	"detonate": {"wave": "square", "freq": 1500, "freq_end": 700, "duration": 0.05, "volume": 0.35},
	"blast": {"wave": "noise", "freq": 1400, "freq_end": 140, "duration": 0.45, "volume": 0.7, "release": 0.3},
	"thump": {"wave": "triangle", "freq": 120, "freq_end": 38, "duration": 0.32, "volume": 0.8, "release": 0.2},
	"chain": {"wave": "pulse", "freq": 440, "freq_end": 880, "duration": 0.1, "volume": 0.3},
	"crate": {"wave": "noise", "freq": 2600, "freq_end": 700, "duration": 0.14, "volume": 0.4},
	"power": {"wave": "square", "freq": 523, "freq_end": 1046, "duration": 0.18, "volume": 0.4},
	"gem": {"wave": "sine", "freq": 1318, "freq_end": 1760, "duration": 0.16, "volume": 0.5},
	"heart": {"wave": "triangle", "freq": 440, "freq_end": 880, "duration": 0.3, "volume": 0.6},
	"foe_die": {"wave": "saw", "freq": 520, "freq_end": 90, "duration": 0.22, "volume": 0.4},
	"crack": {"wave": "noise", "freq": 1800, "freq_end": 500, "duration": 0.1, "volume": 0.5},
	"charge": {"wave": "saw", "freq": 150, "freq_end": 330, "duration": 0.25, "volume": 0.35},
	"hurt": {"wave": "square", "freq": 440, "freq_end": 70, "duration": 0.5, "volume": 0.5, "release": 0.2},
	"out": {"wave": "triangle", "freq": 320, "freq_end": 45, "duration": 0.9, "volume": 0.7, "release": 0.3},
	"respawn": {"wave": "pulse", "freq": 300, "freq_end": 600, "duration": 0.16, "volume": 0.35},
	"shield": {"wave": "sine", "freq": 990, "freq_end": 330, "duration": 0.25, "volume": 0.5},
	"exit_found": {"wave": "triangle", "freq": 392, "freq_end": 784, "duration": 0.3, "volume": 0.6},
	"exit_open": {"wave": "pulse", "freq": 523, "freq_end": 1046, "duration": 0.45, "volume": 0.4, "duty": 0.5},
	"go": {"wave": "square", "freq": 660, "freq_end": 660, "duration": 0.1, "volume": 0.35},
	"tick": {"wave": "square", "freq": 1200, "freq_end": 1200, "duration": 0.04, "volume": 0.3},
	"timeup": {"wave": "saw", "freq": 200, "freq_end": 55, "duration": 0.8, "volume": 0.5, "release": 0.3},
	"boss_hit": {"wave": "saw", "freq": 300, "freq_end": 110, "duration": 0.2, "volume": 0.5},
	"boss_tell": {"wave": "saw", "freq": 80, "freq_end": 260, "duration": 0.8, "volume": 0.45, "attack": 0.2},
	"boss_die": {"wave": "noise", "freq": 1300, "freq_end": 40, "duration": 1.6, "volume": 0.8, "release": 0.8},
	"spit": {"wave": "noise", "freq": 500, "freq_end": 2200, "duration": 0.5, "volume": 0.5, "release": 0.2},
	"rock_warn": {"wave": "sine", "freq": 900, "freq_end": 480, "duration": 0.3, "volume": 0.4},
	"rock_fall": {"wave": "noise", "freq": 420, "freq_end": 80, "duration": 0.3, "volume": 0.6, "release": 0.15},
	"spawn": {"wave": "pulse", "freq": 200, "freq_end": 520, "duration": 0.2, "volume": 0.35},
	"crush": {"wave": "noise", "freq": 700, "freq_end": 200, "duration": 0.12, "volume": 0.5},
	"note": {"wave": "triangle", "freq": 523.25, "freq_end": 523.25, "duration": 0.2, "volume": 0.6, "release": 0.12},
}

## Jingles as [seconds from now, effect, pitch]. Pitches are ratios of the plucked note (a C).
const JINGLES := {
	"clear": [[0.0, 1.0], [0.14, 1.26], [0.28, 1.5], [0.42, 2.0], [0.7, 1.5], [0.84, 2.0]],
	"victory": [[0.0, 1.0], [0.16, 1.0], [0.32, 1.5], [0.48, 1.335], [0.64, 1.5], [0.8, 2.0], [1.1, 1.682], [1.26, 2.0], [1.42, 2.52], [1.74, 3.0]],
	"continue": [[0.0, 0.75], [0.2, 0.84], [0.4, 1.0], [0.6, 1.26]],
	"defeat": [[0.0, 1.0], [0.25, 0.944], [0.5, 0.794], [0.8, 0.667], [1.2, 0.5]],
}

static func define(audio: GameAudio) -> void:
	for sound: String in EFFECTS:
		audio.define(sound, EFFECTS[sound])

static func jingle(tune: String) -> Array:
	var out: Array = []
	for note: Array in JINGLES[tune]:
		out.append([float(note[0]), "note", float(note[1])])
	return out

## The tune of a stage: one per depth, and the boss tune on the two boss levels.
static func music(stage: int) -> Dictionary:
	if stage == 5 or stage == 8:
		return _boss()
	match stage / 3:
		0:
			return _topsoil()
		1:
			return _gallery()
	return _deep()

## Split "A4:.5 C5:1 -:2" into [[pitch, beats], ...].
static func _notes(text: String) -> Array:
	var out: Array = []
	for word in text.split(" ", false):
		out.append([word.get_slice(":", 0), word.get_slice(":", 1).to_float()])
	return out

## A bar of bass for each root in `roots`: root, octave, root, fifth, root.
static func _walk(roots: Array) -> Array:
	var out: Array = []
	for bar: Array in roots:
		out.append_array([[bar[0], 1.0], [bar[1], 0.5], [bar[0], 0.5], [bar[2], 1.0], [bar[0], 1.0]])
	return out

static func _repeat(notes: Array, times: int) -> Array:
	var out: Array = []
	for index in times:
		out.append_array(notes)
	return out

## Kick, hat, snare, hat over two beats, repeated to fill `beats`.
static func _drums(beats: int) -> Array:
	return _repeat(_notes("C3:.2 -:.3 C7:.08 -:.42 C5:.16 -:.34 C7:.08 -:.42"), beats / 2)

static func _topsoil() -> Dictionary:
	var lead := _notes("A4:.5 C5:.5 E5:.5 C5:.5 D5:1 B4:1 C5:.5 B4:.5 A4:.5 G4:.5 A4:2 A4:.5 C5:.5 E5:.5 G5:.5 F5:1 D5:1 E5:.5 D5:.5 C5:.5 B4:.5 C5:1 -:1 F5:.5 E5:.5 D5:.5 C5:.5 D5:1 A4:1 G4:.5 A4:.5 B4:.5 D5:.5 C5:2 A4:.5 C5:.5 E5:.5 A5:.5 G5:1 E5:1 D5:.5 E5:.5 D5:.5 B4:.5 A4:2")
	var bass := _walk([["A2", "A3", "E3"], ["A2", "A3", "E3"], ["F2", "F3", "C3"], ["C3", "C4", "G3"], ["D3", "D4", "A3"], ["G2", "G3", "D3"], ["A2", "A3", "E3"], ["E2", "E3", "B2"]])
	return {"bpm": 126, "voices": [
		{"wave": "pulse", "duty": 0.25, "volume": 0.2, "notes": lead},
		{"wave": "triangle", "volume": 0.34, "notes": bass},
		{"wave": "noise", "volume": 0.1, "notes": _drums(32)},
	]}

static func _gallery() -> Dictionary:
	var ripple := _repeat(_notes("D4:.5 A4:.5 D5:.5 F5:.5 E5:.5 D5:.5 A4:.5 F4:.5 C4:.5 G4:.5 C5:.5 E5:.5 D5:.5 C5:.5 G4:.5 E4:.5 Bb3:.5 F4:.5 Bb4:.5 D5:.5 C5:.5 Bb4:.5 F4:.5 D4:.5 A3:.5 E4:.5 A4:.5 C#5:.5 E5:.5 C#5:.5 A4:.5 E4:.5"), 2)
	var song := _notes("F5:2 A5:2 G5:2 E5:2 F5:2 D5:2 E5:3 -:1 A5:2 F5:2 G5:2 C6:2 Bb5:2 A5:2 A5:3 -:1")
	var bass := _repeat(_notes("D2:3 D3:1 C2:3 C3:1 Bb1:3 Bb2:1 A1:3 A2:1"), 2)
	return {"bpm": 112, "voices": [
		{"wave": "triangle", "volume": 0.26, "notes": ripple},
		{"wave": "pulse", "duty": 0.5, "volume": 0.14, "notes": song},
		{"wave": "sine", "volume": 0.4, "notes": bass},
		{"wave": "noise", "volume": 0.05, "notes": _repeat(_notes("C7:.06 -:.94"), 32)},
	]}

static func _deep() -> Dictionary:
	var lead := _notes("E4:.5 E4:.5 F4:.5 E4:.5 G4:1 F4:1 E4:.5 E4:.5 B4:.5 A4:.5 G4:1 F4:1 A4:.5 A4:.5 B4:.5 C5:.5 B4:1 G4:1 F4:.5 G4:.5 F4:.5 D4:.5 E4:2 E5:.5 E5:.5 F5:.5 E5:.5 G5:1 F5:1 E5:.5 D5:.5 C5:.5 B4:.5 C5:1 A4:1 B4:.5 C5:.5 D5:.5 E5:.5 F5:1 D5:1 E5:1 B4:1 E4:2")
	var half := _repeat(_notes("E2:.5"), 16) + _repeat(_notes("A2:.5"), 8) + _repeat(_notes("F2:.5"), 4) + _repeat(_notes("E2:.5"), 4)
	return {"bpm": 138, "voices": [
		{"wave": "saw", "volume": 0.15, "notes": lead},
		{"wave": "square", "volume": 0.2, "release": 0.03, "notes": _repeat(half, 2)},
		{"wave": "noise", "volume": 0.13, "notes": _drums(32)},
	]}

static func _boss() -> Dictionary:
	var lead := _notes("C5:.5 -:.5 C5:.5 Eb5:.5 D5:.5 C5:.5 B4:1 C5:.5 -:.5 C5:.5 G5:.5 F#5:.5 F5:.5 Eb5:1 Ab4:.5 C5:.5 Eb5:.5 Ab5:.5 G5:1 Eb5:1 D5:.5 Eb5:.5 D5:.5 B4:.5 G4:2 Eb5:.5 -:.5 Eb5:.5 G5:.5 F5:.5 Eb5:.5 D5:1 Eb5:.5 -:.5 Eb5:.5 C6:.5 Bb5:.5 Ab5:.5 G5:1 F5:.5 Ab5:.5 C6:.5 Ab5:.5 G5:1 Eb5:1 D5:.5 F5:.5 Ab5:.5 B5:.5 C6:2")
	var half := _repeat(_notes("C2:.5 C3:.5"), 8) + _repeat(_notes("Ab1:.5 Ab2:.5"), 4) + _repeat(_notes("G1:.5 G2:.5"), 4)
	return {"bpm": 150, "voices": [
		{"wave": "square", "volume": 0.18, "notes": lead},
		{"wave": "saw", "volume": 0.2, "release": 0.03, "notes": _repeat(half, 2)},
		{"wave": "noise", "volume": 0.14, "notes": _repeat(_notes("C3:.2 -:.3 C3:.2 -:.3 C5:.16 -:.34 C7:.08 -:.42"), 16)},
	]}
