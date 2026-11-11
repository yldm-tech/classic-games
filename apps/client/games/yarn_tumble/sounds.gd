extends RefCounted

## Every sound of Yarn Tumble: the effect definitions, which effect answers which world event, and the three music loops. All of it is synthesised by the shared GameAudio.

const EFFECTS := {
	"jump": {"wave": "square", "freq": 300, "freq_end": 620, "duration": 0.11, "volume": 0.3},
	"shoot": {"wave": "triangle", "freq": 900, "freq_end": 520, "duration": 0.07, "volume": 0.45},
	"wrap": {"wave": "pulse", "freq": 520, "freq_end": 700, "duration": 0.07, "volume": 0.35, "duty": 0.3},
	"ball": {"wave": "pulse", "freq": 500, "freq_end": 1100, "duration": 0.2, "volume": 0.4, "duty": 0.5},
	"kick": {"wave": "square", "freq": 180, "freq_end": 90, "duration": 0.12, "volume": 0.5},
	"bounce": {"wave": "triangle", "freq": 240, "freq_end": 150, "duration": 0.09, "volume": 0.5},
	"thud": {"wave": "noise", "freq": 900, "freq_end": 300, "duration": 0.08, "volume": 0.3},
	"ko": {"wave": "square", "freq": 660, "freq_end": 1320, "duration": 0.14, "volume": 0.4},
	"burst": {"wave": "noise", "freq": 4000, "freq_end": 600, "duration": 0.22, "volume": 0.4, "release": 0.15},
	"gem": {"wave": "triangle", "freq": 1040, "freq_end": 1560, "duration": 0.09, "volume": 0.45},
	"power": {"wave": "pulse", "freq": 440, "freq_end": 1760, "duration": 0.3, "volume": 0.4, "duty": 0.25},
	"heart": {"wave": "sine", "freq": 660, "freq_end": 1320, "duration": 0.35, "volume": 0.5},
	"hurt": {"wave": "saw", "freq": 520, "freq_end": 70, "duration": 0.5, "volume": 0.45, "release": 0.2},
	"free": {"wave": "saw", "freq": 200, "freq_end": 420, "duration": 0.16, "volume": 0.35},
	"loosen": {"wave": "triangle", "freq": 500, "freq_end": 260, "duration": 0.14, "volume": 0.35},
	"spit": {"wave": "noise", "freq": 2400, "freq_end": 1200, "duration": 0.1, "volume": 0.3},
	"alert": {"wave": "square", "freq": 980, "freq_end": 980, "duration": 0.06, "volume": 0.3},
	"charge": {"wave": "saw", "freq": 140, "freq_end": 320, "duration": 0.25, "volume": 0.35},
	"hop": {"wave": "sine", "freq": 260, "freq_end": 520, "duration": 0.08, "volume": 0.25},
	"hurry": {"wave": "square", "freq": 740, "freq_end": 1480, "duration": 0.5, "volume": 0.4},
	"spark": {"wave": "noise", "freq": 6000, "freq_end": 9000, "duration": 0.4, "volume": 0.3},
	"note": {"wave": "pulse", "freq": 523, "freq_end": 523, "duration": 0.11, "volume": 0.4, "duty": 0.5},
	"gameover": {"wave": "triangle", "freq": 392, "freq_end": 98, "duration": 1.2, "volume": 0.5, "release": 0.4},
	"continue": {"wave": "pulse", "freq": 330, "freq_end": 990, "duration": 0.4, "volume": 0.4},
	"pop": {"wave": "sine", "freq": 1200, "freq_end": 400, "duration": 0.06, "volume": 0.4},
	"boss_hit": {"wave": "saw", "freq": 300, "freq_end": 120, "duration": 0.12, "volume": 0.45},
	"boss_down": {"wave": "noise", "freq": 3000, "freq_end": 200, "duration": 1.0, "volume": 0.5, "release": 0.5},
	"boom": {"wave": "noise", "freq": 1400, "freq_end": 300, "duration": 0.18, "volume": 0.35, "release": 0.12},
	"egg": {"wave": "sine", "freq": 700, "freq_end": 350, "duration": 0.12, "volume": 0.3},
	"hatch": {"wave": "square", "freq": 400, "freq_end": 800, "duration": 0.08, "volume": 0.25},
	"swoop": {"wave": "saw", "freq": 900, "freq_end": 180, "duration": 0.6, "volume": 0.3, "release": 0.2},
	"leap": {"wave": "square", "freq": 120, "freq_end": 360, "duration": 0.3, "volume": 0.35},
	"slam": {"wave": "noise", "freq": 700, "freq_end": 120, "duration": 0.35, "volume": 0.55, "release": 0.2},
	"throw": {"wave": "triangle", "freq": 1400, "freq_end": 700, "duration": 0.15, "volume": 0.4},
}

## World event -> effect, where the names differ or one effect serves several events.
const EVENT_SOUNDS := {"respawn": "hop", "join": "power", "boss_gone": "burst"}

## Short tunes played one note per entry: [steps to wait after the previous note, pitch factor of "note"].
const JINGLE_CLEAR := [[0, 1.0], [6, 1.26], [6, 1.5], [6, 2.0], [9, 1.5], [6, 2.0]]
const JINGLE_BOSS := [[0, 1.0], [5, 1.0], [5, 1.0], [8, 1.335], [10, 1.19], [8, 1.335], [8, 1.5], [10, 2.0]]
const JINGLE_STAGE := [[0, 1.5], [7, 2.0]]

static func define_all(audio: GameAudio) -> void:
	for sound: String in EFFECTS:
		audio.define(sound, EFFECTS[sound])

## The effect a world event asks for and the pitch to play it at; an empty name for a silent event.
static func for_event(event: Array) -> Array:
	var what := str(event[0])
	var pitch := 1.0
	match what:
		"wrap":
			pitch = 1.0 + 0.14 * int(event[3])
		"ko":
			pitch = 1.0 + 0.12 * mini(int(event[4]), 6)
		"jump", "shoot":
			pitch = 1.0 if int(event[3]) == 0 else 1.12
	var sound := str(EVENT_SOUNDS.get(what, what))
	return [sound if EFFECTS.has(sound) else "", pitch]

## Which loop a floor plays: 0 the lower tower, 1 the upper tower, 2 a guardian.
static func track_for(stage: int, boss_stage: bool) -> int:
	if boss_stage:
		return 2
	return 0 if stage < 8 else 1

static func music(track: int) -> Dictionary:
	match track:
		0:
			return {"bpm": 138, "voices": [
				{"wave": "pulse", "duty": 0.25, "volume": 0.2, "release": 0.04, "notes": _melody("E5 .5 G5 .5 C6 1 B5 .5 G5 .5 E5 1 F5 .5 A5 .5 C6 1 A5 1 F5 1 D5 .5 F5 .5 B5 1 A5 .5 G5 .5 D5 1 E5 1 G5 1 C5 2 E5 .5 G5 .5 C6 1 D6 .5 C6 .5 G5 1 A5 .5 C6 .5 F6 1 E6 1 C6 1 D6 .5 B5 .5 G5 1 A5 .5 B5 .5 D6 1 C6 2 - 1 G5 1")},
				{"wave": "triangle", "volume": 0.34, "release": 0.03, "notes": _melody("C3 1 G3 1 C3 1 G3 1 F2 1 C3 1 F2 1 C3 1 G2 1 D3 1 G2 1 D3 1 C3 1 G3 1 C3 1 E3 1 C3 1 G3 1 C3 1 G3 1 F2 1 C3 1 F2 1 A2 1 G2 1 D3 1 G2 1 B2 1 C3 1 G2 1 C3 1 - 1")},
				{"wave": "noise", "volume": 0.07, "release": 0.03, "notes": _beat(32, ["- .5 C8 .25 - .25", "- .5 C8 .25 C8 .25"])},
			]}
		1:
			return {"bpm": 150, "voices": [
				{"wave": "square", "volume": 0.17, "release": 0.04, "notes": _melody("A4 .5 C5 .5 E5 .5 A5 .5 G5 1 E5 1 F5 .5 E5 .5 D5 .5 C5 .5 D5 1 B4 1 C5 .5 E5 .5 G5 .5 C6 .5 B5 1 G5 1 A5 1 G#5 1 E5 2 A5 .5 A5 .5 C6 1 B5 .5 A5 .5 G5 1 F5 .5 A5 .5 D6 1 C6 1 A5 1 G#5 .5 B5 .5 E6 1 D6 .5 C6 .5 B5 1 A5 2 E5 1 - 1")},
				{"wave": "triangle", "volume": 0.34, "release": 0.03, "notes": _melody("A2 1 E3 1 A2 1 E3 1 D3 1 A2 1 G2 1 D3 1 C3 1 G3 1 C3 1 G3 1 E2 1 B2 1 E3 1 G#2 1 A2 1 E3 1 A2 1 E3 1 D3 1 A3 1 D3 1 F3 1 E3 1 B2 1 E3 1 G#3 1 A2 1 E3 1 A2 1 - 1")},
				{"wave": "noise", "volume": 0.08, "release": 0.03, "notes": _beat(32, ["C6 .25 - .25 C8 .25 - .25", "- .25 C8 .25 C8 .25 - .25"])},
			]}
		_:
			var bass := ""
			for root: String in ["D2", "Bb1", "F2", "A1", "D2", "G1", "A1", "D2"]:
				var octave := root.substr(0, root.length() - 1) + str(int(root.right(1)) + 1)
				bass += "%s .5 %s .5 %s .5 %s .5 %s .5 %s .5 %s .5 %s .5 " % [root, root, octave, root, root, root, octave, root]
			return {"bpm": 164, "voices": [
				{"wave": "square", "volume": 0.18, "release": 0.04, "notes": _melody("D5 .5 D5 .5 F5 .5 D5 .5 A5 1 G#5 1 G5 .5 F5 .5 E5 .5 F5 .5 D5 2 D5 .5 D5 .5 F5 .5 A5 .5 C6 1 Bb5 1 A5 .5 G5 .5 F5 .5 E5 .5 C#5 2 D6 1 C6 .5 Bb5 .5 A5 1 F5 1 G5 1 Bb5 .5 A5 .5 G5 1 E5 1 F5 .5 G5 .5 A5 .5 Bb5 .5 C#6 1 A5 1 D6 1.5 A5 .5 D5 2")},
				{"wave": "saw", "volume": 0.16, "release": 0.03, "notes": _melody(bass)},
				{"wave": "noise", "volume": 0.09, "release": 0.03, "notes": _beat(32, ["C5 .25 - .25 C8 .25 C8 .25", "C8 .25 - .25 C8 .25 - .25"])},
			]}

## "E5 .5 G5 1 - 2" -> [["E5", 0.5], ["G5", 1.0], ["-", 2.0]].
static func _melody(text: String) -> Array:
	var out: Array = []
	var words := text.split(" ", false)
	for index in range(0, words.size() - 1, 2):
		out.append([words[index], words[index + 1].to_float()])
	return out

## A one-beat pattern list repeated to fill `beats` beats.
static func _beat(beats: int, patterns: Array) -> Array:
	var text := ""
	for index in beats:
		text += str(patterns[index % patterns.size()]) + " "
	return _melody(text)
