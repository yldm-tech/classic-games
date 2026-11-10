class_name ReplayScreen
extends ScreenBase

## 精彩回放：加载服务端真实轨迹，按时间回放位置、生命和分数。

signal closed

var handle := ""
var user_id:=""
var game: Dictionary = {}
var playing := false
var progress := 0.0
var frames: Array = []
var duration_ms := 0
var engagement: EngagementCoordinator

func _init(p_state: Node, p_engagement: EngagementCoordinator = null) -> void:
	engagement = p_engagement
	super(p_state)

func set_replay(p_handle: String, p_game: Dictionary,p_user_id:String="") -> void:
	handle = p_handle
	user_id=p_user_id if p_user_id!="" else p_handle
	game = p_game
	playing = false
	progress = 0.0
	frames = []
	duration_ms = 0
	rebuild()
	if is_inside_tree() and engagement != null: refresh()

func refresh()->void:
	if engagement==null or game.is_empty():return
	if await engagement.load_replay(str(game.get("id","")),user_id):
		frames=engagement.store.replay.get("frames",[]);duration_ms=int(engagement.store.replay.get("duration_ms",0));progress=0.0;rebuild()

func _process(delta: float) -> void:
	if playing:
		progress = minf(100.0, progress + delta * 100000.0 / float(maxi(1,duration_ms)))
		var bar := find_child("ProgressSlider", true, false)
		if bar != null:
			(bar as HSlider).set_value_no_signal(progress)
		_sync_replay_view()
		# 到 100% 自动停:翻回 ▶,并停掉每帧空转(否则 _process 一直写 100、按钮卡在 II)。
		if progress >= 100.0:
			playing = false
			rebuild()

func _build() -> void:
	var title := Widgets.heading(txt("rep_title"), 3, theme_name())
	title.name = "ReplayTitle"
	content.add_child(title)
	content.add_child(Widgets.caption(txt_fmt("rep_by_fmt", [handle]), theme_name()))
	if not game.is_empty():
		content.add_child(GameCard.cover(game, 150))

	var row := Widgets.hbox(Tokens.SPACE_2)
	var play := Widgets.primary_button("II" if playing else "▶", theme_name())
	play.name = "PlayPauseButton"
	play.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 不被行高纵向拉伸
	play.disabled = frames.size() < 2 or duration_ms <= 0
	play.pressed.connect(func() -> void:
		if frames.size() < 2 or duration_ms <= 0: return
		# 已播到末尾再按 ▶ 时从头重播,否则下一帧又立刻命中 >=100 自停,按钮成了死键。
		if not playing and progress >= 100.0:
			progress = 0.0
		playing = not playing
		rebuild())
	row.add_child(play)
	var slider := HSlider.new()
	slider.name = "ProgressSlider"
	slider.max_value = 100
	slider.value = progress
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: progress = v)
	row.add_child(slider)
	content.add_child(row)
	if not frames.is_empty():
		var frame:Dictionary=_frame_at(int(progress*duration_ms/100.0))
		var telemetry:=Widgets.caption("x %.1f · y %.1f · HP %d · %d"%[float(frame.get("x",0)),float(frame.get("y",0)),int(frame.get("hp",0)),int(frame.get("score",0))],theme_name())
		telemetry.name="ReplayTelemetry";content.add_child(telemetry)
		var stage := ColorRect.new()
		stage.name = "ReplayStage"
		stage.custom_minimum_size = Vector2(0, 160)
		stage.color = Color("071426")
		stage.clip_contents = true
		var ghost := ColorRect.new()
		ghost.name = "ReplayGhost"
		ghost.size = Vector2(14, 14)
		ghost.color = Color("facc15")
		stage.add_child(ghost)
		content.add_child(stage)
		_place_ghost(ghost, stage, frame)

	var close := Widgets.secondary_button(txt("rep_close"), theme_name())
	close.name = "CloseButton"
	close.pressed.connect(func() -> void: closed.emit())
	content.add_child(close)

func _frame_at(at_ms:int)->Dictionary:
	if frames.is_empty():
		return {}
	var prev: Dictionary = frames[0]
	var nxt: Dictionary = {}
	for item: Dictionary in frames:
		if int(item.get("at_ms", 0)) > at_ms:
			nxt = item
			break
		prev = item
	if nxt.is_empty():
		return prev
	var t0 := int(prev.get("at_ms", 0))
	var t1 := int(nxt.get("at_ms", 0))
	var span := t1 - t0
	var alpha := 0.0 if span <= 0 else clampf(float(at_ms - t0) / float(span), 0.0, 1.0)
	var mixed: Dictionary = prev.duplicate()
	mixed["x"] = lerpf(float(prev.get("x", 0)), float(nxt.get("x", 0)), alpha)
	mixed["y"] = lerpf(float(prev.get("y", 0)), float(nxt.get("y", 0)), alpha)
	mixed["hp"] = int(prev.get("hp", 0))
	mixed["score"] = int(prev.get("score", 0))
	return mixed

func _sync_replay_view() -> void:
	if frames.is_empty():
		return
	var frame: Dictionary = _frame_at(int(progress * duration_ms / 100.0))
	var telemetry := find_child("ReplayTelemetry", true, false)
	if telemetry is Label:
		(telemetry as Label).text = "x %.1f · y %.1f · HP %d · %d" % [float(frame.get("x", 0)), float(frame.get("y", 0)), int(frame.get("hp", 0)), int(frame.get("score", 0))]
	_place_ghost(find_child("ReplayGhost", true, false), find_child("ReplayStage", true, false), frame)

func _place_ghost(ghost: Node, stage: Node, frame: Dictionary) -> void:
	if ghost == null or stage == null:
		return
	var size: Vector2 = (stage as Control).size
	if size.x < 8.0:
		size = Vector2(320, 160)
	var nx := clampf((float(frame.get("x", 0)) + 480.0) / 960.0, 0.0, 1.0)
	var ny := clampf((float(frame.get("y", 0)) + 270.0) / 540.0, 0.0, 1.0)
	(ghost as Control).position = Vector2(nx * maxf(8.0, size.x - 14.0), ny * maxf(8.0, size.y - 14.0))
