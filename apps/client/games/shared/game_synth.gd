class_name GameSynth
extends RefCounted

## The procedural sound-effect synthesiser behind GameAudio.define(). It turns a spec (a Dictionary) into mono samples: one or more layers, each an oscillator or a noise source with its own pitch movement, ADSR envelope, modulation and filter, mixed and then sent through an optional saturation, delay and reverb. Everything is deterministic: the same spec gives the same samples on every machine, noise included.
##
## A spec is either one layer (the keys below at the top level, which is the form every older define() call uses) or { "layers": [layer, ...] } with these keys beside it:
##   duration   seconds of the body (default: where the longest layer ends; 0.15 for a single layer)
##   volume     master level, 0 .. 1 (default 1 with layers). With "normalize" it is the peak of the result.
##   normalize  true scales the result so that its peak equals `volume`. Presets use it, so a preset's loudness does not depend on how its layers happen to add up.
##   drive      0 .. 1, soft saturation (adds body and grit; 0 is off)
##   delay      { "time": seconds, "feedback": 0 .. 0.9, "mix": 0 .. 1 }, an echo
##   reverb     { "mix": 0 .. 1, "size": 0 .. 1, "damp": 0 .. 1 }, a small room
##   tail       seconds added after the body for the echo and the room to ring out (default 0.6 when either is set, else 0)
##   vary       { "pitch": 0 .. 0.5 } is read by GameAudio.play(): each play is transposed by a random factor within that fraction, so a repeated effect does not sound like a machine gun
##
## A layer:
##   wave       "square" (default) | "pulse" | "triangle" | "saw" | "sine" | "noise" (a clocked shift register: the gritty kind, `freq` is how often it changes) | "white" | "pink"
##   freq       Hz at the start (default 440)
##   freq_end   Hz at the end (default freq)
##   glide      "linear" (default) | "exp" (equal musical steps per second, the natural choice for sweeps)
##   glide_time 0 .. 1, the part of the layer over which the pitch travels before it holds (default 1)
##   steps      [factor, ...]: the pitch jumps through these multipliers in equal parts of the layer (an arpeggio; [1, 1.5] is the two-note chime)
##   vibrato    { "rate": Hz, "depth": semitones }
##   start      seconds from the start of the effect (default 0)
##   duration   seconds (default: to the end of the body)
##   volume     0 .. 1 (default 0.5)
##   attack     seconds of fade in (default 0.004)
##   decay      seconds from the peak down to `sustain` (default 0)
##   sustain    0 .. 1, the level held after the decay (default 1)
##   release    seconds of fade out at the end (default 0.05)
##   curve      exponent applied to the envelope: 1 is straight (default), 2 or 3 falls away quickly like something struck
##   duty       pulse width of "pulse", 0 .. 1 (default 0.25); duty_end sweeps it
##   unison     1 .. 3 detuned copies (default 1) and detune, their spread in cents (default 12)
##   fm         { "ratio": modulator frequency / freq, "index": depth at the start, "index_end": depth at the end }: phase modulation, for bells, metal and growls
##   ring       { "freq": Hz, "freq_end": Hz, "mix": 0 .. 1 }: multiplies by a sine, for tremolo (slow) or clang (fast)
##   filter     { "type": "lowpass" | "highpass" | "bandpass", "cutoff": Hz, "cutoff_end": Hz, "q": 0.3 .. 12 }: the cutoff sweeps exponentially over the layer
##   seed       integer, makes two noise layers differ (default: the layer's index)

const RATE := 32000
const MAX_SECONDS := 4.0
const WAVES := ["square", "pulse", "triangle", "saw", "sine", "noise", "white", "pink"]
const DEFAULT_TAIL := 0.6

const _SQUARE := 0
const _PULSE := 1
const _TRIANGLE := 2
const _SAW := 3
const _SINE := 4
const _NOISE := 5
const _WHITE := 6
const _PINK := 7

## Samples in the result for a spec at a rate. render() returns exactly this many.
static func length(spec: Dictionary, rate: int = RATE) -> int:
	return maxi(1, int(minf(_body_seconds(spec) + _tail_seconds(spec), MAX_SECONDS) * rate))

## Synthesise a spec into mono samples in -1 .. 1.
static func render(spec: Dictionary, rate: int = RATE) -> PackedFloat32Array:
	var layered := spec.get("layers") is Array
	var body := _body_seconds(spec)
	var count := length(spec, rate)
	var body_count := clampi(int(body * rate), 1, count)
	var samples := PackedFloat32Array()
	samples.resize(count)
	if layered:
		var index := 0
		for layer: Variant in spec["layers"]:
			if layer is Dictionary:
				var first := clampi(int(maxf(0.0, float((layer as Dictionary).get("start", 0.0))) * rate), 0, body_count - 1)
				var wanted := body_count - first
				if (layer as Dictionary).has("duration"):
					wanted = mini(wanted, maxi(1, int(float(layer["duration"]) * rate)))
				_layer(samples, first, wanted, rate, layer, index)
			index += 1
	else:
		_layer(samples, 0, body_count, rate, spec, 0)
	var master := clampf(float(spec.get("volume", 1.0)), 0.0, 1.0) if layered else 1.0
	if layered:
		_block_dc(samples)
	var drive := clampf(float(spec.get("drive", 0.0)), 0.0, 1.0)
	if drive > 0.0:
		_saturate(samples, drive)
	if spec.get("delay") is Dictionary:
		_delay(samples, rate, spec["delay"])
	if spec.get("reverb") is Dictionary:
		_reverb(samples, rate, spec["reverb"])
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	var gain := master
	if bool(spec.get("normalize", false)) and peak > 0.0001:
		gain = master / peak
	elif peak * master > 0.98:
		# Layers that add up past full scale are turned down as a whole rather than clipped.
		gain = 0.98 / peak
	if not is_equal_approx(gain, 1.0):
		for index in count:
			samples[index] *= gain
	if count > body_count:
		# Whatever is still ringing when the tail runs out is faded, so the end never clicks.
		var fade := mini(count, int(0.03 * rate))
		for index in fade:
			samples[count - 1 - index] *= float(index) / float(fade)
	return samples

static func _body_seconds(spec: Dictionary) -> float:
	var body := 0.15
	if spec.has("duration"):
		body = float(spec["duration"])
	elif spec.get("layers") is Array:
		body = 0.0
		for layer: Variant in spec["layers"]:
			if layer is Dictionary:
				body = maxf(body, maxf(0.0, float((layer as Dictionary).get("start", 0.0))) + float((layer as Dictionary).get("duration", 0.15)))
	return clampf(body, 0.01, MAX_SECONDS)

static func _tail_seconds(spec: Dictionary) -> float:
	var rings := spec.get("delay") is Dictionary or spec.get("reverb") is Dictionary
	return clampf(float(spec.get("tail", DEFAULT_TAIL if rings else 0.0)), 0.0, MAX_SECONDS)

## Add one layer to `samples[first .. first + count)`.
static func _layer(samples: PackedFloat32Array, first: int, count: int, rate: int, layer: Dictionary, index: int) -> void:
	if count <= 0:
		return
	var wave := maxi(0, WAVES.find(str(layer.get("wave", "square"))))
	var volume := clampf(float(layer.get("volume", 0.5)), 0.0, 1.0)
	var duty_from := clampf(float(layer.get("duty", 0.25)), 0.05, 0.95) if wave == _PULSE else 0.5
	var duty_to := clampf(float(layer.get("duty_end", duty_from)), 0.05, 0.95) if wave == _PULSE else 0.5
	var attack := maxi(1, int(maxf(0.0, float(layer.get("attack", 0.004))) * rate))
	var release := maxi(1, int(maxf(0.0, float(layer.get("release", 0.05))) * rate))
	var decay := maxi(0, int(maxf(0.0, float(layer.get("decay", 0.0))) * rate))
	var sustain := clampf(float(layer.get("sustain", 1.0)), 0.0, 1.0)
	var curve := clampf(float(layer.get("curve", 1.0)), 0.25, 8.0)
	var from_hz := maxf(0.01, float(layer.get("freq", 440.0)))
	var to_hz := maxf(0.01, float(layer.get("freq_end", from_hz)))
	var glides := not is_equal_approx(from_hz, to_hz)
	var exponential := str(layer.get("glide", "linear")) == "exp"
	var glide_time := clampf(float(layer.get("glide_time", 1.0)), 0.001, 1.0)
	var octaves := log(to_hz / from_hz)
	var steps := PackedFloat32Array()
	if layer.get("steps") is Array:
		for factor: Variant in layer["steps"]:
			steps.append(maxf(0.01, float(factor)))
	var vibrato: Dictionary = layer["vibrato"] if layer.get("vibrato") is Dictionary else {}
	var vibrato_step := float(vibrato.get("rate", 0.0)) * TAU / float(rate)
	var vibrato_depth := float(vibrato.get("depth", 0.0)) * 0.05776
	var fm: Dictionary = layer["fm"] if layer.get("fm") is Dictionary else {}
	var fm_ratio := float(fm.get("ratio", 0.0))
	var fm_from := float(fm.get("index", 0.0)) / TAU
	var fm_to := float(fm.get("index_end", fm.get("index", 0.0))) / TAU
	var has_fm := fm_ratio > 0.0 and (fm_from != 0.0 or fm_to != 0.0)
	var ring: Dictionary = layer["ring"] if layer.get("ring") is Dictionary else {}
	var ring_from := float(ring.get("freq", 0.0))
	var ring_to := float(ring.get("freq_end", ring_from))
	var ring_mix := clampf(float(ring.get("mix", 1.0)), 0.0, 1.0) if ring_from > 0.0 else 0.0
	var unison := clampi(int(layer.get("unison", 1)), 1, 3)
	var detune := float(layer.get("detune", 12.0)) / 1200.0 * 0.6931
	var filter: Dictionary = layer["filter"] if layer.get("filter") is Dictionary else {}
	var filter_type := ["lowpass", "highpass", "bandpass"].find(str(filter.get("type", "lowpass"))) if not filter.is_empty() else -1
	var cutoff_from := clampf(float(filter.get("cutoff", 2000.0)), 20.0, rate * 0.45)
	var cutoff_ratio := log(clampf(float(filter.get("cutoff_end", cutoff_from)), 20.0, rate * 0.45) / cutoff_from)
	var damping := 1.0 / clampf(float(filter.get("q", 0.707)), 0.3, 12.0)
	var low := 0.0
	var band := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	# Noise state. The clocked register is the same on every run; the white source is a linear congruential generator seeded per layer.
	var register := 0x7FFF
	var held := 1.0
	var state := (int(layer.get("seed", index)) * 7919 + 104729) & 0x7FFFFFFF
	var pink_a := 0.0
	var pink_b := 0.0
	var pink_c := 0.0
	var phases := PackedFloat64Array()
	phases.resize(unison)
	var spreads := PackedFloat64Array()
	for voice in unison:
		spreads.append(exp(detune * (float(voice) - float(unison - 1) * 0.5)) if unison > 1 else 1.0)
	var fm_phase := 0.0
	var ring_phase := 0.0
	var inverse := 1.0 / float(count)
	var inverse_rate := 1.0 / float(rate)
	var frequency := from_hz
	var voice_gain := 1.0 / sqrt(float(unison))
	var step_count := steps.size()
	for offset in count:
		var progress := float(offset) * inverse
		if glides:
			var travelled := minf(1.0, progress / glide_time)
			frequency = from_hz * exp(octaves * travelled) if exponential else lerpf(from_hz, to_hz, travelled)
		var hz := frequency
		if step_count > 0:
			hz *= steps[mini(step_count - 1, int(progress * step_count))]
		if vibrato_depth != 0.0:
			hz *= 1.0 + vibrato_depth * sin(float(offset) * vibrato_step)
		var modulation := 0.0
		if has_fm:
			fm_phase += hz * fm_ratio * inverse_rate
			fm_phase -= floorf(fm_phase)
			modulation = lerpf(fm_from, fm_to, progress) * sin(fm_phase * TAU)
		var value := 0.0
		if wave >= _NOISE:
			var white := 0.0
			if wave == _NOISE:
				var before := phases[0]
				var after := before + hz * inverse_rate
				after -= floorf(after)
				phases[0] = after
				if after < before:
					var bit := (register ^ (register >> 1)) & 1
					register = (register >> 1) | (bit << 14)
					held = 1.0 if (register & 1) == 1 else -1.0
				value = held
			else:
				state = (state * 1103515245 + 12345) & 0x7FFFFFFF
				white = float(state) / 1073741824.0 - 1.0
				if wave == _PINK:
					pink_a = 0.99765 * pink_a + white * 0.0990460
					pink_b = 0.96300 * pink_b + white * 0.2965164
					pink_c = 0.57000 * pink_c + white * 1.0526913
					value = (pink_a + pink_b + pink_c + white * 0.1848) * 0.22
				else:
					value = white
		else:
			var duty := lerpf(duty_from, duty_to, progress) if wave == _PULSE else 0.5
			for voice in unison:
				var step := hz * spreads[voice] * inverse_rate
				var phase := phases[voice] + step
				phase -= floorf(phase)
				phases[voice] = phase
				var at := phase + modulation
				at -= floorf(at)
				match wave:
					_SINE:
						value += sin(at * TAU)
					_TRIANGLE:
						value += 4.0 * absf(at - 0.5) - 1.0
					_SAW:
						value += 2.0 * at - 1.0 - _blep(at, step)
					_:
						var edge := at - duty
						if edge < 0.0:
							edge += 1.0
						value += (1.0 if at < duty else -1.0) + _blep(at, step) - _blep(edge, step)
			value *= voice_gain
		if ring_mix > 0.0:
			ring_phase += lerpf(ring_from, ring_to, progress) * inverse_rate
			ring_phase -= floorf(ring_phase)
			value *= 1.0 - ring_mix + ring_mix * sin(ring_phase * TAU)
		if filter_type >= 0:
			# The coefficients follow the sweep every 16 samples; in between the cutoff has moved by a fraction of a percent.
			if (offset & 15) == 0:
				var g := tan(PI * minf(cutoff_from * exp(cutoff_ratio * progress), rate * 0.45) * inverse_rate)
				a1 = 1.0 / (1.0 + g * (g + damping))
				a2 = g * a1
				a3 = g * a2
			var v3 := value - low
			var v1 := a1 * band + a2 * v3
			var v2 := low + a2 * band + a3 * v3
			band = 2.0 * v1 - band
			low = 2.0 * v2 - low
			match filter_type:
				0:
					value = v2
				1:
					value = value - damping * v1 - v2
				_:
					value = v1 * damping
		var envelope := minf(1.0, float(offset) / float(attack)) * minf(1.0, float(count - offset) / float(release))
		if sustain < 1.0 and offset > attack:
			envelope *= sustain if decay <= 0 or offset >= attack + decay else lerpf(1.0, sustain, float(offset - attack) / float(decay))
		if curve != 1.0:
			envelope = pow(envelope, curve)
		samples[first + offset] += value * volume * envelope

## The polynomial correction that rounds the step of a saw or a square over the two samples around it, which removes most of the aliasing a naive edge produces.
static func _blep(phase: float, step: float) -> float:
	if step <= 0.0:
		return 0.0
	if phase < step:
		var early := phase / step
		return early + early - early * early - 1.0
	if phase > 1.0 - step:
		var late := (phase - 1.0) / step
		return late * late + late + late + 1.0
	return 0.0

## Remove any constant offset (an asymmetric pulse and ring-modulated noise both have one): it costs headroom and thumps when the effect starts and stops.
static func _block_dc(samples: PackedFloat32Array) -> void:
	var previous := 0.0
	var out := 0.0
	for index in samples.size():
		var value := samples[index]
		out = value - previous + 0.995 * out
		previous = value
		samples[index] = out

static func _saturate(samples: PackedFloat32Array, drive: float) -> void:
	var gain := 1.0 + drive * 7.0
	var makeup := 1.0 / tanh(gain)
	for index in samples.size():
		samples[index] = tanh(samples[index] * gain) * makeup

static func _delay(samples: PackedFloat32Array, rate: int, spec: Dictionary) -> void:
	var gap := maxi(1, int(clampf(float(spec.get("time", 0.12)), 0.005, 1.0) * rate))
	var feedback := clampf(float(spec.get("feedback", 0.35)), 0.0, 0.9)
	var mix := clampf(float(spec.get("mix", 0.3)), 0.0, 1.0)
	var count := samples.size()
	var wet := PackedFloat32Array()
	wet.resize(count)
	# Each repeat is a little duller than the one before, as an echo off a wall is.
	var smooth := 0.0
	for index in range(gap, count):
		smooth += 0.55 * (samples[index - gap] + wet[index - gap] * feedback - smooth)
		wet[index] = smooth
	for index in count:
		samples[index] += wet[index] * mix

## Four damped comb filters into two all-pass filters: the classic small-room reverberator.
static func _reverb(samples: PackedFloat32Array, rate: int, spec: Dictionary) -> void:
	var mix := clampf(float(spec.get("mix", 0.2)), 0.0, 1.0)
	var size := clampf(float(spec.get("size", 0.5)), 0.0, 1.0)
	var damp := clampf(float(spec.get("damp", 0.4)), 0.0, 0.95)
	var count := samples.size()
	var feedback := 0.70 + 0.2 * size
	var wet := PackedFloat32Array()
	wet.resize(count)
	var line := PackedFloat32Array()
	line.resize(count)
	for seconds: float in [0.0297, 0.0371, 0.0411, 0.0437]:
		var gap := maxi(1, int(seconds * (0.6 + 0.8 * size) * rate))
		var smooth := 0.0
		for index in count:
			var echo := line[index - gap] if index >= gap else 0.0
			smooth += (1.0 - damp) * (echo - smooth)
			line[index] = samples[index] + smooth * feedback
			wet[index] += echo * 0.25
	for seconds: float in [0.005, 0.0017]:
		var gap := maxi(1, int(seconds * rate))
		for index in count:
			var delayed := line[index - gap] if index >= gap else 0.0
			var value := wet[index] + delayed * 0.5
			line[index] = value
			wet[index] = delayed - value * 0.5
	for index in count:
		samples[index] += wet[index] * mix
