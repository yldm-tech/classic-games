class_name ProceduralBGM
extends AudioStreamPlayer

var key := "ignition"

func configure(value: String) -> void:
	key = value if value != "" else "ignition"
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 4000
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = 400
	var pcm := PackedByteArray(); pcm.resize(wav.loop_end * 2)
	var base: float = 110.0 + float(abs(hash(key)) % 110)
	for i in wav.loop_end:
		var t := float(i) / wav.mix_rate
		var beat := 1.0 if fmod(t, 0.5) < 0.08 else 0.35
		var sample := clampi(roundi((sin(t * TAU * base) * .12 * beat + sin(t * TAU * base * 1.5) * .04) * 32767.0), -32768, 32767)
		pcm[i * 2] = sample & 0xff; pcm[i * 2 + 1] = (sample >> 8) & 0xff
	wav.data = pcm; stream = wav; volume_db = -18.0; set_meta("bgm_key", key)

func _ready() -> void:
	if DisplayServer.get_name() != "headless": play()
