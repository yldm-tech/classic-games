extends SceneTree

## Headless tests of the shared support for recorded audio and high-resolution art (games/shared/game_audio.gd, game_sprites.gd, game_text.gd), against the media of the fixture module testing/games/fixture_gallery/. There is no audio device and no screen here, so what is tested is everything short of the speaker and the pixel: files load, tracks cross-fade, stingers duck and give the music back, pause freezes all of it, frames come out at the right stage size in the right place.

const DIR := "res://testing/games/fixture_gallery/"

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_tracks()
	_test_stingers()
	_test_sounds()
	_test_sprites()
	await _test_drawing()
	print("media_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _audio() -> GameAudio:
	var audio := GameAudio.new()
	root.add_child(audio)
	return audio

func _test_tracks() -> void:
	var audio := _audio()
	_check("a music file loads", audio.load_music("village", DIR + "audio/village.ogg") and audio.has_track("village"))
	_check("and a second name for it, quieter", audio.load_music("calm", DIR + "audio/village.ogg", {"volume_db": -6.0}))
	var stream := load(DIR + "audio/village.ogg") as AudioStreamOggVorbis
	_check("a track is Ogg Vorbis and loops from its start", stream != null and stream.loop and is_zero_approx(stream.loop_offset) and stream.get_length() > 10.0)
	_check("an unknown track does nothing", not audio.play_track("nope") and not audio.music_playing)
	_check("a track starts", audio.play_track("village", 0.0) and audio.music_playing and audio.music_track == "village" and int(audio.played["village"]) == 1)
	_check("at full level when it is not faded in", is_equal_approx(audio.music_levels()[0], 1.0) and is_zero_approx(audio.music_levels()[1]))
	_check("asking for the playing track again changes nothing", audio.play_track("village") and int(audio.played["village"]) == 1)
	audio.play_track("calm", 1.0)
	_check("another track takes over the name at once", audio.music_track == "calm" and audio.music_playing)
	audio.tick(0.5)
	var half := audio.music_levels()
	_check("half way through a cross-fade both are sounding", half[0] > 0.5 and half[0] < 0.9 and half[1] > 0.5 and half[1] < 0.9)
	_check("at equal power: the two levels squared add up to one", is_equal_approx(half[0] * half[0] + half[1] * half[1], 1.0))
	audio.tick(0.6)
	_check("after it only the new one is", is_zero_approx(audio.music_levels()[0]) and is_equal_approx(audio.music_levels()[1], 1.0))
	_check("each track plays at its own level under the bus", is_equal_approx((audio.get_node("Music1") as AudioStreamPlayer).volume_db, -6.0))
	audio.stop_music(1.0)
	_check("a fading stop is a stop at once, for the game", not audio.music_playing and audio.music_track == "")
	audio.tick(0.5)
	_check("while the sound fades", audio.music_levels()[1] > 0.3 and audio.music_levels()[1] < 0.9)
	audio.stop_music(4.0)
	audio.tick(0.6)
	_check("a second, slower stop does not stretch the fade", is_zero_approx(audio.music_levels()[1]))
	audio.play_music({"bpm": 120, "voices": [{"notes": [["C4", 1]]}]})
	_check("a synthesised tune still plays, without a track name", audio.music_playing and audio.music_track == "")
	audio.play_track("village", 0.5)
	audio.set_paused(true)
	audio.tick(5.0)
	_check("a paused run holds its fade", audio.music_levels()[1] > 0.9 and is_zero_approx(audio.music_levels()[0]))
	audio.set_paused(false)
	audio.tick(0.6)
	_check("and finishes it after", is_zero_approx(audio.music_levels()[1]) and is_equal_approx(audio.music_levels()[0], 1.0))
	audio.stop_all()
	_check("stop_all silences everything", not audio.music_playing and is_zero_approx(audio.music_levels()[0]) and is_zero_approx(audio.music_levels()[1]))
	_check("a music file that is not there is refused, loudly but without a crash", not audio.has_track("ghost"))
	audio.free()

func _test_stingers() -> void:
	var audio := _audio()
	audio.load_music("village", DIR + "audio/village.ogg")
	_check("a stinger file loads", audio.load_stinger("clear", DIR + "audio/clear.ogg") and audio.has_stinger("clear"))
	_check("an unknown stinger does nothing", not audio.play_stinger("nope") and not audio.stinger_playing)
	var seconds := (load(DIR + "audio/clear.ogg") as AudioStream).get_length()
	audio.play_track("village", 0.0)
	_check("a stinger starts over the music", audio.play_stinger("clear") and audio.stinger_playing and audio.music_playing and int(audio.played["clear"]) == 1)
	audio.tick(0.3)
	_check("which is turned down under it", is_equal_approx(audio.music_levels()[0], db_to_linear(GameAudio.DUCK_DB)))
	audio.tick(seconds)
	_check("the stinger ends by itself", not audio.stinger_playing)
	audio.tick(1.0)
	_check("and the music comes back up", is_equal_approx(audio.music_levels()[0], 1.0) and audio.music_playing)

	audio.play_stinger("clear", GameAudio.STINGER_PAUSE)
	_check("a pausing stinger holds the music", audio.is_music_held() and audio.music_playing and is_equal_approx(audio.music_levels()[0], 1.0))
	audio.set_paused(true)
	audio.set_paused(false)
	_check("a pause and resume of the run in between does not let it go", audio.is_music_held())
	audio.tick(seconds + 0.1)
	_check("and it continues afterwards", not audio.is_music_held() and not audio.stinger_playing)

	audio.play_stinger("clear", GameAudio.STINGER_OVER)
	audio.tick(0.3)
	_check("a stinger can leave the music alone", is_equal_approx(audio.music_levels()[0], 1.0) and not audio.is_music_held())
	audio.play_stinger("clear", GameAudio.STINGER_STOP)
	_check("or end it", not audio.music_playing and audio.stinger_playing)
	audio.tick(seconds + 1.0)
	_check("for good", not audio.music_playing and is_zero_approx(audio.music_levels()[0]) and not audio.stinger_playing)

	audio.play_track("village", 0.0)
	audio.play_stinger("clear")
	audio.tick(0.3)
	audio.stop_music(GameAudio.END_FADE)
	audio.tick(seconds + 1.0)
	_check("music stopped under a stinger stays stopped when the stinger ends", not audio.music_playing and is_zero_approx(audio.music_levels()[0]))
	var buses := true
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		buses = buses and player.bus == (GameAudio.BUS_SFX if str(player.name).begins_with("Effect") else GameAudio.BUS_MUSIC)
	_check("music and stingers are on the Music bus, effects on the SFX bus", buses and audio.get_child_count() == GameAudio.VOICES + 3)
	audio.free()

func _test_sounds() -> void:
	var audio := _audio()
	_check("an effect file loads", audio.load_sound("chime", DIR + "audio/chime.ogg", {"volume_db": -3.0, "vary": 0.05}) and audio.has_sound("chime"))
	_check("and is played and counted like a synthesised one", audio.play("chime") and audio.play("chime", 1.2, -4.0) and int(audio.played["chime"]) == 2)
	_check("an effect file is not left looping by an earlier use as music", not (load(DIR + "audio/chime.ogg") as AudioStreamOggVorbis).loop)
	audio.free()

func _test_sprites() -> void:
	var sheet := GameSprites.load_atlas(DIR + "art/keeper.json")
	_check("an atlas loads with its frames and animations", sheet.texture != null and sheet.frame_names().size() == 3 and sheet.has_animation("walk"))
	_check("its texture has mipmaps, so it stays clean drawn small", FileAccess.get_file_as_string(DIR + "art/keeper.png.import").contains("mipmaps/generate=true"))
	var idle := sheet.size("idle")
	_check("a frame's stage size is its source size times the sheet's scale", is_equal_approx(idle.y, 60.0) and is_equal_approx(idle.x, 78.0 * sheet.scale))
	var box := sheet.bounds("idle", Vector2(100, 300))
	_check("a frame stands on its pivot: bottom centre for this sheet", is_equal_approx(box.end.y, 300.0) and is_equal_approx(box.get_center().x, 100.0))
	_check("zoom scales about the pivot", is_equal_approx(sheet.bounds("idle", Vector2(100, 300), 2.0).end.y, 300.0) and is_equal_approx(sheet.bounds("idle", Vector2(100, 300), 2.0).size.y, 120.0))
	_check("an animation steps through its frames at its rate and loops", sheet.animation_frame("walk", 0.0) == "walk_0" and sheet.animation_frame("walk", 0.17) == "walk_1" and sheet.animation_frame("walk", 0.34) == "walk_0" and is_equal_approx(sheet.animation_length("walk"), 2.0 / 6.0))
	sheet.define_animation("once", ["idle", "walk_0"], 10.0, false)
	_check("one that does not loop holds its last frame", sheet.animation_frame("once", 5.0) == "walk_0" and sheet.animation_frame("nope", 1.0) == "")
	var region := sheet.frame_texture("walk_0")
	_check("a frame is available as a texture for nodes", region != null and region.atlas == sheet.texture and region.get_size() == Vector2(71, 138))
	_check("an unknown frame has no size and no texture", sheet.size("nope") == Vector2.ZERO and sheet.frame_texture("nope") == null)
	var tile := GameSprites.load_image(DIR + "art/cobble.jpg", {"height": 64})
	_check("a single image is one frame sized in stage pixels", tile.has_frame("main") and tile.size("main") == Vector2(64, 64) and is_equal_approx(tile.scale, 0.25))
	var grid := GameSprites.load_grid(DIR + "art/cobble.jpg", 4, 2, {"width": 16, "pivot": Vector2(0.5, 1.0)})
	_check("a grid image is cut into numbered cells", grid.frame_names().size() == 8 and grid.size("5") == Vector2(16, 32) and grid.bounds("5", Vector2(50, 50)).end.y == 50.0)
	var missing := GameSprites.load_atlas(DIR + "art/nowhere.json")
	_check("a missing atlas gives an empty sheet instead of a crash", missing.texture == null and not missing.has_frame("idle") and missing.size("idle") == Vector2.ZERO)

## Drawing cannot be looked at here, but it can be run: every helper is called from a real _draw and must get through without an error.
func _test_drawing() -> void:
	var sheet := GameSprites.load_atlas(DIR + "art/keeper.json")
	var tile := GameSprites.load_image(DIR + "art/cobble.jpg", {"height": 64})
	var text := GameText.new()
	var canvas := Node2D.new()
	canvas.texture_filter = GameSprites.FILTER
	var drawn := [0]
	canvas.draw.connect(func() -> void:
		sheet.draw(canvas, "idle", Vector2(100, 300))
		sheet.draw(canvas, "walk_0", Vector2(200, 300), true, 1.5, 0.3, Color(1, 1, 1, 0.5), true)
		sheet.draw(canvas, "nope", Vector2.ZERO)
		sheet.draw_animation(canvas, "walk", 0.2, Vector2(300, 300))
		sheet.draw_fit(canvas, "idle", Rect2(0, 0, 40, 40))
		tile.draw_tiled(canvas, "main", Rect2(0, 300, 640, 60), Vector2.ZERO, Vector2(13, 5))
		tile.draw_patch(canvas, "main", Rect2(20, 20, 200, 80), 48.0)
		text.draw(canvas, Vector2(320, 40), "点亮每一盏灯 Light", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 600, 1.5)
		drawn[0] += 1)
	root.add_child(canvas)
	canvas.queue_redraw()
	await process_frame
	await process_frame
	_check("every drawing helper runs inside a real _draw", drawn[0] >= 1)
	_check("text is measured in stage pixels and a font is built once", text.measure("Light", 16).x > 20.0 and text.measure("Light", 16).y > 10.0 and text.font(600) == text.font(600))
	canvas.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + label)
