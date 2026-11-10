class_name RuntimeLoader
extends RefCounted

## 读 DSL → 校验 runtime 版本 → 按内容清单(docs/11-runtime-content.md)把枚举/数值套到游戏对象。
## 版本不匹配直接报错,由 GameSession 转成 game_error 信号(见 docs/05-dsl-design.md 的版本治理)。
##
## 注意分工:完整 JSON Schema 校验在 Go 后端做(见 docs/12-ai-prompt.md);
## 客户端信任已校验的 DSL,这里只做版本治理 + 把枚举/数值套到游戏对象。

const ShooterRuntime := preload("res://runtime/shooter/shooter_runtime.gd")
const SurvivorRuntime := preload("res://runtime/survivor/survivor_runtime.gd")
const TowerDefenseRuntime := preload("res://runtime/tower_defense/tower_defense_runtime.gd")
const DslMigrations := preload("res://runtime/dsl_migrations.gd")

const RUNTIMES := {
	"shooter": {"version": "1.0.0", "builder": ShooterRuntime},
	"survivor": {"version": "1.0.0", "builder": SurvivorRuntime},
	"tower_defense": {"version": "1.0.0", "builder": TowerDefenseRuntime},
}

## 失败时由调用方(GameSession)读取,转成 game_error。GDScript 无异常,用此约定。
var last_error: Dictionary = {}

## Validate that the mod's required runtime version is satisfied, then build the run.
## runtime_ref 形如 "shooter@1.0.0";dsl 为生效 DSL。
## 成功返回组装好的运行时节点;失败返回 null 并设置 last_error = { code, msg }。
func load_from_dsl(runtime_ref: String, dsl: Dictionary) -> Node:
	last_error = {}
	var ref := _parse_ref(runtime_ref)
	if not RUNTIMES.has(ref["name"]):
		return _fail("UNKNOWN_RUNTIME", "未知 runtime: %s" % ref["name"])
	var runtime: Dictionary = RUNTIMES[ref["name"]]
	var runtime_version: String = runtime["version"]
	var effective := dsl
	if not _version_compatible(ref["version"], runtime_version):
		if DslMigrations.can_migrate(ref["name"], ref["version"], runtime_version):
			effective = DslMigrations.migrate(ref["name"], ref["version"], runtime_version, dsl)
			if effective.is_empty(): return _fail("MIGRATION_FAILED", "DSL 迁移失败")
		else:
			return _fail("RUNTIME_VERSION_MISMATCH", "mod 要求 %s,本端内置 %s,不兼容" % [ref["version"], runtime_version])
	return runtime["builder"].build(effective)

## 版本治理:同 major 视为兼容(patch/minor 向后兼容);major 不同则不兼容,
## major 不同时由 DslMigrations 迁移；没有已知迁移路径才拒绝。
func _version_compatible(required: String, installed: String) -> bool:
	var a := required.split(".")
	var b := installed.split(".")
	if a.size() < 1 or b.size() < 1:
		return false
	return a[0] == b[0]

func _parse_ref(ref: String) -> Dictionary:
	var parts := ref.split("@")
	return {
		"name": parts[0],
		"version": parts[1] if parts.size() > 1 else "",
	}

func _fail(code: String, msg: String) -> Node:
	last_error = {"code": code, "msg": msg}
	return null
