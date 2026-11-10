extends Node

const AppRootScript := preload("res://app/app_root.gd")

## 入口:恢复会话、挂全局状态、初始化路由,展示 Shell 首屏。
## 未登录 → 登录页；未引导 → onboarding，门控由 AppRoot 统一编排。

func _ready() -> void:
	# 桌面端(macOS/Windows/Linux)启动即最大化铺满屏幕,保留窗口标题栏(红绿灯/caption);
	# 手机/Web 的窗口由系统接管,不干预。
	if OS.has_feature("pc"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	AppState.restore()
	add_child(AppRootScript.new(AppState, OS.get_environment("CLASSIC_GAMES_API")))
