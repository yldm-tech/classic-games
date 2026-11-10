class_name Router
extends RefCounted

## 导航状态机(对照原型 fp-app-root.jsx 的 useNav,纯逻辑可 headless 断言)。
## 层级规则(docs/16):Tab 平级切换、子页统一返回栈、全屏只留游戏;
## 手机竖屏点「立即开玩」先走横屏闸门(rotate),再加载(loading)进游戏(play)。

signal changed

const VIEW_TABS := "tabs"
const VIEW_DETAIL := "detail"
const VIEW_ROTATE := "rotate"
const VIEW_LOADING := "loading"
const VIEW_PLAY := "play"
const VIEW_SETTINGS := "settings"

var tab := 0
var view := VIEW_TABS
var game: Dictionary = {}
var is_phone := true
var is_portrait := true

var _stack: Array[String] = []

func set_tab(index: int) -> void:
	if index != tab:
		tab = index
		changed.emit()

## 进入子页:当前 view 入栈。
func go(target: String) -> void:
	_stack.append(view)
	view = target
	changed.emit()

func open_game(g: Dictionary) -> void:
	game = g
	go(VIEW_DETAIL)

## 开玩:手机竖屏先横屏闸门,否则直接进加载页。
func play(g: Dictionary) -> void:
	game = g
	go(VIEW_ROTATE if is_phone and is_portrait else VIEW_LOADING)

## 横屏闸门里转了屏:切横屏并直进加载(不入栈,对照原型 rotateAndPlay)。
func rotate_and_play() -> void:
	is_portrait = false
	view = VIEW_LOADING
	changed.emit()

## 加载完成进入游戏(不入栈:play/rotate 返回时一律回 tabs)。
func enter_play() -> void:
	view = VIEW_PLAY
	changed.emit()

## 退出游戏回详情(没有当前游戏则回 tabs)。
func exit_play() -> void:
	view = VIEW_DETAIL if not game.is_empty() else VIEW_TABS
	# play() 入栈过同名 view,弹掉避免「返回原地踏步」(原型 useNav 的瑕疵,此处修正)
	if not _stack.is_empty() and _stack.back() == view:
		_stack.pop_back()
	changed.emit()

## 返回:弹栈;栈顶若是 rotate/play 这类过场,跳过直接回 tabs。
func back() -> void:
	if _stack.is_empty():
		view = VIEW_TABS
		changed.emit()
		return
	var prev: String = _stack.pop_back()
	view = VIEW_TABS if prev == VIEW_ROTATE or prev == VIEW_PLAY else prev
	changed.emit()

## AI 生成完成:以生成结果为「当前游戏」打开详情(对照原型 forged)。
## by/tone 取当前登录用户的真实身份与配色,不是某个演示账号(生成结果作者就是操作者本人)。
func forged(prompt: String, by: String, tone: String) -> void:
	game = {"id": "forged", "prompt": prompt, "by": by, "tone": tone,
		"plays": 0, "forks": 0, "likes": 0, "cat": "Arcade", "badge": "ai"}
	go(VIEW_DETAIL)

## 设备转屏后调用:闸门挂着但已不是「手机竖屏」时,直接放行进游戏。
func resolve_orientation(p_is_portrait: bool) -> void:
	is_portrait = p_is_portrait
	if view == VIEW_ROTATE and not (is_phone and is_portrait):
		view = VIEW_PLAY
		changed.emit()

func depth() -> int:
	return _stack.size()
