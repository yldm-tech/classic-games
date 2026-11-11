# 添加一款游戏

一款游戏是 `apps/client/games/<id>/` 下的一个目录。加一款游戏只需要加这个目录：启动器的目录、游戏菜单、成就、局内 HUD、官网的游戏列表，以及测试和清单检查，都在启动时或构建时自己发现它。不需要也不应该改任何共享文件（`launcher/`、`runtime/`、`i18n/`、`project.godot`、`Makefile`、CI、`apps/web`）。如果你发现必须改共享文件才能做完，那是契约的缺口，请单独提 issue，不要在游戏的 PR 里顺手改。

本文是游戏作者的参考。权威定义在代码里：契约是 `apps/client/games/shared/game_module.gd`，清单 schema 是 `apps/client/games/shared/game_manifest.gd`，可运行的完整样例是测试夹具 `apps/client/testing/games/fixture_duo/`。

## 0. 原创规则（先读这一条）

[decisions](./decisions.md) 的 ADR-016 规定：**游戏内容必须原创。** 可以做经典的类型（平台跳跃、迷宫炸弹、坦克基地防御……），不得复刻任何现有商业游戏。具体到一个 PR：

- 名称、角色、敌人、道具的名字和造型都自己设计，不使用、不谐音、不影射现有游戏的名称和商标。
- 美术和音频自己制作（或程序生成），不描摹、不重绘、不提取现有游戏的素材，也不使用来源或许可不明的素材。
- 关卡自己设计，不照搬现有游戏的关卡布局、敌人配置或数值表。
- 「像某某游戏」不是验收标准。玩法规则可以属于同一个类型，表达必须是自己的。

每个素材文件的来源与许可记在游戏目录的 `ASSETS.md`（第 6 节），`make games-check` 会核对有没有漏记。

## 1. 目录

```text
apps/client/games/<id>/
├── game.json          # 清单：身份、名称、人数、配色、成就、玩法说明、操作表、HUD、开局选项
├── main.gd            # 入口脚本，extends GameModule（文件名由清单的 entry 决定）
├── *.gd / *.tscn …    # 游戏自己的脚本、场景、数据
├── key_art.png        # 可选：16:9 主视觉，由清单的 art.image 指向
├── site_screenshot.png# 可选：官网用的局内截图，由清单的 site.screenshot 指向
├── ASSETS.md          # 每个素材文件的来源与许可
└── <id>_test.gd       # 自带的 headless 测试，至少一个 *_test.gd
```

`<id>` 是小写字母、数字、下划线，以字母开头，全仓库唯一。它同时是存档里的键，发布后不要改。

`apps/client/games/shared/` 是所有游戏共用的支持库，不是游戏。它故意很小：需要的东西不在里面时，先在自己的目录里实现；确实有两款以上游戏需要、而且契约清楚，再单独提 PR 加进去。

## 2. 模块契约

入口脚本继承 `GameModule`（一个 `Node2D`）。宿主是 `runtime/game_session.gd`，启动器经它运行游戏；游戏不认识宿主，也不认识启动器。

### 2.1 你实现的

| 方法 | 何时调用 | 说明 |
|---|---|---|
| `_game_start(config)` | 一局开始 | `config = { options: { 选项 id: 值 }, players: 开局人数, seed: 整数, locale: "zh" 或 "en", stage_size: Vector2i }`。在这里搭建这一局 |
| `_game_step(delta)` | 每个固定步 | 推进模拟。`delta` 恒为 `GameModule.STEP`（1/60 秒）。所有玩法逻辑放这里 |
| `_game_frame(delta)` | 每个渲染帧，在本帧的固定步之后 | 只做表现：动画、`queue_redraw()`。测试里用 `advance()` 推进时不会调用它，所以会影响玩法或快照的东西（包括摄像机位置，如果你把它放进快照）不要放这里 |
| `_game_snapshot()` | 宿主每帧读 HUD 时、以及结束时 | 返回一个字典，见 2.4 |
| `_game_player_joined(slot)` / `_game_player_left(slot)` | 一局进行中有玩家加入或退出 | 只有清单里 `players.join_in_progress` 为 true 的游戏会收到 |
| `_game_paused(paused)` | 暂停与继续 | 可选。模拟的冻结由宿主完成，你不需要自己停 |

只有 `_game_start` 和 `_game_step` 是必需的。不要覆盖 `_process`，也不要覆盖或自己调用宿主一侧的方法（`start`、`set_paused`、`snapshot`、`feed`、`join`、`leave`）。

### 2.2 你使用的

| 成员 | 说明 |
|---|---|
| `input(slot)` | 第 `slot` 位玩家（0 是玩家一）的 `GameInput`，见 2.3 |
| `active_players()` / `player_count()` / `is_player_active(slot)` | 当前在玩的座位 |
| `score` | 这一局的总分，整数。直接赋值，宿主会记录它并显示在 HUD |
| `rng` | 用 `config.seed` 播种的 `GameRng`：`int_range`、`float_range`、`unit`、`chance`、`pick`、`shuffle`。所有随机都用它，不要用全局的 `randf()` / `randi()`，否则同一个种子无法重放，测试也就写不稳 |
| `audio` | `GameAudio`，见 2.6 |
| `stage_size` | 逻辑舞台的像素尺寸，见 2.5 |
| `elapsed` | 已模拟的秒数，不含暂停 |
| `options` / `locale` | 开局选项的值、界面语言 |
| `finish(outcome, extra = {})` | 结束这一局。`outcome` 是 `OUTCOME_CLEARED`（通关）、`OUTCOME_DEFEATED`（失败）或 `OUTCOME_TIMED_OUT`（游戏自己的时限到了，不算赢也不算输）。`extra` 里的字段并入结果 |

信号 `finished(result)` 和 `score_changed(score)` 由基类发出，游戏自己不需要 emit。

### 2.3 输入

每位玩家有十个逻辑控制：四个方向 `up` `down` `left` `right`，六个按键 `a` `b` `x` `y` `l` `r`。手柄上是十字键或左摇杆、A B X Y、LB RB；键盘上是玩家在「设置 › 玩家按键」里为两套方案绑定的键（默认方案 1 为 WASD + F G R T Q E，方案 2 为方向键 + K L I O U P）。哪个设备控制哪位玩家由启动器决定，游戏看不到设备，也没有鼠标和触摸输入。暂停不是控制：Menu / Esc 属于启动器。

```gdscript
var pad := input(slot)
position += pad.move * SPEED * delta        # move: 长度不超过 1 的 Vector2，摇杆是模拟量
if pad.just_pressed(GameInput.A): jump()    # 只在按下的那一步为 true
if pad.is_down(GameInput.B): charge(delta)  # 按住期间为 true
var cell := pad.move_sign()                 # Vector2i，各分量为 -1 / 0 / 1，给网格移动用
```

`just_pressed` / `just_released` 与固定步对齐：恰好一步为 true；两步之间按下又松开的轻点也会被看到一步。暂停时所有控制被松开，继续后需要玩家重新按下。

游戏目录里**不得**出现 `Input.`、`InputMap`、`InputEvent`、`_input(`、`_unhandled_input(`：`make boundary-test` 会拒绝。

### 2.4 快照、HUD 与结果

`_game_snapshot()` 返回 HUD 要显示的字段。基类已经提供 `score`、`elapsed`、`player_count`、`active_players`；你补充清单 `hud` 段里点名的字段。约定：

- 全局字段放在顶层，例如 `time_left`、`wave`、`boss_hp`。
- 每位玩家各自的字段放在 `players` 数组里，下标是座位：`players[0] = { score, lives, max_lives, … }`。HUD 的每位玩家各有一角，生命条（`hud.vital`）和 `hud.player_stats` 从这里取；`players[i].score` 存在时显示该玩家自己的分数。
- 首领血条在 `hud.boss.field` 出现在快照里时显示，首领不在场时不要输出这个字段。

一局结束时的结果是「结束那一刻的快照 + `cleared` / `defeated` / `timed_out` + `finish()` 的 `extra`」，宿主再加上 `play_seconds`（不含暂停）和 `aborted`（玩家中途退出）。成就条件（清单的 `achievements[].when`）就是对这份结果求值，所以成就要用到的量（死亡次数、收集数、是否无伤……）必须出现在快照或 `extra` 里。玩家中途退出的一局不会解锁成就，但时长和分数照常记录。

### 2.5 舞台、缩放与摄像机

清单的 `stage.size` 声明逻辑舞台，必须是 1920×1080 除以整数：960×540、640×360、480×270、384×216、320×180 等。游戏以**左上角为原点**、按 `stage_size` 的逻辑像素作画，不读窗口或视口尺寸。

- `stage.pixel_art: true`：舞台按逻辑分辨率渲染，再以整数倍、最近邻过滤放大到 1920×1080，每个逻辑像素是一个清晰的方块；模块节点的 `texture_filter` 已设为最近邻。像素美术用这个。
- `stage.pixel_art: false`（默认）：舞台按 1920×1080 渲染，逻辑坐标映射上去，矢量图形和文字保持锐利。

卷轴关卡：给模块加一个 `Camera2D` 子节点并移动它，舞台就是摄像机的视野。单屏游戏不需要摄像机。HUD 由启动器画在舞台之上：上方约 16% 高度（左上、右上角是玩家信息，中间是时钟）和右下角的暂停按钮会盖住画面，重要的东西别只放在那里。

### 2.6 声音

`audio` 在运行时合成音效和音乐，游戏不带音频文件，也就没有音频许可要记。音效走 `SFX` 总线、音乐走 `Music` 总线，音量由玩家在设置里调，游戏不碰总线。

```gdscript
audio.define("jump", {"wave": "square", "freq": 330, "freq_end": 660, "duration": 0.12})
audio.play("jump")                 # 第二个参数是音高倍率
audio.play_music({"bpm": 132, "voices": [
	{"wave": "pulse", "volume": 0.3, "notes": [["C4", 1], ["E4", 1], ["G4", 2]]},
	{"wave": "triangle", "volume": 0.4, "notes": [["C2", 2], ["G2", 2]]},
]})
```

波形有 `square`、`pulse`、`triangle`、`saw`、`sine`、`noise`；音符是音名（`"F#3"`、`"Bb2"`）、MIDI 编号或休止 `"-"`。完整参数见 `games/shared/game_audio.gd` 开头。在 `_game_start` 里 `define`（合成发生在这时），不要在每次播放时合成。

### 2.7 能碰什么，不能碰什么

可以：自己目录下的任何脚本、场景和数据；`games/shared/` 的库；作为模块子节点的任何 Godot 节点（`Node2D`、`Camera2D`、`TileMapLayer`、粒子、`AnimationPlayer`……）；用 `FileAccess` 读自己目录里的数据文件。

不可以，其中前五条由 `make boundary-test` 机械地检查：

- 引用自己目录和 `games/shared/` 之外的任何 `res://` 路径：不能用启动器的代码、`runtime/`、`i18n/`，更不能用另一款游戏的文件。
- 声明 `class_name`。全局类名会与别的游戏冲突，用 `const X := preload("res://games/<id>/x.gd")`。
- 读全局输入（见 2.3）。
- 碰宿主的东西：`user://`、`OS.`、`ProjectSettings`、`AudioServer`、`DisplayServer`、`Engine.time_scale`、`get_tree().root` / `.paused` / `.quit`、`get_window()`、`DirAccess`。存档、音量、窗口、暂停都是启动器的。
- 联网：任何网络类、URL、端点。
- 新增第三方依赖或 Godot 插件。
- 往 `project.godot` 加 autoload、输入动作或图层名。

## 3. 清单 `game.json`

一个完整的例子是 `apps/client/testing/games/fixture_duo/game.json`。字段（schema 1）：

| 字段 | 必需 | 说明 |
|---|---|---|
| `schema` | 是 | `1` |
| `id` | 是 | 等于目录名 |
| `kind` | 是 | `"module"`。（`"dsl"` 是内置 DSL 运行时的三款游戏用的，新游戏不用） |
| `entry` | 是 | 入口脚本，目录内的相对路径，如 `"main.gd"` |
| `stage` | 是 | `{ "size": [宽, 高], "pixel_art": true/false }`，见 2.5 |
| `name` | 是 | `{ "zh", "en" }`。`en` 同时是各语言下标题下方的拉丁副标题，习惯全大写 |
| `initials` | 是 | 中文名的拼音首字母，小写，供搜索 |
| `genre` | 是 | `{ "zh", "en" }`，`en` 全大写。游戏库按它分类，同类型的游戏请用完全相同的写法 |
| `tagline` | 是 | `{ "zh", "en" }`，一句话 |
| `players` | 是 | `{ "min": 1, "max": 1 或 2, "join_in_progress": bool }`。`max` 为 2 时游戏菜单出现「玩家人数」一行；`join_in_progress` 为 true 时玩家二可以在暂停菜单里中途加入或退出 |
| `colors` | 是 | `{ "title", "shadow", "glow" }`，`RRGGBB`，标题字、投影、辉光 |
| `art` | 是 | `{ "top", "bottom", "primary", "secondary" }`（`RRGGBB`，没有图片时的占位配色），可选 `"image"`（目录内的 16:9 图片） |
| `achievements` | 是 | `[{ "id", "icon", "name", "desc", "when" }]`，可以为空数组。`icon` 是 `star` / `bolt` / `cup` / `shield`。`when` 见下 |
| `how` | 是 | `{ "zh", "en" }`，一段话：目标、怎样算赢、怎样算输 |
| `controls` | 是 | `[{ "id", "name", "inputs" }]`。`inputs` 是 `"move"`（四个方向）或单个控制名 `"a"` `"b"` …。启动器据此在游戏菜单和暂停屏画出操作表（键盘键帽读自当前绑定，手柄图标固定），并自动补上「暂停」一行 |
| `hud` | 是 | 见下 |
| `options` | 否 | `[{ "id", "name", "note", "values": [整数…], "default", "labels": [{ "zh", "en" }…] }]`。开局选项，值经 `config.options` 传给游戏；`labels` 可选，与 `values` 一一对应 |
| `site` | 否 | 只给官网用：`{ "screenshot", "screenshot_alt": { "zh", "en" }, "art_alt": { "zh", "en" } }` |

`achievements[].when` 的条件全部满足才解锁；`{}` 表示打完任意一局：

| 键 | 含义 |
|---|---|
| `"cleared": true/false` | 结果的 `cleared` 必须相等 |
| `"players": 2` | 结束时至少有这么多玩家 |
| `"min": { "字段": 数 }` | 结果里该字段不小于这个数 |
| `"max": { "字段": 数 }` | 结果里该字段存在且不大于这个数（例如 `{"deaths": 0}`） |

`hud`：

| 键 | 说明 |
|---|---|
| `clock` | 必需。`{ "mode": "countdown" / "elapsed" / "none", "field": 快照字段, "total": 可选 }`。有 `total` 时显示 `total - field` |
| `vital` | 可选。`{ "field", "max", "label": { "zh", "en" } }`，分数下面的条（生命、能量）。优先从 `players[i]` 取 |
| `player_stats` | 可选。`[{ "label", "fields": [一个或两个字段] }]`，每位玩家角上的小计数，从 `players[i]` 取；两个字段显示为 `a / b` |
| `stats` | 可选。同上格式，全局计数，显示在右上 |
| `boss` | 可选。`{ "field", "max", "label" }`，`field` 在快照里出现时显示首领血条 |

清单里出现未知字段是错误（防止拼写错误悄悄失效）。清单无效的游戏不会进入目录：启动器启动时用 toast 说明，「设置 › 关于」逐条列出问题，`make games-check` 则直接失败并打印全部问题。

## 4. 本地双人

清单 `players.max` 为 2 的游戏自动获得：游戏菜单里的人数选择和每位玩家的设备行、HUD 的第二个玩家角、暂停归属（谁暂停谁操作暂停菜单）、手柄拔出时自动暂停。游戏一侧要做的只有：

- 对 `active_players()` 里的每个座位读 `input(slot)` 并各自模拟。单人开局时只有座位 0。
- 快照里给出 `players[0]` 和 `players[1]`。
- 若声明了 `join_in_progress`，实现 `_game_player_joined` / `_game_player_left`（给新玩家一个出生点、把离开的玩家移出场景）。不声明则人数在开局时确定，中途不变。

单人时两套键盘方案和所有手柄都控制玩家一；双人时每位玩家恰好一个设备。这些都与游戏无关。

## 5. 测试

每个模块目录至少有一个 `*_test.gd`。它是一个 `extends SceneTree` 的脚本，直接加载入口脚本，不经过启动器和 `GameSession`，所以只引用自己的目录和 `games/shared/`。模板是 `apps/client/testing/games/fixture_duo/fixture_duo_test.gd`：

```gdscript
extends SceneTree

const Main := preload("res://games/<id>/main.gd")

func _initialize() -> void:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 1, "seed": 7, "options": {}, "stage_size": Vector2i(480, 270)})
	game.feed(0, &"right", 1.0)        # 按住玩家一的「右」
	game.advance(2.0)                  # 确定性地推进 2 秒（120 个固定步），不等渲染帧
	var state := game.snapshot()
	# …断言…
	game.free()
	print("<文件名去掉 .gd>: %d passed, %d failed" % [passed, failed])
	quit.call_deferred(0 if failed == 0 else 1)
```

- 结尾必须打印 `<文件名去掉 .gd>: N passed, 0 failed`，runner 以这一行和退出码判定；脚本解析错误、退出时泄漏对象都算失败。
- 用固定的 `seed` 和 `advance()`，不要依赖真实时间或帧数：同一种子、同一输入必须得到同一快照，这本身就值得断言一次。
- 至少覆盖：开局状态、每位玩家的输入各自生效、每一种结束方式（通关、失败、有时限则加超时）、成就要用到的结果字段、双人游戏的加入与退出（如果支持）。
- `_initialize` 里的脚本错误会让测试挂住而不是失败（Godot 不会自己退出）。本地先单独跑一次自己的测试再跑全量。

运行：

| 命令 | 作用 |
|---|---|
| `make games-check GODOT=<godot>` | 清单 schema、入口脚本能加载且继承 `GameModule`、目录里有测试、`ASSETS.md` 覆盖全部素材 |
| `make games-test GODOT=<godot>` | 自动发现并运行每个 `games/*/*_test.gd`（以及共享库和契约测试）。新游戏的测试不需要登记到任何地方 |
| `make boundary-test` | 依赖方向与 2.7 的禁止项 |
| `make export-test GODOT=<godot>` | 导出资源包并在包内运行发现，确认游戏在导出版里也能被找到 |
| `make ci GODOT=<godot>` | 以上全部加其余门禁；`make ci-web` 是官网门禁（官网会读你的清单） |

## 6. 素材来源 `ASSETS.md`

目录里每一个不是源码的文件（图片、音频、字体、模型……凡扩展名不在 `gd uid import json md tscn tres gdshader gdshaderinc txt cfg` 之内的）都要在 `ASSETS.md` 里占一行，写明它是什么、从哪里来、以什么许可分发。`make games-check` 检查每个这样的文件名都以反引号出现在 `ASSETS.md` 里。

```markdown
# Assets of `<id>`

| File | What it is | Source | Licence |
|---|---|---|---|
| `sprites/hero.png` | Player sprite sheet, 16x16 frames | Drawn for this project by <author> | Apache-2.0, with the project |
| `key_art.png` | 16:9 key art | Generated with <model> from a prompt written for this project; original composition | Apache-2.0; note on AI-generated images |
```

可以接受的来源：自己为本项目制作的；程序生成的；许可明确允许再分发和修改的第三方素材（CC0、CC BY 等，写清作者、出处和许可，CC BY 要保留署名）。不能接受：从其他游戏提取或描摹的素材、「网上找的」、许可不明或禁止再分发的素材。没有任何素材文件的游戏也要有 `ASSETS.md`，写明这一点即可。[legal/licenses](./legal/licenses.md) 只指向各游戏的 `ASSETS.md`，不需要为新游戏加行。

## 7. 截图

`scripts/run-launcher-shot.sh` 把启动器的某一屏渲染成 1920×1080 的 PNG（需要桌面会话，不在 CI 里）。它可以启动任何模块，按脚本给每位玩家输入若干秒，然后截图：

```bash
GODOT=/path/to/godot \
LAUNCHER_SHOT_DIR=~/screenshots/classic-games/<id> \
LAUNCHER_SHOT_GAME=<id> \
LAUNCHER_SHOT_PLAYERS=2 \
LAUNCHER_SHOT_SEED=7 \
LAUNCHER_SHOT_INPUT="2:right+a/left;1:/a;0.5:" \
LAUNCHER_SHOT_NAME=<id>-game \
scripts/run-launcher-shot.sh game fresh
```

`LAUNCHER_SHOT_INPUT` 是用分号隔开的若干段，每段是 `秒数:玩家一的控制/玩家二的控制`，控制用 `+` 连接，留空表示什么都不按。上例：前 2 秒玩家一按住右和 A、玩家二按住左；接着 1 秒只有玩家二按 A；最后 0.5 秒都松开。秒数是游戏时间，在 `LAUNCHER_SHOT_ACTIONS` 里加 `scale=4` 可以让它过得更快。其他屏幕把 `game` 换成 `menu`（游戏菜单）、`home`、`library` 等；全部环境变量见 `apps/client/launcher/launcher_shot.gd` 开头。测试夹具的截图加 `LAUNCHER_SHOT_GAMES_ROOT=res://testing/games LAUNCHER_SHOT_GAME=fixture_duo`。

PR 里请附游戏菜单、局内（单人，支持双人的再加双人）和结算三屏的截图，中英文各看一遍。要在官网上显示局内画面，把一张局内截图存为游戏目录里的图片，并在清单的 `site.screenshot` 里写上文件名（同时记进 `ASSETS.md`）；没有这张图的游戏在官网上只显示主视觉，连主视觉也没有时显示一块用清单配色画的面板。

## 8. 提交前清单

- [ ] 只新增了 `apps/client/games/<id>/` 一个目录，没有改任何共享文件
- [ ] 名称、角色、美术、音频、关卡全部原创（第 0 节）
- [ ] `game.json` 通过 `make games-check`，中英文字段都填了
- [ ] 入口脚本继承 `GameModule`，输入只经 `input(slot)`，随机只经 `rng`
- [ ] 自带 `*_test.gd`，`make games-test` 通过
- [ ] `ASSETS.md` 记了每一个素材文件
- [ ] `make ci` 与 `make ci-web` 通过
- [ ] 真实窗口里启动过一次，输出里没有 ERROR / WARNING
- [ ] 附了截图
