class_name GameAudio
extends Node

## Sound for game modules, of two kinds that can be mixed freely.
##
## Procedural: effects and simple tunes synthesised into PCM at run time, with no audio file and so no audio licence to track.
##   audio.define("jump", {"wave": "square", "freq": 330, "freq_end": 660, "duration": 0.12})
##   audio.define("coin", GameSfx.preset("coin"))
##   audio.play("jump")
##   audio.play_music({"bpm": 132, "voices": [{"wave": "square", "notes": [["C4", 1], ["E4", 1], ["G4", 2]]}]})
## An effect spec is described in GameSynth (layers, envelopes, filters, modulation, echo and room); GameSfx holds ready-made ones. A tune spec:
##   bpm       beats per minute (default 120)
##   voices    [{ wave, volume, duty, attack, release, notes }], mixed together; `notes` is [[pitch, beats], ...] where pitch is a note name ("C4", "F#3", "Bb2"), a MIDI number, or "-" / 0 for a rest
## The tune loops over the length of its longest voice (at most MAX_MUSIC_SECONDS).
##
## Recorded: audio files in the game's own directory (Ogg Vorbis; scripts/assets/ prepares them). DIR below stands for that directory's full resource path, written out in the game.
##   audio.load_music("stage", DIR + "audio/stage.ogg")
##   audio.load_stinger("clear", DIR + "audio/clear.ogg")
##   audio.load_sound("roar", DIR + "audio/roar.ogg")
##   audio.play_track("stage")              # loops; cross-fades from whatever was playing
##   audio.play_stinger("clear")            # one shot over the music, which is turned down while it plays and comes back after
##   audio.play("roar")                     # a loaded sound plays exactly like a defined one
##   audio.stop_music(1.0)                  # fade out over a second
##
## Effects play on the SFX bus, music and stingers on the Music bus; the player's volume settings act on those buses, never on the game. A paused run is silent and resumes where it stopped. In a headless run (tests, no audio device) nothing is started, but every call is tracked exactly as it would be: `played`, `music_playing`, `music_track` and `stinger_playing` read the same.
##
## Everything synthesised is deterministic: the same spec gives the same bytes, noise included. The random pitch variation of an effect (`vary`) is applied at play time, is presentation only and never touches a game's rng.

const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"
const EFFECT_RATE := GameSynth.RATE
const MUSIC_RATE := 11025
## Effects that can sound at once; one more replaces the oldest.
const VOICES := 8
const MAX_EFFECT_SECONDS := GameSynth.MAX_SECONDS
const MAX_MUSIC_SECONDS := 64.0
const WAVES := GameSynth.WAVES
const NOTE_OFFSETS := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

## What a stinger does to the music while it plays.
const STINGER_DUCK := &"duck"    ## turn the music down, bring it back afterwards (default)
const STINGER_PAUSE := &"pause"  ## hold the music where it is, continue from there afterwards
const STINGER_OVER := &"over"    ## leave the music alone
const STINGER_STOP := &"stop"    ## fade the music out for good (a game-over jingle)
## How far the music is turned down under a ducking stinger, in dB.
const DUCK_DB := -14.0
const DUCK_IN_SECONDS := 0.12
const DUCK_OUT_SECONDS := 0.7
## Default cross-fade of play_track, in seconds.
const TRACK_FADE := 0.8
## How long the music takes to fade when a run ends by itself, in seconds. GameModule.finish() uses it.
const END_FADE := 0.4
## The same effect asked for again within this many milliseconds is counted but not started a second time: two copies on top of each other are only louder and use up a voice.
const RETRIGGER_MSEC := 25
## The level below which a fading track counts as silent, in dB.
const SILENT_DB := -60.0

## How many times each named effect, stinger and track was asked for, including in headless runs where nothing is audible. Tests read it.
var played: Dictionary = {}
## Whether music was started and not stopped since.
var music_playing := false
## Name of the loaded track that is playing, "" when none is (a procedural tune has no name).
var music_track := ""
## Whether a stinger is sounding.
var stinger_playing := false

## Rendered effects are kept for the life of the process, keyed by their spec: a game defines the same effects every time a run starts, and a test starts hundreds of runs. Bytes, not streams, so nothing here is a resource that could outlive the engine.
static var _rendered: Dictionary = {}
static var _rendered_bytes := 0
const _RENDER_CACHE_BYTES := 48 * 1024 * 1024

var _sounds: Dictionary = {}
var _tracks: Dictionary = {}
var _stingers: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_started: Dictionary = {}
## Two music players, so one track can fade out while the next fades in. Per deck: the gain it has (0 .. 1), the gain it is heading for, how fast (per second), its own level in dB and whether it is in use.
var _decks: Array[AudioStreamPlayer] = []
var _deck_gain: Array[float] = [0.0, 0.0]
var _deck_target: Array[float] = [0.0, 0.0]
var _deck_speed: Array[float] = [0.0, 0.0]
var _deck_db: Array[float] = [0.0, 0.0]
var _deck_live: Array[bool] = [false, false]
var _current := 0
var _stinger: AudioStreamPlayer
var _stinger_left := 0.0
var _duck := 1.0
var _duck_target := 1.0
var _duck_speed := 0.0
var _held := false
var _paused := false
var _random := RandomNumberGenerator.new()
## The dummy audio driver of a headless run never releases a playing stream in time for exit, so nothing is actually started there.
var _audible := DisplayServer.get_name() != "headless"

func _init() -> void:
	name = "GameAudio"
	# Fades and stingers keep running after the host has frozen the finished run under the result screen; a paused run is frozen here, by set_paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Effect%d" % index
		player.bus = BUS_SFX
		add_child(player)
		_players.append(player)
	for index in 2:
		var deck := AudioStreamPlayer.new()
		deck.name = "Music%d" % index
		deck.bus = BUS_MUSIC
		add_child(deck)
		_decks.append(deck)
	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.bus = BUS_MUSIC
	add_child(_stinger)

func _exit_tree() -> void:
	stop_all()

func _process(delta: float) -> void:
	tick(delta)

# ---- effects ----

## Register a synthesised effect under a name. Synthesis happens here, once, not when the effect is played.
func define(sound: String, spec: Dictionary) -> void:
	var key := JSON.stringify(spec, "", true)
	var data: PackedByteArray
	if _rendered.has(key):
		data = _rendered[key]
	else:
		data = effect(spec).data
		if _rendered_bytes + data.size() > _RENDER_CACHE_BYTES:
			_rendered.clear()
			_rendered_bytes = 0
		_rendered[key] = data
		_rendered_bytes += data.size()
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = EFFECT_RATE
	stream.stereo = false
	stream.data = data
	var vary: Dictionary = spec["vary"] if spec.get("vary") is Dictionary else {}
	_sounds[sound] = {"stream": stream, "volume_db": 0.0, "vary": clampf(float(vary.get("pitch", 0.0)), 0.0, 0.5)}

## Register an effect that is an audio file of the game. `options`: { "volume_db": level of this sound (default 0), "vary": random pitch variation per play, 0 .. 0.5 (default 0) }. Returns false, and says why, when the file cannot be loaded.
func load_sound(sound: String, path: String, options: Dictionary = {}) -> bool:
	var stream := _load_stream(path)
	if stream == null:
		return false
	_sounds[sound] = {"stream": stream, "volume_db": float(options.get("volume_db", 0.0)), "vary": clampf(float(options.get("vary", 0.0)), 0.0, 0.5)}
	return true

func has_sound(sound: String) -> bool:
	return _sounds.has(sound)

## Play a defined or loaded effect. `pitch` scales its frequency (1.0 unchanged) and `gain_db` its level (0 unchanged). An unknown name does nothing and returns false.
func play(sound: String, pitch: float = 1.0, gain_db: float = 0.0) -> bool:
	if not _sounds.has(sound):
		return false
	played[sound] = int(played.get(sound, 0)) + 1
	if _audible and not _paused:
		var now := Time.get_ticks_msec()
		if now - int(_last_started.get(sound, -RETRIGGER_MSEC)) < RETRIGGER_MSEC:
			return true
		_last_started[sound] = now
		var entry: Dictionary = _sounds[sound]
		var vary: float = entry["vary"]
		var player := _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
		player.stream = entry["stream"]
		player.pitch_scale = clampf(pitch * (1.0 + _random.randf_range(-vary, vary)), 0.25, 4.0)
		player.volume_db = float(entry["volume_db"]) + gain_db
		player.play()
	return true

# ---- music ----

## Register a music file of the game under a name. `options`: { "volume_db": level of this track (default 0), "loop": whether it repeats (default true), "loop_start": seconds into the file where every repeat after the first begins (default 0) }. Returns false, and says why, when the file cannot be loaded.
func load_music(track: String, path: String, options: Dictionary = {}) -> bool:
	var stream := _load_stream(path)
	if stream == null:
		return false
	_set_loop(stream, bool(options.get("loop", true)), maxf(0.0, float(options.get("loop_start", 0.0))))
	_tracks[track] = {"stream": stream, "volume_db": float(options.get("volume_db", 0.0))}
	return true

func has_track(track: String) -> bool:
	return _tracks.has(track)

## Play a loaded track, cross-fading from whatever music was playing over `fade` seconds (0 cuts). Asking for the track that is already playing changes nothing, so a game can call this every time it enters a state. Returns false for an unknown name.
func play_track(track: String, fade: float = TRACK_FADE) -> bool:
	if not _tracks.has(track):
		return false
	if music_playing and music_track == track:
		return true
	played[track] = int(played.get(track, 0)) + 1
	var entry: Dictionary = _tracks[track]
	_start_music(entry["stream"], float(entry["volume_db"]), fade)
	music_track = track
	return true

## Start a synthesised looping tune, replacing the music that was playing. `volume_db` is the tune's own level under the Music bus.
func play_music(spec: Dictionary, volume_db: float = -8.0) -> void:
	_start_music(music(spec), volume_db, 0.0)
	music_track = ""

## Stop the music, fading it out over `fade` seconds (0 cuts). A stop never lengthens a fade that is already under way.
func stop_music(fade: float = 0.0) -> void:
	music_playing = false
	music_track = ""
	for index in 2:
		_fade_out(index, fade)
	_apply_levels()

## Register a short one-shot piece of music (stage clear, game over, a power-up fanfare) under a name. `options`: { "volume_db": level (default 0) }.
func load_stinger(stinger: String, path: String, options: Dictionary = {}) -> bool:
	var stream := _load_stream(path)
	if stream == null:
		return false
	_set_loop(stream, false, 0.0)
	_stingers[stinger] = {"stream": stream, "volume_db": float(options.get("volume_db", 0.0)), "seconds": maxf(0.05, stream.get_length())}
	return true

func has_stinger(stinger: String) -> bool:
	return _stingers.has(stinger)

## Play a loaded stinger once. `mode` says what happens to the music meanwhile: STINGER_DUCK (turned down, then back), STINGER_PAUSE (held, then continued), STINGER_OVER (untouched) or STINGER_STOP (faded out for good). A new stinger replaces the one that was playing. Returns false for an unknown name.
func play_stinger(stinger: String, mode: StringName = STINGER_DUCK) -> bool:
	if not _stingers.has(stinger):
		return false
	played[stinger] = int(played.get(stinger, 0)) + 1
	var entry: Dictionary = _stingers[stinger]
	_release_music()
	stinger_playing = true
	_stinger_left = float(entry["seconds"])
	match mode:
		STINGER_PAUSE:
			_held = true
		STINGER_STOP:
			stop_music(END_FADE)
		STINGER_OVER:
			pass
		_:
			_duck_target = db_to_linear(DUCK_DB)
			_duck_speed = (1.0 - _duck_target) / DUCK_IN_SECONDS
	_stinger.stop()
	_stinger.stream = entry["stream"]
	_stinger.volume_db = float(entry["volume_db"])
	if _audible:
		_stinger.play()
		_stinger.stream_paused = _paused
	_apply_levels()
	return true

func stop_stinger() -> void:
	_stinger.stop()
	_stinger.stream = null
	stinger_playing = false
	_stinger_left = 0.0
	_release_music()
	_apply_levels()

# ---- for the host ----

## Freeze or resume everything that is sounding. GameModule calls it when the run is paused.
func set_paused(paused: bool) -> void:
	_paused = paused
	for player in _players:
		player.stream_paused = paused
	_stinger.stream_paused = paused
	_apply_levels()

func stop_all() -> void:
	stop_music()
	stop_stinger()
	for player in _players:
		player.stop()
		player.stream = null

## Advance fades, ducking and the stinger clock by `delta` seconds. The node does this itself every frame; a headless test calls it to move time.
func tick(delta: float) -> void:
	if _paused or delta <= 0.0:
		return
	var changed := false
	for index in 2:
		if not _deck_live[index] or is_equal_approx(_deck_gain[index], _deck_target[index]):
			continue
		_deck_gain[index] = move_toward(_deck_gain[index], _deck_target[index], _deck_speed[index] * delta)
		changed = true
		if _deck_target[index] <= 0.0 and _deck_gain[index] <= 0.0:
			_silence(index)
	if not is_equal_approx(_duck, _duck_target):
		_duck = move_toward(_duck, _duck_target, _duck_speed * delta)
		changed = true
	if stinger_playing:
		_stinger_left -= delta
		if _stinger_left <= 0.0:
			stinger_playing = false
			_stinger_left = 0.0
			_release_music()
			changed = true
	if changed:
		_apply_levels()

## The level of each music player as a factor 0 .. 1 (fade times ducking), for tests: [deck 0, deck 1].
func music_levels() -> Array[float]:
	return [_level(0), _level(1)]

## Whether a pausing stinger is holding the music where it was.
func is_music_held() -> bool:
	return _held

func _start_music(stream: AudioStream, volume_db: float, fade: float) -> void:
	var incoming := _current
	if _deck_live[_current]:
		incoming = 1 - _current
		_fade_out(_current, fade)
	# The other deck may still be fading out an older track; the new one takes it over.
	_silence(incoming)
	_current = incoming
	_deck_live[incoming] = true
	_deck_db[incoming] = volume_db
	_deck_target[incoming] = 1.0
	_deck_gain[incoming] = 0.0 if fade > 0.0 else 1.0
	_deck_speed[incoming] = 1.0 / fade if fade > 0.0 else 0.0
	music_playing = true
	var deck := _decks[incoming]
	deck.stream = stream
	_apply_levels()
	if _audible:
		deck.play()
		deck.stream_paused = _paused or _held

func _fade_out(index: int, fade: float) -> void:
	if not _deck_live[index]:
		return
	if fade <= 0.0:
		_silence(index)
		return
	var speed := 1.0 / fade
	if _deck_target[index] <= 0.0 and _deck_speed[index] >= speed:
		return
	_deck_target[index] = 0.0
	_deck_speed[index] = speed

func _silence(index: int) -> void:
	_decks[index].stop()
	_decks[index].stream = null
	_deck_live[index] = false
	_deck_gain[index] = 0.0
	_deck_target[index] = 0.0

## Give the music back after a stinger: un-hold it and bring a ducked level up again.
func _release_music() -> void:
	_held = false
	_duck_target = 1.0
	_duck_speed = (1.0 - db_to_linear(DUCK_DB)) / DUCK_OUT_SECONDS

func _level(index: int) -> float:
	# An equal-power curve: two tracks that cross keep the same loudness through the middle of the fade.
	return sin(clampf(_deck_gain[index], 0.0, 1.0) * PI * 0.5) * _duck if _deck_live[index] else 0.0

func _apply_levels() -> void:
	for index in 2:
		var deck := _decks[index]
		deck.volume_db = _deck_db[index] + maxf(SILENT_DB, linear_to_db(maxf(_level(index), 0.000001)))
		deck.stream_paused = _paused or _held

## Load an audio file of a game. Works the same from the project directory and from an exported pack, where only the imported form of the file exists.
static func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_error("GameAudio: no audio file at %s (is it imported and committed with its .import file?)" % path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("GameAudio: %s is not an audio file Godot can play" % path)
	return stream

static func _set_loop(stream: AudioStream, loop: bool, loop_start: float) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
		(stream as AudioStreamOggVorbis).loop_offset = loop_start
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
		(stream as AudioStreamMP3).loop_offset = loop_start
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			var frame_bytes := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
			wav.loop_begin = int(loop_start * wav.mix_rate)
			@warning_ignore("integer_division")
			wav.loop_end = wav.data.size() / frame_bytes

# ---- synthesis ----

## Synthesise one effect into a 16-bit mono stream. See GameSynth for everything a spec can hold.
static func effect(spec: Dictionary) -> AudioStreamWAV:
	return _to_stream(GameSynth.render(spec, EFFECT_RATE), EFFECT_RATE, false)

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
