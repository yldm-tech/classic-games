extends RefCounted

## Every effect and tune of the game as specs for the shared procedural audio. Nothing here is a recording.

const EFFECTS := {
	"jump": {"wave": "square", "freq": 300, "freq_end": 620, "duration": 0.13, "volume": 0.32},
	"ram_jump": {"wave": "triangle", "freq": 180, "freq_end": 520, "duration": 0.18, "volume": 0.5},
	"throw": {"wave": "noise", "freq": 5200, "freq_end": 1800, "duration": 0.09, "volume": 0.28},
	"spark_hit": {"wave": "pulse", "freq": 880, "freq_end": 440, "duration": 0.07, "volume": 0.3, "duty": 0.125},
	"spark_fizzle": {"wave": "noise", "freq": 2400, "freq_end": 600, "duration": 0.06, "volume": 0.16},
	"creature_down": {"wave": "square", "freq": 520, "freq_end": 110, "duration": 0.2, "volume": 0.36},
	"stomp": {"wave": "triangle", "freq": 240, "freq_end": 70, "duration": 0.16, "volume": 0.6},
	"hurt": {"wave": "saw", "freq": 420, "freq_end": 130, "duration": 0.26, "volume": 0.4},
	"die": {"wave": "pulse", "freq": 660, "freq_end": 82, "duration": 0.9, "volume": 0.4, "duty": 0.25, "release": 0.3},
	"moth": {"wave": "triangle", "freq": 1320, "freq_end": 1760, "duration": 0.07, "volume": 0.34},
	"flask": {"wave": "pulse", "freq": 520, "freq_end": 1040, "duration": 0.16, "volume": 0.34, "duty": 0.5},
	"resin": {"wave": "pulse", "freq": 392, "freq_end": 1568, "duration": 0.32, "volume": 0.36, "duty": 0.25},
	"one_up": {"wave": "square", "freq": 660, "freq_end": 1980, "duration": 0.45, "volume": 0.34, "release": 0.15},
	"bell": {"wave": "sine", "freq": 1568, "freq_end": 1480, "duration": 0.6, "volume": 0.5, "release": 0.45},
	"ram_lost": {"wave": "saw", "freq": 330, "freq_end": 660, "duration": 0.3, "volume": 0.3},
	"lamp": {"wave": "triangle", "freq": 523, "freq_end": 1047, "duration": 0.4, "volume": 0.5, "release": 0.2},
	"beacon": {"wave": "saw", "freq": 110, "freq_end": 880, "duration": 1.1, "volume": 0.36, "release": 0.4},
	"geyser": {"wave": "noise", "freq": 900, "freq_end": 3600, "duration": 0.7, "volume": 0.3, "release": 0.3},
	"icicle": {"wave": "pulse", "freq": 2200, "freq_end": 1500, "duration": 0.12, "volume": 0.22, "duty": 0.125},
	"shatter": {"wave": "noise", "freq": 7000, "freq_end": 2400, "duration": 0.16, "volume": 0.3},
	"crumble": {"wave": "noise", "freq": 500, "freq_end": 160, "duration": 0.3, "volume": 0.34},
	"spit": {"wave": "saw", "freq": 160, "freq_end": 420, "duration": 0.16, "volume": 0.34},
	"cinder": {"wave": "noise", "freq": 1600, "freq_end": 300, "duration": 0.22, "volume": 0.26},
	"boss_roar": {"wave": "saw", "freq": 140, "freq_end": 55, "duration": 0.9, "volume": 0.5, "release": 0.3},
	"boss_screech": {"wave": "pulse", "freq": 1500, "freq_end": 2600, "duration": 0.5, "volume": 0.32, "duty": 0.125, "release": 0.2},
	"boss_hit": {"wave": "square", "freq": 220, "freq_end": 150, "duration": 0.1, "volume": 0.42},
	"boss_land": {"wave": "noise", "freq": 320, "freq_end": 90, "duration": 0.35, "volume": 0.55},
	"boss_down": {"wave": "noise", "freq": 2600, "freq_end": 120, "duration": 1.4, "volume": 0.5, "release": 0.6},
	"splash": {"wave": "noise", "freq": 1200, "freq_end": 260, "duration": 0.4, "volume": 0.36},
	"relight": {"wave": "triangle", "freq": 262, "freq_end": 784, "duration": 0.5, "volume": 0.46},
	"game_over": {"wave": "triangle", "freq": 392, "freq_end": 98, "duration": 1.4, "volume": 0.5, "release": 0.5},
	"bonus": {"wave": "square", "freq": 990, "freq_end": 1180, "duration": 0.04, "volume": 0.2},
}

## Chords as [root in the bass octave, third, fifth] for the helpers below.
const HIGHLAND_CHORDS := [["A2", "C4", "E4"], ["F2", "A3", "C4"], ["A2", "C4", "E4"], ["G2", "B3", "D4"], ["F2", "A3", "C4"], ["C3", "E4", "G4"], ["E2", "G3", "B3"], ["A2", "C4", "E4"]]
const HIGHLAND_LEAD := [
	["A4", 1], ["C5", 1], ["E5", 1.5], ["D5", 0.5],
	["C5", 1], ["A4", 1], ["G4", 2],
	["A4", 1], ["C5", 1], ["D5", 1.5], ["E5", 0.5],
	["G5", 2], ["E5", 2],
	["A5", 1], ["G5", 1], ["E5", 1.5], ["D5", 0.5],
	["C5", 1], ["D5", 1], ["E5", 2],
	["D5", 1], ["C5", 1], ["B4", 1.5], ["G4", 0.5],
	["A4", 3], ["-", 1],
]

const HOLLOW_CHORDS := [["D2", "F3", "A3"], ["Bb1", "D3", "F3"], ["C2", "E3", "G3"], ["A1", "C#3", "E3"], ["F2", "A3", "C4"], ["C2", "E3", "G3"], ["Bb1", "D3", "F3"], ["D2", "F3", "A3"]]
const HOLLOW_LEAD := [
	["D5", 2], ["F5", 1], ["E5", 1],
	["D5", 1], ["A4", 1], ["Bb4", 2],
	["C5", 2], ["D5", 1], ["F5", 1],
	["E5", 3], ["-", 1],
	["F5", 1], ["G5", 1], ["A5", 2],
	["G5", 1], ["F5", 1], ["E5", 2],
	["D5", 1], ["C5", 1], ["Bb4", 1], ["A4", 1],
	["D5", 3], ["-", 1],
]

const BOSS_CHORDS := [["E2", "G3", "B3"], ["E2", "G3", "B3"], ["C2", "E3", "G3"], ["D2", "F#3", "A3"], ["E2", "G3", "B3"], ["G2", "B3", "D4"], ["A2", "C4", "E4"], ["B1", "D#3", "F#3"]]
const BOSS_LEAD := [
	["E4", 0.5], ["E4", 0.5], ["G4", 0.5], ["E4", 0.5], ["B4", 1], ["A4", 1],
	["G4", 0.5], ["E4", 0.5], ["G4", 0.5], ["A4", 0.5], ["B4", 2],
	["C5", 0.5], ["C5", 0.5], ["E5", 0.5], ["C5", 0.5], ["G4", 1], ["E4", 1],
	["F#4", 0.5], ["A4", 0.5], ["D5", 0.5], ["A4", 0.5], ["F#4", 2],
	["E5", 0.5], ["E5", 0.5], ["D5", 0.5], ["B4", 0.5], ["G4", 1], ["B4", 1],
	["D5", 0.5], ["B4", 0.5], ["G4", 0.5], ["B4", 0.5], ["D5", 2],
	["E5", 1], ["C5", 1], ["A4", 1], ["C5", 1],
	["B4", 1], ["F#4", 1], ["D#4", 1], ["B3", 1],
]

static func define_all(audio: GameAudio) -> void:
	for sound: String in EFFECTS:
		audio.define(sound, EFFECTS[sound])

## The tune for a track id: "highland", "hollow", "boss" or "victory".
static func tune(track: String) -> Dictionary:
	match track:
		"highland":
			return {"bpm": 126, "voices": [
				{"wave": "pulse", "duty": 0.25, "volume": 0.2, "notes": HIGHLAND_LEAD},
				{"wave": "triangle", "volume": 0.34, "notes": _bass(HIGHLAND_CHORDS, [[0, 1], [0, 0.5], [2, 0.5], [0, 1], [2, 1]])},
				{"wave": "square", "volume": 0.07, "notes": _arpeggio(HIGHLAND_CHORDS, 0.5)},
				{"wave": "noise", "volume": 0.07, "release": 0.03, "notes": _hats(8, [0.5, 0.5, 0.25, 0.25, 0.5])},
			]}
		"hollow":
			return {"bpm": 96, "voices": [
				{"wave": "triangle", "volume": 0.3, "notes": HOLLOW_LEAD},
				{"wave": "sine", "volume": 0.3, "notes": _bass(HOLLOW_CHORDS, [[0, 2], [2, 1], [0, 1]])},
				{"wave": "pulse", "duty": 0.125, "volume": 0.06, "notes": _arpeggio(HOLLOW_CHORDS, 0.5)},
			]}
		"boss":
			return {"bpm": 156, "voices": [
				{"wave": "saw", "volume": 0.16, "notes": BOSS_LEAD},
				{"wave": "triangle", "volume": 0.36, "notes": _bass(BOSS_CHORDS, [[0, 0.5], [0, 0.5], [0, 0.5], [2, 0.5], [0, 0.5], [0, 0.5], [2, 0.5], [0, 0.5]])},
				{"wave": "noise", "volume": 0.09, "release": 0.02, "notes": _hats(8, [0.5, 0.25, 0.25])},
			]}
		_:
			return {"bpm": 132, "voices": [
				{"wave": "pulse", "duty": 0.5, "volume": 0.22, "notes": [["C5", 0.5], ["E5", 0.5], ["G5", 0.5], ["C6", 1.5], ["A5", 0.5], ["G5", 0.5], ["E5", 1], ["G5", 1], ["F5", 0.5], ["E5", 0.5], ["D5", 1], ["C5", 2], ["-", 2]]},
				{"wave": "triangle", "volume": 0.34, "notes": [["C3", 2], ["G2", 2], ["A2", 2], ["E2", 2], ["F2", 2], ["G2", 2]]},
			]}

## The bass line: `pattern` is [[chord tone index, beats], ...] played once per chord, one bar each.
static func _bass(chords: Array, pattern: Array) -> Array:
	var out: Array = []
	for chord: Array in chords:
		for step: Array in pattern:
			var tone := int(step[0])
			# The fifth is taken from the chord's upper notes, an octave down, so it stays under the lead.
			out.append([chord[0] if tone == 0 else _octave_down(str(chord[tone])), step[1]])
	return out

static func _arpeggio(chords: Array, beats: float) -> Array:
	var out: Array = []
	var order := [1, 2, 1, 2, 1, 2, 1, 2]
	for chord: Array in chords:
		for index in int(4.0 / beats):
			out.append([chord[order[index % order.size()]], beats])
	return out

## A noise voice ticking a rhythm for `bars` bars of four beats: each entry of `pattern` is one tick lasting that many beats, of which the first eighth sounds.
static func _hats(bars: int, pattern: Array) -> Array:
	var out: Array = []
	var total := 0.0
	var index := 0
	while total < float(bars) * 4.0 - 0.001:
		var beats := float(pattern[index % pattern.size()])
		out.append([108, 0.125])
		out.append(["-", beats - 0.125])
		total += beats
		index += 1
	return out

static func _octave_down(pitch: String) -> String:
	var octave := int(pitch.right(1))
	return pitch.left(pitch.length() - 1) + str(octave - 1)
