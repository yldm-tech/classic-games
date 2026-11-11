extends SceneTree

## Loads every picture, audio file and sprite frame table of every game under the games roots, the way a game does at run time. The export check (scripts/check-export-discovery.sh) runs it inside an exported pack, where the source files are gone and only their imported forms remain: a medium that is missing from the pack, or that cannot be loaded there, fails here and not in a player's hands.
## Prints one line per problem and ends with "media_check: <n> images, <m> audio files, <k> frame tables, <p> problems".

const Registry := preload("res://games/shared/game_registry.gd")

const ROOTS_ENV := "GAME_CHECK_ROOTS"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

func _initialize() -> void:
	var problems := PackedStringArray()
	var images := 0
	var sounds := 0
	var tables := 0
	var roots := OS.get_environment(ROOTS_ENV).split(",", false)
	if roots.is_empty():
		roots = PackedStringArray([Registry.GAMES_ROOT])
	for root_dir: String in roots:
		for game: Dictionary in Registry.discover(root_dir.strip_edges())["games"]:
			var dir := str(game["dir"])
			for file in _files(dir, ""):
				var path := dir.path_join(file)
				var extension := file.get_extension().to_lower()
				if extension in IMAGE_EXTENSIONS:
					images += 1
					var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
					if texture == null or texture.get_width() <= 0:
						problems.append("%s: the image cannot be loaded" % path)
				elif extension in AUDIO_EXTENSIONS:
					sounds += 1
					var stream := load(path) as AudioStream if ResourceLoader.exists(path) else null
					if stream == null or stream.get_length() <= 0.0:
						problems.append("%s: the audio file cannot be loaded" % path)
				elif extension == "json" and file != "game.json":
					var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
					if parsed is Dictionary and (parsed as Dictionary).get("frames") is Dictionary and (parsed as Dictionary).has("image"):
						tables += 1
						var sheet := GameSprites.load_atlas(path)
						if sheet.texture == null or sheet.frame_names().size() != ((parsed as Dictionary)["frames"] as Dictionary).size():
							problems.append("%s: the frame table or its image cannot be loaded" % path)
	for line in problems:
		printerr("media_check: " + line)
	print("media_check: %d images, %d audio files, %d frame tables, %d problems" % [images, sounds, tables, problems.size()])
	quit.call_deferred(0 if problems.is_empty() else 1)

## Every file under `dir`, as paths relative to it, by the name a game loads it with. In an exported pack a medium is listed by its import or remap record (hero.png.import) rather than by itself, so those suffixes are dropped and each name is reported once.
func _files(dir: String, prefix: String) -> PackedStringArray:
	var seen := {}
	for file in DirAccess.get_files_at(dir):
		seen[file.trim_suffix(".import").trim_suffix(".remap")] = true
	var out := PackedStringArray()
	for file: String in seen:
		out.append(prefix + file)
	for folder in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(folder), prefix + folder + "/"))
	return out
