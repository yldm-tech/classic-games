extends SceneTree

## Writes GameSfx presets as WAV files, so they can be measured, listened to outside the game or turned into audio files:
##   godot --headless --path apps/client --script res://games/shared/synth_dump.gd -- <output directory> [preset ...]
## Without preset names every preset is written. Prints one line per file with its length and peak.

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		printerr("synth_dump: give an output directory after --")
		quit.call_deferred(2)
		return
	var directory := arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var wanted := arguments.slice(1) if arguments.size() > 1 else GameSfx.names()
	var failed := false
	for preset_name: String in wanted:
		if not GameSfx.has(preset_name):
			printerr("synth_dump: there is no preset \"%s\"" % preset_name)
			failed = true
			continue
		var stream := GameAudio.effect(GameSfx.preset(preset_name))
		var path := directory.path_join(preset_name + ".wav")
		if stream.save_to_wav(path) != OK:
			printerr("synth_dump: cannot write %s" % path)
			failed = true
			continue
		var peak := 0
		for index in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(index)))
		@warning_ignore("integer_division")
		print("synth_dump: %s %.3fs peak %.3f" % [path, float(stream.data.size() / 2) / float(stream.mix_rate), float(peak) / 32768.0])
	quit.call_deferred(1 if failed else 0)
