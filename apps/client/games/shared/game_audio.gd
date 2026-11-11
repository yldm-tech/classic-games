class_name GameAudio
extends Node

## Procedural sound for game modules: short effects and looping music are synthesised into PCM at run time, so a game ships sound without any audio file (and so without any audio licence to track). Effects play on the SFX bus and music on the Music bus; the player's volume settings act on those buses, never on the game.
##
## GameModule creates one as `audio`. Typical use:
##   audio.define("jump", {"wave": "square", "freq": 330, "freq_end": 660, "duration": 0.12})
##   audio.play("jump")
##   audio.play_music({"bpm": 132, "voices": [{"wave": "square", "notes": [["C4", 1], ["E4", 1], ["G4", 2]]}]})
##
## An effect spec:
##   wave      "square" (default) | "pulse" | "triangle" | "saw" | "sine" | "noise"
##   freq      Hz at the start (default 440); for noise, how often the noise value changes
##   freq_end  Hz at the end (default freq), for slides
##   duration  seconds (default 0.15, at most MAX_EFFECT_SECONDS)
##   volume    0 .. 1 (default 0.5)
##   attack    seconds of fade in (default 0.004)
##   release   seconds of fade out at the end (default 0.05)
##   duty      pulse width of "pulse", 0 .. 1 (default 0.25)
##
## A music spec:
##   bpm       beats per minute (default 120)
##   voices    [{ wave, volume, duty, notes }], mixed together; `notes` is [[pitch, beats], ...] where pitch is a note name ("C4", "F#3", "Bb2"), a MIDI number, or "-" / 0 for a rest
## The tune loops over the length of its longest voice (at most MAX_MUSIC_SECONDS).
##
## Everything here is deterministic: the same spec gives the same bytes, noise included.

const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"
const EFFECT_RATE := 22050
const MUSIC_RATE := 11025
const VOICES := 6
const MAX_EFFECT_SECONDS := 2.0
const MAX_MUSIC_SECONDS := 64.0
const WAVES := ["square", "pulse", "triangle", "saw", "sine", "noise"]
const NOTE_OFFSETS := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

## How many times each named effect was asked for, including in headless runs where nothing is audible. Tests read it.
var played: Dictionary = {}
## Whether music was started and not stopped since.
var music_playing := false

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music: AudioStreamPlayer
var _paused := false
## The dummy audio driver of a headless run never releases a playing stream in time for exit, so nothing is actually started there.
var _audible := DisplayServer.get_name() != "headless"

func _init() -> void:
	name = "GameAudio"
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Effect%d" % index
		player.bus = BUS_SFX
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = BUS_MUSIC
	add_child(_music)

func _exit_tree() -> void:
	stop_all()

# ---- effects ----

## Register an effect under a name. Synthesis happens here, once, not when the effect is played.
func define(sound: String, spec: Dictionary) -> void:
	_sounds[sound] = effect(spec)

func has_sound(sound: String) -> bool:
	return _sounds.has(sound)

## Play a defined effect. `pitch` scales its frequency (1.0 unchanged). An unknown name does nothing and returns false.
func play(sound: String, pitch: float = 1.0) -> bool:
	if not _sounds.has(sound):
		return false
	played[sound] = int(played.get(sound, 0)) + 1
	if _audible and not _paused:
		var player := _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
		player.stream = _sounds[sound]
		player.pitch_scale = clampf(pitch, 0.25, 4.0)
		player.play()
	return true

# ---- music ----

## Start a looping tune, replacing the one that was playing. `volume_db` is the tune's own level under the Music bus.
func play_music(spec: Dictionary, volume_db: float = -8.0) -> void:
	_music.stop()
	_music.stream = music(spec)
	_music.volume_db = volume_db
	music_playing = true
	if _audible:
		_music.play()
		_music.stream_paused = _paused

func stop_music() -> void:
	_music.stop()
	_music.stream = null
	music_playing = false

## Freeze or resume everything that is sounding. GameModule calls it when the run is paused.
func set_paused(paused: bool) -> void:
	_paused = paused
	_music.stream_paused = paused
	for player in _players:
		player.stream_paused = paused

func stop_all() -> void:
	stop_music()
	for player in _players:
		player.stop()
		player.stream = null

# ---- synthesis ----

## Synthesise one effect into a 16-bit mono stream.
static func effect(spec: Dictionary) -> AudioStreamWAV:
	var seconds := clampf(float(spec.get("duration", 0.15)), 0.01, MAX_EFFECT_SECONDS)
	var count := maxi(1, int(seconds * EFFECT_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	_render(samples, 0, count, EFFECT_RATE, spec, float(spec.get("freq", 440.0)), float(spec.get("freq_end", spec.get("freq", 440.0))))
	return _to_stream(samples, EFFECT_RATE, false)

## Synthesise a looping tune into a 16-bit mono stream.
static func music(spec: Dictionary) -> AudioStreamWAV:
	var beat := 60.0 / clampf(float(spec.get("bpm", 120.0)), 30.0, 300.0)
	var voices: Array = spec.get("voices", []) if spec.get("voices") is Array else []
	var longest := 0.0
	for voice: Variant in voices:
		if voice is Dictionary:
			longest = maxf(longest, _beats(voice) * beat)
	var count := maxi(1, int(minf(longest, MAX_MUSIC_SECONDS) * MUSIC_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	for voice: Variant in voices:
		if not voice is Dictionary:
			continue
		var at := 0.0
		for note: Variant in (voice as Dictionary).get("notes", []):
			if not (note is Array and (note as Array).size() >= 2):
				continue
			var length := maxf(0.0, float(note[1])) * beat
			var frequency := note_frequency(note[0])
			var first := int(at * MUSIC_RATE)
			var last := mini(count, int((at + length) * MUSIC_RATE))
			if frequency > 0.0 and last > first:
				_render(samples, first, last - first, MUSIC_RATE, voice, frequency, frequency)
			at += length
	return _to_stream(samples, MUSIC_RATE, true)

## Frequency in Hz of a note name ("A4" is 440), a MIDI number, or 0 for a rest or anything unreadable.
static func note_frequency(pitch: Variant) -> float:
	var midi := -1
	if pitch is int or pitch is float:
		midi = int(pitch)
	elif pitch is String:
		var text := (pitch as String).strip_edges()
		if text.length() >= 2 and NOTE_OFFSETS.has(text.substr(0, 1).to_upper()):
			var offset := int(NOTE_OFFSETS[text.substr(0, 1).to_upper()])
			var rest := text.substr(1)
			if rest.begins_with("#"):
				offset += 1
				rest = rest.substr(1)
			elif rest.begins_with("b"):
				offset -= 1
				rest = rest.substr(1)
			if rest.is_valid_int():
				midi = (int(rest) + 1) * 12 + offset
	if midi <= 0 or midi > 127:
		return 0.0
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)

static func _beats(voice: Dictionary) -> float:
	var total := 0.0
	for note: Variant in voice.get("notes", []):
		if note is Array and (note as Array).size() >= 2:
			total += maxf(0.0, float(note[1]))
	return total

## Add one tone to `samples[first .. first + count)`.
static func _render(samples: PackedFloat32Array, first: int, count: int, rate: int, spec: Dictionary, from_hz: float, to_hz: float) -> void:
	var wave := str(spec.get("wave", "square"))
	var volume := clampf(float(spec.get("volume", 0.5)), 0.0, 1.0)
	var duty := clampf(float(spec.get("duty", 0.25)), 0.05, 0.95) if wave == "pulse" else 0.5
	var attack := maxi(1, int(maxf(0.0, float(spec.get("attack", 0.004))) * rate))
	var release := maxi(1, int(maxf(0.0, float(spec.get("release", 0.05))) * rate))
	var phase := 0.0
	# Noise is a linear-feedback shift register, so it is the same on every run.
	var register := 0x7FFF
	var noise := 1.0
	for index in count:
		var progress := float(index) / float(count)
		var frequency := lerpf(from_hz, to_hz, progress)
		var before := phase
		phase = fmod(phase + frequency / float(rate), 1.0)
		var value := 0.0
		match wave:
			"triangle":
				value = 4.0 * absf(phase - 0.5) - 1.0
			"saw":
				value = 2.0 * phase - 1.0
			"sine":
				value = sin(phase * TAU)
			"noise":
				if phase < before:
					var bit := (register ^ (register >> 1)) & 1
					register = (register >> 1) | (bit << 14)
					noise = 1.0 if (register & 1) == 1 else -1.0
				value = noise
			_:
				value = 1.0 if phase < duty else -1.0
		var envelope := minf(1.0, float(index) / float(attack)) * minf(1.0, float(count - index) / float(release))
		samples[first + index] += value * volume * envelope

static func _to_stream(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index in samples.size():
		data.encode_s16(index * 2, clampi(roundi(samples[index] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
