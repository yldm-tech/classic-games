# 添加一款游戏

一款游戏是 `apps/client/games/<id>/` 下的一个目录。加一款游戏只需要加这个目录：启动器的目录、游戏菜单、成就、局内 HUD、官网的游戏列表，以及测试和清单检查，都在启动时或构建时自己发现它。不需要也不应该改任何共享文件（`launcher/`、`runtime/`、`i18n/`、`project.godot`、`Makefile`、CI、`apps/web`）。如果你发现必须改共享文件才能做完，那是契约的缺口，请单独提 issue，不要在游戏的 PR 里顺手改。

本文是游戏作者的参考。权威定义在代码里：契约是 `apps/client/games/shared/game_module.gd`，清单 schema 是 `apps/client/games/shared/game_manifest.gd`。可运行的完整样例是三个测试夹具：`apps/client/testing/games/fixture_duo/`（双人、中途加入、卷轴摄像机、像素舞台、倒计时、生命、首领）、`apps/client/testing/games/fixture_arena/`（单人、平滑舞台、模拟量移动、清场结束、成就读取 `finish()` 附带的字段）和 `apps/client/testing/games/fixture_gallery/`（高清美术与录制音频：精灵图集与帧表、帧动画、平铺贴图、平滑文字、循环音乐文件、过场短曲、文件音效与预设音效，见第 8 节）。夹具放在 `res://testing/games/` 下；你的游戏在 `res://games/<id>/` 下，照抄时把路径换掉。

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
├── *.gd / *.tscn …    # 游戏自己的脚本、场景、数据，可以放进子目录
├── art/               # 可选：高清美术（图集 .png 与帧表 .json、背景 .jpg / .webp），见第 8 节
├── audio/             # 可选：录制音频（.ogg：音乐、过场短曲、音效），见第 8 节
├── key_art.png        # 可选：16:9 主视觉，由清单的 art.image 指向（可以在子目录里）
├── site_screenshot.png# 可选：官网用的局内截图，由清单的 site.screenshot 指向；必须叫这个名字、放在目录顶层
├── ASSETS.md          # 每个素材文件的来源与许可
└── <id>_test.gd       # 自带的 headless 测试，至少一个 *_test.gd，必须放在目录顶层
```

`<id>` 是小写字母、数字、下划线，以字母开头，全仓库唯一。它同时是存档里的键，发布后不要改。测试文件只在目录顶层才会被运行：放进子目录的 `*_test.gd` 永远不会跑，`make games-check` 会把它报成错误。

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

只有 `_game_start` 和 `_game_step` 是必需的。不要定义 `_process` 或 `_physics_process`，也不要覆盖或自己调用宿主一侧的方法（`start`、`set_paused`、`snapshot`、`feed`、`release_inputs`、`join`、`leave`、`advance`）以及基类的 `finish`、`input`、`active_players` 等：GDScript 里同名方法会无声地替换基类的实现（自己写了 `_process` 的游戏永远不会被推进），所以 `make games-check` 读入口脚本的源码，发现这些名字就失败。

生命周期的几个事实：

- 每一局是入口脚本的一个新实例，「再来一局」也是。宿主先把它加进场景树（`_ready` 在这时运行），再调用 `_game_start`。测试可能对同一个实例调用两次 `start`，所以这一局的状态在 `_game_start` 里初始化，不要只靠成员变量的初始值。
- `_game_start` 里调用 `finish()` 无效：一局不能在开始之前结束。
- `finish()` 之后模拟立刻停止，`_game_step` 和 `_game_frame` 都不再被调用，最后一帧留在结算界面下面。想让玩家看到的结束演出（死亡动画、过关特效）要在调用 `finish()` 之前播完：用 `_game_step` 里的计时器推迟 `finish()`。一局里只有第一次 `finish()` 算数。
- 暂停时宿主停掉模块节点（及其子节点）的处理，继续时恢复；`_game_paused` 只是通知。
- 没有结束条件的游戏（玩家永远不会赢也不会输）也可以：玩家随时可以从暂停菜单退出，那一局记为中途退出。

### 2.2 你使用的

| 成员 | 说明 |
|---|---|
| `input(slot)` | 第 `slot` 位玩家（0 是玩家一）的 `GameInput`，见 2.3 |
| `active_players()` / `player_count()` / `is_player_active(slot)` | 当前在玩的座位 |
| `score` | 这一局的总分，整数。直接赋值，宿主会记录它并显示在 HUD |
| `rng` | 用 `config.seed` 播种的 `GameRng`：`next_u32()`、`unit()`（0 到 1）、`int_range(low, high)`（两端都含）、`float_range(low, high)`、`chance(probability)`、`pick(array)`、`shuffle(array)`（原地打乱并返回）。玩法里的所有随机都用它，并且只在 `_game_start` 和 `_game_step` 里用；不要用全局的 `randf()` / `randi()`，否则同一个种子无法重放，测试也就写不稳。反过来，`_game_frame` 里纯表现的随机（粒子抖动）不要用 `rng`：渲染帧数因机器而异，会把玩法的随机序列带偏；那里用 `randf()` 或自己另建一个 `GameRng.new(种子)` |
| `audio` | `GameAudio`：合成的音效与曲子，以及来自音频文件的音乐、过场短曲和音效，见 2.6 |
| `STEP` | 常量，一个固定步的秒数（1/60） |
| `stage_size` | 逻辑舞台的像素尺寸，见 2.5 |
| `elapsed` | 已模拟的秒数，不含暂停。玩法里的计时都用它或自己累加 `delta`，不要读系统时钟（`Time.get_ticks_msec()` 等） |
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

`just_pressed` / `just_released` 与固定步对齐：恰好一步为 true；两步之间按下又松开的轻点也会被看到一步。`pad.strength(GameInput.RIGHT)` 是单个控制的力度（0 到 1，键和按钮只有 0 或 1），力度不小于 0.5 才算「按下」（`is_down`、`move_sign`），所以轻推摇杆时 `move` 已经有值而 `move_sign()` 还是零。暂停时所有控制被松开，继续后需要玩家重新按下；窗口失去焦点、手柄被拔掉时也一样。没人坐的座位读出来是什么都没按。

输入只在 `_game_step` 里读：`just_pressed` 是按步计算的，在 `_game_frame` 里读会漏掉或重复。

游戏目录里**不得**出现 `Input.`、`InputMap`、`InputEvent`、`_input(`、`_unhandled_input(`：`make boundary-test` 会拒绝。

### 2.4 快照、HUD 与结果

`_game_snapshot()` 返回 HUD 要显示的字段。基类已经提供 `score`、`elapsed`、`player_count`、`active_players`；你补充清单 `hud` 段里点名的字段。宿主每个渲染帧都调用它，所以它只读状态、不改状态，也不要在里面做重活。字段的值可以是任何类型（测试里常放坐标），但 HUD 和成就只读数字。约定：

- 全局字段放在顶层，例如 `time_left`、`wave`、`boss_hp`。
- 每位玩家各自的字段放在 `players` 数组里，下标是座位：`players[0] = { score, lives, max_lives, … }`。HUD 的每位玩家各有一角，生命条（`hud.vital`）和 `hud.player_stats` 从这里取；`players[i].score` 存在时显示该玩家自己的分数。
- 首领血条在 `hud.boss.field` 出现在快照里时显示，首领不在场时不要输出这个字段。
- 除首领血条外，清单 `hud` 段点名的每个字段从第一步起就必须在快照里：`make games-check` 会用默认选项、最多人数把游戏启动一步，缺哪个字段就报哪个（否则拼错的字段只会显示成 0，没有任何提示）。`players` 存在时必须是数组，每个座位一个字典，单人开局时也给满。
- 记入存档的最高分是顶层的 `score`（就是你赋值的那个成员）。`players[i].score` 只用于显示；双人游戏通常让 `score` 等于两人之和。

一局结束时的结果是「结束那一刻的快照 + `cleared` / `defeated` / `timed_out` + `finish()` 的 `extra`」，宿主再加上 `play_seconds`（不含暂停）和 `aborted`（玩家中途退出）。成就条件（清单的 `achievements[].when`）就是对这份结果求值，所以成就要用到的量（死亡次数、收集数、是否无伤……）必须出现在快照或 `extra` 里，而且要在结果的顶层、是数字（布尔值按 0 / 1 算）：`players[i]` 里面的字段和不是数字的字段不满足任何条件。只在结束时才知道的量（命中率、用时评级）放进 `finish()` 的 `extra` 最方便。玩家中途退出的一局不会解锁成就，但时长和分数照常记录。结算界面显示结果、分数、用时和 `hud.stats` 里的计数。

### 2.5 舞台、缩放与摄像机

清单的 `stage.size` 声明逻辑舞台，必须是 1920×1080 除以整数：960×540、640×360、480×270、384×216、320×180 等。游戏以**左上角为原点**、按 `stage_size` 的逻辑像素作画，不读窗口或视口尺寸。

- `stage.pixel_art: true`：舞台按逻辑分辨率渲染，再以整数倍、最近邻过滤放大到 1920×1080，每个逻辑像素是一个清晰的方块；模块节点的 `texture_filter` 已设为最近邻。像素美术用这个。
- `stage.pixel_art: false`（默认）：舞台按 1920×1080 渲染，逻辑坐标映射上去，矢量图形、文字和高清贴图都保持锐利。高清美术用这个，细节见第 8 节。

作画有两种办法，可以混用：在入口脚本里实现 `_draw()` 并在 `_game_frame` 里调用 `queue_redraw()`；或者把 `Sprite2D`、`TileMapLayer`、`Polygon2D` 等节点加为模块的子节点，在 `_game_frame` 里按状态摆放它们。舞台没有默认背景，自己先画一层底色。

卷轴关卡：给模块加一个 `Camera2D` 子节点并移动它，舞台就是摄像机的视野，两种舞台模式下都一样（夹具 `fixture_duo` 用的是 `ANCHOR_MODE_FIXED_TOP_LEFT`，默认的居中锚点也可以，配合 `limit_left` / `limit_right`）。摄像机的位置如果影响玩法或进快照，就在 `_game_step` 里移动它。单屏游戏不需要摄像机。

HUD 由启动器画在舞台之上，重要的东西别只放在它下面：上方约 16% 高度（左上、右上角是玩家信息，中间是时钟）；用了 `hud.player_stats` 或 `hud.stats` 时两个角会向下伸到约 24%，右上角再加首领血条时到约 29%；右下角是暂停按钮。HUD 不跟随摄像机。

**玩法不要交给引擎的物理和计时节点。** `advance()`（测试）和固定步只推进 `_game_step`；`CharacterBody2D` / `Area2D` / `RigidBody2D` 的碰撞、`_physics_process`、`Timer`、`get_tree().create_timer()`、`Tween`、`AnimationPlayer`、粒子都按引擎自己的帧时间走，测试里根本不会前进，同一个种子也重放不出同一局。碰撞自己在 `_game_step` 里算（网格查表、矩形相交、圆距离，两个夹具都是这样），计时自己累加 `delta`。这些节点可以放心用在纯表现上。

游戏里的文字：仓库不带字体文件，中文靠系统字体。共享库的 `GameText` 把启动器用的那套系统字体配方包好了：`var text := GameText.new()` 建一次存起来（一个中文字体几十 MB，不要每帧新建），在 `_draw()` 里 `text.draw(self, 位置, 文字, 字号, 颜色, 对齐, 宽度, 字重, 描边宽度, 描边颜色)`，位置是基线；不给宽度时按这个点对齐（左起、居中或右止），`text.measure(文字, 字号)` 量尺寸，`text.font(字重)` 取出字体给 `Label` 或自己的 `draw_string` 用。字号是逻辑像素：平滑舞台上字形按画布分辨率栅格化（480×270 舞台上的 14 号字实际是 56 个画布像素高），和启动器的文字一样平滑。文字按 `locale`（`"zh"` 或 `"en"`）二选一，两种语言都要有。像素舞台上的文字会被整数倍放大成方块，字号按逻辑像素算；得分、时间、生命这些交给 HUD，不用自己画。

### 2.6 声音

`audio`（`GameAudio`）有两类声音，可以混用：运行时合成的（不带文件，也就没有音频许可要记），和游戏目录里的音频文件（第 8 节讲怎么准备）。音效走 `SFX` 总线，音乐和过场短曲走 `Music` 总线，音量和静音由玩家在设置里调，游戏不碰总线。暂停时所有声音由宿主停住，继续时从原处接着响；一局自己结束时音乐在 0.4 秒内淡出，最后一个音效和过场短曲照常响完；玩家中途退出时全部立刻停止。这些游戏都不用管。

**合成音效。** 在 `_game_start` 里 `define`（合成发生在这时，同一份参数在整个进程里只合成一次），之后按名字 `play`：

```gdscript
audio.define("jump", {"wave": "square", "freq": 330, "freq_end": 660, "duration": 0.12})   # 单层，老写法，一直有效
audio.define("coin", GameSfx.preset("coin"))                                              # 现成的预设
audio.define("stomp", GameSfx.preset("impact", {"pitch": 0.8, "volume": 0.5}))            # 预设改几个值
audio.define("zap", {"volume": 0.5, "normalize": true, "vary": {"pitch": 0.06}, "layers": [   # 自己叠层
	{"wave": "saw", "freq": 900, "freq_end": 200, "glide": "exp", "duration": 0.2, "decay": 0.19, "sustain": 0.0, "filter": {"type": "lowpass", "cutoff": 6000, "cutoff_end": 900, "q": 1.4}},
	{"wave": "white", "duration": 0.03, "volume": 0.4, "filter": {"type": "highpass", "cutoff": 3000}},
]})
audio.play("jump")                 # 第二个参数是音高倍率，第三个是音量增减（dB）
```

预设（`GameSfx.names()` 列出全部）：`impact`、`explosion_small`、`explosion_large`、`crumble`、`break`、`shot_laser`、`shot_blaster`、`shot_heavy`、`shot_light`、`zap`、`jump`、`land`、`bounce`、`whoosh`、`splash`、`door`、`pickup`、`coin`、`power_up`、`extra_life`、`hurt`、`ui_move`、`ui_confirm`、`ui_cancel`。`GameSfx.preset(名字, 覆盖项)` 返回一份可以直接 `define` 的参数；覆盖项替换顶层的键（`volume`、`drive`、`delay`、`reverb`、`tail`、`vary`、`layers`），另有两个只在这里有效的键：`pitch` 把里面所有频率乘上一个倍数，`speed` 把所有时间除以一个倍数。预设都做了归一化，`volume` 就是它的峰值。

一份参数要么是一层（下表「层」的键直接写在顶层，就是老写法），要么是 `{ "layers": [层, …] }` 加上这些整体的键：

| 键 | 说明 |
|---|---|
| `duration` | 主体的秒数。省略时取最晚结束的那一层；单层时默认 0.15 |
| `volume` | 总音量，0 到 1（有 `layers` 时默认 1）。配合 `normalize` 时就是结果的峰值 |
| `normalize` | `true`：把结果缩放到峰值等于 `volume`，响度不再取决于各层恰好怎么叠加 |
| `drive` | 0 到 1，软饱和，增加厚度和颗粒感 |
| `delay` | `{ "time": 秒, "feedback": 0 到 0.9, "mix": 0 到 1 }`，回声 |
| `reverb` | `{ "mix": 0 到 1, "size": 0 到 1, "damp": 0 到 1 }`，小房间混响 |
| `tail` | 主体之后留给回声和混响的秒数（设了 `delay` 或 `reverb` 时默认 0.6，否则 0） |
| `vary` | `{ "pitch": 0 到 0.5 }`：每次播放随机移调这么大的比例，连续触发时不会像机关枪。只影响听感，不碰玩法的 `rng` |

层：

| 键 | 说明 |
|---|---|
| `wave` | `square`（默认）、`pulse`、`triangle`、`saw`、`sine`、`noise`（移位寄存器噪声，颗粒感，`freq` 是它变化的频率）、`white`、`pink` |
| `freq` / `freq_end` | 起始和结束频率（Hz，默认 440 / 同起始） |
| `glide` / `glide_time` | `"linear"`（默认）或 `"exp"`（按音程均匀滑动，扫频用它更自然）；`glide_time` 是滑完全程所占的比例，之后保持 |
| `steps` | `[倍数, …]`：音高在这一层里等分地跳过这些倍数，琶音用；`[1, 1.5]` 就是两个音的叮咚 |
| `vibrato` | `{ "rate": Hz, "depth": 半音 }` |
| `start` / `duration` | 这一层从第几秒开始、持续几秒（默认从 0 到主体结束） |
| `volume` | 0 到 1，默认 0.5 |
| `attack` / `decay` / `sustain` / `release` | ADSR 包络：淡入秒数（默认 0.004）、从峰值降到 `sustain` 的秒数（默认 0）、保持的电平（0 到 1，默认 1）、结尾淡出秒数（默认 0.05）。打击类的声音用 `decay` 约等于时长、`sustain` 为 0 |
| `curve` | 包络的指数：1 是直线，2 或 3 掉得更快，像被敲了一下 |
| `duty` / `duty_end` | `pulse` 的占空比及其扫动 |
| `unison` / `detune` | 1 到 3 个失谐的副本，及它们的音分间距（默认 12），让音色变厚 |
| `fm` | `{ "ratio": 调制频率与 freq 之比, "index": 起始深度, "index_end": 结束深度 }`，相位调制：铃声、金属、低吼 |
| `ring` | `{ "freq": Hz, "freq_end": Hz, "mix": 0 到 1 }`，乘以一个正弦：慢的是颤音，快的是金属碰撞声 |
| `filter` | `{ "type": "lowpass" / "highpass" / "bandpass", "cutoff": Hz, "cutoff_end": Hz, "q": 0.3 到 12 }`，截止频率按指数扫过这一层 |
| `seed` | 整数，让两层噪声互不相同 |

整个音效（含尾巴）最长 4 秒，同时最多响 8 个；同一个音效在 25 毫秒内被再次请求时只计数、不重复起播。合成是确定的：同一份参数在任何机器上得到同样的字节。把预设写成 WAV 来听或测量：`godot --headless --path apps/client --script res://games/shared/synth_dump.gd -- <输出目录> [预设名…]`。

**合成曲子**（老接口，一直有效）：

```gdscript
audio.play_music({"bpm": 132, "voices": [
	{"wave": "pulse", "volume": 0.3, "notes": [["C4", 1], ["E4", 1], ["G4", 2]]},
	{"wave": "triangle", "volume": 0.4, "notes": [["C2", 2], ["G2", 2]]},
]})
```

音符是 `[音高, 拍数]`，音高是音名（`"F#3"`、`"Bb2"`）、MIDI 编号或休止 `"-"`；声部的波形是 `square`、`pulse`、`triangle`、`saw`、`sine`、`noise`。按最长的一个声部循环，最长 64 秒。

**音频文件。** 文件放在自己的目录里，用完整的 `res://games/<id>/…` 路径在 `_game_start` 里登记，之后按名字播放：

```gdscript
audio.load_music("stage", "res://games/<id>/audio/stage.ogg")            # 选项：{"volume_db": 0, "loop": true, "loop_start": 0.0}
audio.load_stinger("clear", "res://games/<id>/audio/clear.ogg")         # 选项：{"volume_db": 0}
audio.load_sound("roar", "res://games/<id>/audio/roar.ogg", {"vary": 0.05})   # 选项：{"volume_db": 0, "vary": 0}

audio.play_track("stage")              # 循环播放；从正在放的音乐交叉淡入，默认 0.8 秒，第二个参数改时长，0 是硬切
audio.play_track("boss", 1.5)          # 换曲就是再调一次；要的就是正在放的那首时什么都不发生，所以每次进入某个状态都可以调
audio.play_stinger("clear")            # 响一次；默认把音乐压低 14 dB，放完再升回来
audio.play("roar")                     # 文件音效和合成音效同一个 play
audio.stop_music(1.0)                  # 淡出 1 秒；不给参数是立刻停
```

`play_stinger(名字, 方式)` 的方式：`GameAudio.STINGER_DUCK`（默认，压低音乐再恢复）、`STINGER_PAUSE`（音乐停在原处，短曲放完从原处继续）、`STINGER_OVER`（不动音乐）、`STINGER_STOP`（音乐淡出不再回来，给游戏结束的短曲用）。短曲放到一半音乐被停掉（包括 `finish()`）时，短曲照常放完，音乐不会回来。`load_*` 在文件加载不了时返回 false 并在输出里报错（真实窗口里的 ERROR 会让提交前检查不过）；`play_track`、`play_stinger`、`play` 遇到没登记的名字什么都不做并返回 false。

headless 测试里没有声音设备，什么都不会真的播放，但每个调用都照常记账：`audio.played["jump"]` 是每个音效、短曲、曲目被请求的次数，`audio.music_playing`、`audio.music_track`（正在放的曲目名，合成曲子和没有音乐时是 `""`）、`audio.stinger_playing` 都可以拿来断言。

### 2.7 能碰什么，不能碰什么

可以：自己目录下的任何脚本、场景和数据；`games/shared/` 的库；作为模块子节点的任何 Godot 节点（`Node2D`、`Camera2D`、`TileMapLayer`、粒子、`AnimationPlayer`……，玩法上的限制见 2.5）；用 `FileAccess` 只读地读自己目录里的数据文件（`FileAccess.get_file_as_string("res://games/<id>/levels/1.json")`）。

不可以，其中前六条由 `make boundary-test` 机械地检查（按文本扫描，注释和字符串里出现这些写法同样会被拒绝）：

- 引用自己目录和 `games/shared/` 之外的任何 `res://` 路径：不能用启动器的代码、`runtime/`、`i18n/`，更不能用另一款游戏的文件。
- 用别的写法绕开上一条：`uid://` 路径、经过上级目录的相对路径（`preload("../x.gd")`）、把 `"res://"` 前缀和后半段在运行时拼起来。资源一律写完整的 `res://games/<id>/…`（`"res://games/<id>/levels/%d.json" % n` 这样的格式串可以）。
- 声明 `class_name`。全局类名会与别的游戏冲突，用 `const X := preload("res://games/<id>/x.gd")`。出于同样的原因，内部类不要以自己所在的脚本为类型（Godot 会在退出时报资源仍在使用，所有门禁都会失败）。
- 读全局输入：`Input.`、`InputMap`、`InputEvent*`、`_input(`、`_unhandled_input(`、`_gui_input(`（见 2.3）。
- 碰宿主的东西：`user://`、`OS.`、`ProjectSettings`、`AudioServer`、`DisplayServer`、`Engine.time_scale` / `max_fps` / `get_main_loop()`、`get_tree().root` / `.paused` / `.quit` / `.current_scene`、`get_window()`、`get_viewport()`、以 `/root` 开头的节点路径、`DirAccess`、`ClassDB`，以及写文件（`FileAccess.WRITE` / `READ_WRITE`、`ResourceSaver`）。存档、音量、窗口、暂停都是启动器的。
- 联网：任何网络类（`HTTPRequest`、`HTTPClient`、`WebSocket*`、`StreamPeer*`、`PacketPeer*`、`ENet*`、`WebRTC*`、`MultiplayerPeer*`、`UPNP*`、`IP.`、`JavaScriptBridge`……）、URL、端点。
- 新增第三方依赖或 Godot 插件。
- 往 `project.godot` 加 autoload、输入动作或图层名。

## 3. 清单 `game.json`

完整的例子是 `apps/client/testing/games/fixture_duo/game.json` 和 `apps/client/testing/games/fixture_arena/game.json`。字段（schema 1）：

| 字段 | 必需 | 说明 |
|---|---|---|
| `schema` | 是 | `1` |
| `id` | 是 | 等于目录名 |
| `kind` | 是 | `"module"`。（`"dsl"` 是内置 DSL 运行时的三款游戏用的，新游戏不用） |
| `entry` | 是 | 入口脚本，目录内的相对路径，如 `"main.gd"` |
| `stage` | 是 | `{ "size": [宽, 高], "pixel_art": true/false }`，见 2.5。`pixel_art` 省略时为 false |
| `name` | 是 | `{ "zh", "en" }`。`en` 同时是各语言下标题下方的拉丁副标题，习惯全大写 |
| `initials` | 是 | 中文名的拼音首字母，小写，供搜索 |
| `genre` | 是 | `{ "zh", "en" }`，`en` 全大写。游戏库按它分类，同类型的游戏请用完全相同的写法 |
| `tagline` | 是 | `{ "zh", "en" }`，一句话 |
| `players` | 是 | `{ "min": 1 或 2, "max": 1 或 2, "join_in_progress": bool }`，`min` 不大于 `max`。`max` 大于 `min` 时游戏菜单出现「玩家人数」一行；`join_in_progress`（可省略，只在 `max` 大于 `min` 时允许为 true）为 true 时玩家二可以在暂停菜单里中途加入或退出 |
| `colors` | 是 | `{ "title", "shadow", "glow" }`，`RRGGBB`，标题字、投影、辉光 |
| `art` | 是 | `{ "top", "bottom", "primary", "secondary" }`（`RRGGBB`，没有图片时的占位配色），可选 `"image"`（目录内的 16:9 图片，`.png` / `.jpg` / `.jpeg` / `.webp`，扩展名小写，可以在子目录里），可选 `"motif"`（占位图的图案：`"orbit"`、`"swarm"`、`"road"`，省略则是两团柔光）。没有 `image` 的游戏在启动器和官网上都显示用这组配色画的占位图 |
| `achievements` | 是 | `[{ "id", "icon", "name", "desc", "when" }]`，可以为空数组。`icon` 是 `star` / `bolt` / `cup` / `shield`。`when` 见下 |
| `how` | 是 | `{ "zh", "en" }`，一段话：目标、怎样算赢、怎样算输 |
| `controls` | 是 | `[{ "id", "name", "inputs" }]`。`inputs` 是 `"move"`（四个方向）或单个控制名 `"a"` `"b"` …。启动器据此在游戏菜单和暂停屏画出操作表（键盘键帽读自当前绑定，手柄图标固定），并自动补上「暂停」一行 |
| `hud` | 是 | 见下 |
| `options` | 否 | `[{ "id", "name", "note", "values": [整数…], "default", "labels": [{ "zh", "en" }…] }]`。开局选项，玩家在游戏菜单里选，值经 `config.options` 以整数传给游戏；`labels` 可选，与 `values` 一一对应，没有时菜单显示数字。启动器总是传全每个选项；测试里传什么就是什么，所以读的时候带默认值：`int(config["options"].get("speed", 2))` |
| `site` | 否 | 只给官网用：`{ "screenshot", "screenshot_alt": { "zh", "en" }, "art_alt": { "zh", "en" } }`，三项都可省略。截图文件必须命名为 `site_screenshot.<扩展名>` 并放在目录顶层（清单校验会检查）：导出预设按这个名字把它排除在游戏包之外 |

`achievements[].when` 的条件全部满足才解锁；`{}` 表示打完任意一局：

| 键 | 含义 |
|---|---|
| `"cleared": true/false` | 结果的 `cleared` 必须相等 |
| `"players": 2` | 结束时至少有这么多玩家（不能超过游戏的 `players.max`） |
| `"min": { "字段": 数 }` | 结果顶层的该字段不小于这个数；结果里没有这个字段按 0 算 |
| `"max": { "字段": 数 }` | 结果顶层的该字段存在且不大于这个数（例如 `{"deaths": 0}`） |

`hud`：

| 键 | 说明 |
|---|---|
| `clock` | 必需。`{ "mode": "countdown" / "elapsed" / "none", "field": 快照字段名, "total": 快照字段名（可选） }`。`field` 的值是秒；省略时显示这一局已玩的时间。有 `total` 时显示 `total - field`。`countdown` 向上取整并标「剩余时间」，`none` 不显示时钟 |
| `vital` | 可选。`{ "field", "max", "label": { "zh", "en" } }`，分数下面的条（生命、能量）。`field` 和 `max` **都是快照字段的名字，不是数字**：上限也由游戏放进快照（`"max": "max_lives"`，快照里给 `max_lives: 3`）。每位玩家从自己的 `players[i]` 取，玩家一取不到时退回顶层 |
| `player_stats` | 可选。`[{ "label", "fields": [一个或两个字段] }]`，每位玩家角上的小计数，从 `players[i]` 取；两个字段显示为 `a / b` |
| `stats` | 可选。同上格式，全局计数，显示在右上 |
| `boss` | 可选。`{ "field", "max", "label" }`，`field` 和 `max` 同样是快照字段名，`label` 可省略；`field` 在快照里出现时显示首领血条 |

清单里任何一层出现未知字段都是错误（防止 `join_in_progres`、`pixelart` 这样的拼写错误悄悄失效）。清单无效的游戏不会进入目录：启动器启动时用 toast 说明，「设置 › 关于」逐条列出问题，`make games-check` 则直接失败并打印全部问题。

## 4. 本地双人

清单 `players.max` 为 2 的游戏自动获得：游戏菜单里的人数选择和每位玩家的设备行、HUD 的第二个玩家角、暂停归属（谁暂停谁操作暂停菜单）、手柄拔出时自动暂停、结算界面上每位玩家各自的分数。游戏一侧要做的只有：

- 对 `active_players()` 里的每个座位读 `input(slot)` 并各自模拟。单人开局时只有座位 0。
- 快照里给出 `players[0]` 和 `players[1]`。
- 若声明了 `join_in_progress`，实现 `_game_player_joined` / `_game_player_left`（给新玩家一个出生点、把离开的玩家移出场景）。不声明则人数在开局时确定，中途不变。

单人时两套键盘方案和所有手柄都控制玩家一；双人时每位玩家恰好一个设备（没有手柄时是两套键盘方案同屏，有一个手柄时玩家一键盘、玩家二手柄，有两个时各一个，玩家可以在菜单和暂停里改）。这些都与游戏无关：游戏永远只看到 `input(0)` 和 `input(1)`。玩家二离开后 `active_players()` 里不再有座位 1，但 `players[1]` 仍要留在快照里。

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
- 传给 `start` 的 `stage_size` 要和清单的 `stage.size` 一致：测试不读清单，不传时是 960×540。`players`、`seed`、`options`、`locale` 不传时分别是 1、1、空、`"zh"`。
- `advance()` 只调用 `_game_step`，不调用 `_game_frame`，也不推进任何引擎节点（见 2.5）。测试里不要 `await` 渲染帧来等游戏前进。
- `feed(slot, control, strength)` 是「按住」，要松开就再喂一次 0；模拟一次点按是喂 1、`advance(GameModule.STEP)`、再喂 0。
- 每个建出来的游戏实例在测试结束前 `free()` 掉，否则退出时的泄漏检查会判失败。
- `_initialize` 里的脚本错误（比如读了一个不存在的字典键）会让测试停在原地：Godot 不会自己退出。runner 给每个 Godot 进程 600 秒时限（环境变量 `GODOT_TEST_TIMEOUT` 可改），超时算失败并指出是哪个测试；本地先单独跑一次自己的测试，输出里的 `SCRIPT ERROR` 会告诉你是哪一行。

单独跑一个测试（在仓库根目录）：

```bash
GODOT=/path/to/godot scripts/run-godot-test.sh res://games/<id>/<id>_test.gd '^<id>_test: [0-9]+ passed, 0 failed$'
```

运行：

| 命令 | 作用 |
|---|---|
| `make games-check GODOT=<godot>` | 清单 schema、入口脚本能加载且继承 `GameModule` 并且没有重定义基类的方法、用默认选项启动一步后快照里有 HUD 点名的每个字段、目录顶层有测试、官网截图存在、`ASSETS.md` 覆盖全部素材、素材不超预算且格式和导入设置正确（第 8.6 节） |
| `make games-test GODOT=<godot>` | 自动发现并运行每个 `games/*/*_test.gd`（以及共享库和契约测试）。新游戏的测试不需要登记到任何地方 |
| `make boundary-test` | 依赖方向与 2.7 的禁止项 |
| `make export-test GODOT=<godot>` | 导出资源包并在包内运行发现，确认游戏在导出版里也能被找到，并且每款游戏的每张图片和每个音频文件在包里都能加载 |
| `make ci GODOT=<godot>` | 以上全部加其余门禁；`make ci-web` 是官网门禁（官网会读你的清单） |

## 6. 素材来源 `ASSETS.md`

目录里每一个不是源码的文件（图片、音频、字体、模型……凡扩展名不在 `gd uid import json md tscn tres gdshader gdshaderinc txt cfg` 之内的）都要在 `ASSETS.md` 里占一行，写明它是什么、从哪里来、以什么许可分发。图集的帧表（`.json`）算源码，不用单列，写在图集那一行里即可。生成的素材照着生成时留下的来源记录（第 8.7 节）写：用的模型、提示词、做过哪些处理。`make games-check` 检查每个这样的文件名都以反引号出现在 `ASSETS.md` 里。

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

截图工具用一份临时存档，不碰你自己的；`LAUNCHER_SHOT_LOCALE=en` 换成英文界面。局内结束后再截就是结算屏（让输入脚本把这一局打完，或把时限选项调短）。

PR 里请附游戏菜单、局内（单人，支持双人的再加双人）和结算三屏的截图，中英文各看一遍。要在官网上显示局内画面，把一张局内截图存为游戏目录顶层的 `site_screenshot.png`，并在清单的 `site.screenshot` 里写上文件名（同时记进 `ASSETS.md`）；没有这张图的游戏在官网上只显示主视觉，连主视觉也没有时显示一块用清单配色画的面板。往游戏目录里加图片或音频后跑一次 `make import GODOT=<godot>`，把生成的 `.import` 文件一起提交（`.gd` 旁边的 `.uid` 文件同理）。

## 8. 高清美术与录制音频

像素舞台加合成芯片音乐是一种风格，不是唯一的选择。要做插画质感的画面和制作过的音乐，用平滑舞台、高分辨率贴图和音频文件；共享库提供加载和绘制，`scripts/assets/` 提供制作工具。完整的样例是夹具 `apps/client/testing/games/fixture_gallery/`。

### 8.1 平滑舞台到底怎么渲染

清单里 `"stage": { "size": [480, 270], "pixel_art": false }`。游戏仍然在 `stage.size` 的逻辑坐标里摆放一切（所以玩法代码和坐标不用变），宿主把这个逻辑舞台映射到一块固定 1920×1080 的画布上：

- 舞台视口的大小恒为 1920×1080 像素，`size_2d_override` 设为 `stage.size` 并开启拉伸。一个逻辑像素等于 `1920 / 宽` 个画布像素：480×270 是 4，640×360 是 3，960×540 是 2。所有绘制命令先经过这个变换再栅格化，所以线条、圆、多边形、文字都是在 1920×1080 上画的，不是先画小图再放大。
- 贴图同理：把一张 256 像素高的角色图画成 32 个逻辑像素高，它在屏幕上占 128 个画布像素，是从 256 缩小到 128，不是从 32 放大。
- 模块节点的 `texture_filter` 由宿主设为「线性 + mipmap」（`GameSprites.FILTER`），视口默认过滤是线性，不做像素对齐（`snap_2d_transforms_to_pixel` 关闭），所以精灵可以停在小数坐标上平滑移动。自己加的子节点继承这个过滤，不要再设成最近邻。
- 文字的字形按画布分辨率栅格化（引擎按视口的缩放做字体过采样），字号仍按逻辑像素写。
- 窗口再把这块 1920×1080 的画布整体缩放到实际大小（保持 16:9）。也就是说 1080p 是画面的上限分辨率：素材做得比「它在 1080p 画布上占的像素」大出一倍以上只是白占体积。

像素舞台（`pixel_art: true`）的规则不变：按逻辑分辨率渲染，最近邻整数倍放大。两种舞台不能混用，一款游戏选一种。

### 8.2 尺寸、格式与预算

| 素材 | 源尺寸 | 格式 | 说明 |
|---|---|---|---|
| 角色、敌人、道具的帧 | 屏幕上占的画布像素的 1 到 2 倍。480×270 舞台上 32 逻辑像素高的角色占 128 画布像素，帧高 192 到 256 像素正合适；占半屏的首领 384 到 512 | 带透明通道的 PNG，打进图集 | 生成时用 1024×1024，一帧一张，打包时统一缩小（`pack --max-frame 256`） |
| 图集 | 每边不超过 2048（硬上限 4096，超过的贴图在 WebGL 和不少手机上加载失败） | PNG | 一个角色或一组相关的东西一个图集，各自配一份帧表 |
| 地块、可平铺的纹理 | 屏幕上占的画布像素的 1 到 2 倍：16 逻辑像素的格子占 64 画布像素，源图 128 | PNG（要透明）或 JPEG / WebP（不透明）；打进图集时加 `--extrude 2` | 平铺用的纹理要先做成无缝的（`assets.py tile`） |
| 整屏背景 | 1920×1080；卷轴用的宽背景每边不超过 4096 | JPEG（质量 85 到 90）或 WebP，不透明的图不要用 PNG | 一张 1080p 的 JPEG 约 300 到 600 KB，同一张图的 PNG 要 2 到 4 MB |
| 有透明的视差层 | 同背景 | PNG 或 WebP | |
| 音乐 | 30 到 90 秒的循环 | Ogg Vorbis，立体声，质量 5（约 160 kbit/s，每分钟约 1.2 MB） | 响度 -18 LUFS |
| 过场短曲 | 2 到 10 秒 | Ogg Vorbis | 响度 -16 LUFS |
| 文件音效 | 2 秒以内 | Ogg Vorbis，单声道 | 峰值 -3 dBFS |

**预算：每款游戏提交进仓库的素材合计约 15 MB。** 这些字节每一次克隆、每一个网页版都要带上。`make games-check` 的硬线是：单个素材文件不超过 4 MB，一款游戏的素材合计不超过 16 MB，超了就失败。典型的分配：三到四首音乐 4 到 5 MB，背景 2 到 3 MB，图集 4 到 6 MB，其余给短曲和音效。

为什么音频只用 Ogg Vorbis：Godot 对它的循环是按采样对齐、没有间隙的；MP3 和 AAC 的编码器会在首尾加静音，循环点上必然有一个小空档，所以 `games-check` 直接拒绝游戏目录里的 `.mp3` 等格式（短音效也可以用 `.wav`）。音乐模型给的是 MP3，用 `assets.py audio` 转（8.5）。

**导入设置。** 往目录里加了图片或音频后跑一次 `make import GODOT=<godot>`，把生成的 `.import` 文件一起提交。项目的导入默认值（`project.godot` 的 `[importer_defaults]`）已经让新导入的贴图生成 mipmap，其余保持 Godot 的默认：`compress/mode=0`（无损；不要改成 VRAM 压缩，2D 美术会出色块）、`process/fix_alpha_border=true`（防止透明边缘出暗边）。平滑舞台的游戏里，除主视觉（`art.image`）和官网截图之外的每张图片都必须是 `mipmaps/generate=true`，`games-check` 会查；改设置前就导入过的图片，把它的 `.import` 里这一行改成 `true` 再跑一次 `make import`。音频的 `.import` 不用动：是否循环由 `load_music` / `load_stinger` 在运行时设置。

### 8.3 加载和绘制：`GameSprites`

一个 `GameSprites` 是一张贴图加一组有名字的帧。每一帧知道自己的一个源像素等于多少逻辑像素，所以绘制时只给逻辑坐标：

```gdscript
var hero: GameSprites
var sky: GameSprites
var ground: GameSprites

func _game_start(config: Dictionary) -> void:
	hero = GameSprites.load_atlas("res://games/<id>/art/hero.json")                 # 图集 + 帧表，assets.py pack 生成
	sky = GameSprites.load_image("res://games/<id>/art/sky.jpg", {"height": 270})   # 单张图，一帧，名字是 "main"
	ground = GameSprites.load_image("res://games/<id>/art/ground.png", {"height": 32})

func _draw() -> void:
	sky.draw_fit(self, "main", Rect2(Vector2.ZERO, Vector2(stage_size)))
	ground.draw_tiled(self, "main", Rect2(0, 238, stage_size.x, 32), Vector2.ZERO, Vector2(camera_x, 0))
	hero.draw_animation(self, "run", elapsed, hero_position, facing_left)
	hero.draw(self, "hurt", other_position, false, 1.0, 0.0, Color(1, 1, 1, 0.5))
```

| 方法 | 说明 |
|---|---|
| `GameSprites.load_atlas(帧表路径)` | 读帧表和它旁边的图。加载不了时返回一个空的图集（什么都画不出来）并报错，不会崩 |
| `GameSprites.load_image(图片路径, 选项)` | 单张图作为一帧 `"main"`。选项：`{"scale": 每个源像素的逻辑像素数}` 或 `{"height": 逻辑高度}` 或 `{"width": 逻辑宽度}`（默认 scale 1），`{"pivot": Vector2 比例}`（默认中心 `Vector2(0.5, 0.5)`；`Vector2(0.5, 1)` 是底边中点） |
| `GameSprites.load_grid(图片路径, 列, 行, 选项)` | 等大格子的图，逐行读成帧 `"0"`、`"1"`……；`height` / `width` 是一格的逻辑尺寸，另有 `{"count": 用到的格数}` |
| `draw(canvas, 帧, 位置, flip_h = false, zoom = 1.0, rotation = 0.0, modulate = 白, flip_v = false)` | 把帧的锚点（pivot）画在这个位置，自然大小乘 `zoom`；翻转、缩放、旋转都绕锚点。带旋转的绘制会设置并复位画布项的绘制变换 |
| `draw_animation(canvas, 动画, 秒数, 位置, flip_h, zoom, rotation, modulate)` | 画动画在这一刻的帧 |
| `draw_fit(canvas, 帧, 矩形, modulate)` | 拉伸填满一个逻辑矩形：背景、格子上的地块、进度条 |
| `draw_tiled(canvas, 帧, 矩形, 单块尺寸 = 自然大小, 滚动偏移, modulate)` | 用这一帧平铺填满矩形，边缘裁齐；滚动偏移给卷轴地面和视差层用 |
| `draw_patch(canvas, 帧, 矩形, 边宽, modulate, 四边不同时的 Vector4)` | 九宫格：四角不变形，边单向拉伸，中间双向拉伸；边宽是源像素。面板、对话框用 |
| `size(帧)` / `bounds(帧, 位置, zoom)` | 帧的逻辑尺寸；画在某个位置时占的逻辑矩形（做碰撞盒对齐、调试用） |
| `animation_frame(动画, 秒数)` / `animation_length(动画)` / `has_animation` / `define_animation(名字, 帧列表, fps, 是否循环)` | 帧动画。秒数传 `elapsed` 或你自己在 `_game_step` 里累加的计时器，不要传系统时钟：这样暂停时姿势会停住，测试里也能断言当前是哪一帧 |
| `has_frame` / `frame_names()` / `frame_texture(帧)` | `frame_texture` 返回这一帧的 `AtlasTexture`，给 `Sprite2D`、`TextureRect`、粒子用；节点再按 `scale` 缩到逻辑尺寸 |
| `texture` / `scale` | 整张贴图；每个源像素的逻辑像素数 |

碰撞盒继续用你自己的数字，不要从图上量：图是画出来的，盒子是玩法。动画的进度由模拟时间决定，所以「画哪一帧」可以写成一个只读状态的函数，在 `_draw()` 和快照里共用（夹具里的 `keeper_frame()`）。

帧表（JSON，放在图片旁边，`assets.py pack` 生成，也可以手写）：

```json
{ "format": 1, "image": "hero.png", "scale": 0.125,
  "frames": { "run_0": { "rect": [2, 2, 180, 240], "source": [180, 240], "offset": [0, 0], "pivot": [90, 240] } },
  "animations": { "run": { "frames": ["run_0", "run_1"], "fps": 10, "loop": true } } }
```

`rect` 是这一帧（裁掉空边之后）在图集里的位置；`source` 是没裁之前的尺寸，`offset` 是裁剩的部分在其中的位置，`pivot` 是锚点，都按源像素；`scale` 是每个源像素的逻辑像素数，帧里可以单独再写一个。

### 8.4 制作美术：`scripts/assets/assets.py`

工具只依赖 Python 3.10+、Pillow 和 numpy（`pip install -r scripts/assets/requirements.txt`），音频另需命令行的 ffmpeg 和 sox；每个命令的全部参数见 `scripts/assets/README.md` 和 `assets.py <命令> --help`。生成类的命令从环境变量 `EVERYAPI_KEY` 读密钥（只在调用它的那条命令的环境里设置，不写进任何文件，工具也从不打印它），并且必须给 `--log`（来源记录文件）和 `--date`（今天的日期）。生成的原始文件放在仓库外面，只把处理好的成品提交进游戏目录。

一个角色的流程：

```bash
A=scripts/assets/assets.py; RAW=~/classic-games-assets/<id>; LOG=$RAW/provenance.jsonl; D=<今天的日期>

# 1. 基准姿势，画在纯色背景上。提示词里写清楚：全身、侧面、朝右、居中留白、纯品红底、无阴影、无地面、无发光、无文字。
python3 $A image --prompt "<角色描述>. Full body, side view facing right, standing idle, centred with empty space around it. Isolated on a perfectly flat solid pure magenta (#FF00FF) background, no shadow, no ground, no glow, no text" --size 1024x1024 --out $RAW/hero_base.jpg --log $LOG --date $D

# 2. 把底色抠成透明（去溢色、收边、羽化）。角色身上有光晕把底色染开时加大 --tolerance（0.2 到 0.25）。
python3 $A key $RAW/hero_base.jpg $RAW/hero/idle.png

# 3. 以抠好的透明图为参考生成其余姿势和动画帧：设计保持一致，结果自带透明通道。一次一个请求，按顺序跑。
python3 $A pose --reference $RAW/hero/idle.png --pose "running, left leg forward" --out $RAW/hero/run_0.png --log $LOG --date $D
python3 $A pose --reference $RAW/hero/idle.png --pose "running, right leg forward" --out $RAW/hero/run_1.png --log $LOG --date $D

# 4. 裁边、统一缩小、打成图集，写出帧表。文件名就是帧名，name_0、name_1…… 自动成为动画 name。
python3 $A pack $RAW/hero/*.png --out apps/client/games/<id>/art/hero --max-frame 256 --height 32 --height-of idle --fps run=10
```

每一张生成的图都要亲眼看过再用：多出来的肢体、变了样的设计、被裁掉的身体、图里出现文字或水印、残留的底色边，都重新生成。`pack` 的要点：`--height 32 --height-of idle` 表示帧 `idle` 的内容高 32 个逻辑像素，其余帧用同一个比例；锚点默认是每一帧内容的底边中点（`--pivot bottom --anchor content`），所以分别生成、在画面里位置不一的姿势都会站在同一条地面线上；需要帧与帧严格对位时（同一张图切出来的部件）用 `--anchor frame`。地块用 `--no-trim --extrude 2 --pivot topleft`。

背景和纹理：

```bash
python3 $A image --prompt "<场景描述>, no characters, no text" --size 1920x1080 --out $RAW/sky.jpg --log $LOG --date $D
python3 $A fit $RAW/sky.jpg apps/client/games/<id>/art/sky.jpg --size 1920x1080 --quality 88      # 裁成确切尺寸，存 JPEG / WebP
python3 $A tile $RAW/stone.jpg apps/client/games/<id>/art/stone.jpg --size 256x256               # 做成无缝平铺的纹理
python3 $A inspect apps/client/games/<id>/art/*                                                 # 尺寸、模式、透明范围、字节数
```

### 8.5 制作音频

```bash
# 音乐：说清楚是纯器乐、不要人声，写上速度、调式、配器、情绪，并要求乐句重复以便循环。
python3 $A music --prompt "Instrumental, no vocals. <风格、速度、配器>, a repeating four-bar phrase so it can loop" --seconds 60 --out $RAW/stage.mp3 --log $LOG --date $D
# 转成游戏用的循环：找循环点、交叉淡化接缝、统一响度、编码 Ogg Vorbis。
python3 $A audio $RAW/stage.mp3 apps/client/games/<id>/audio/stage.ogg --kind music --loop
# 过场短曲（过关、失败、强化）：同一个模型，要求有明确的结尾。
python3 $A music --prompt "Instrumental, no vocals. A short triumphant fanfare that ends on a clear final chord" --seconds 8 --out $RAW/clear.mp3 --log $LOG --date $D
python3 $A audio $RAW/clear.mp3 apps/client/games/<id>/audio/clear.ogg --kind stinger
# 录制的音效文件（如果有）：裁掉首尾静音、短淡入淡出、峰值归一。
python3 $A audio $RAW/roar.wav apps/client/games/<id>/audio/roar.ogg --kind sfx --mono
python3 $A inspect apps/client/games/<id>/audio/*.ogg        # 时长、LUFS、峰值、接缝
```

**循环是怎么做的。** 生成的曲子有开头和收尾，直接首尾相接会咔哒一声。`audio --loop` 做四件事：跳过开头的静音；找到结尾开始渐弱的位置，只用它之前的部分；在可用的范围里选一个循环长度，使循环点之后的音乐与开头最相似（相同的音落在相同的拍子上，所以选出来的长度是整小节、通常是整乐句）；把紧跟在循环之后的 2 秒（`--crossfade`）淡出、叠在循环自己的开头上，开头同时淡入。这样从末尾接回开头时，听到的是音乐自然地往下走。报告里的 `loop_seconds`、`loop_similarity`（越接近 1 越好；低于 0.3 说明这首曲子没有重复的乐句，换 `--start` / `--end` / `--loop-seconds` 手动指定，或者重新生成）和 `seam_ratio`（接缝处的跳变与曲子里普通相邻采样的变化之比，1 左右听不出来）要看一眼。循环文件从头循环到尾，`load_music` 不需要 `loop_start`；想保留一段只播一次的前奏时，把前奏留在文件里并传 `{"loop_start": 前奏秒数}`。

**响度。** 所有音乐统一到 -18 LUFS，过场短曲 -16 LUFS，文件音效峰值 -3 dBFS，任何文件的峰值不超过 -1 dBFS；合成音效预设的峰值在 0.3 到 0.75 之间。这样换曲时音量不跳，音效和短曲盖得过音乐，总线不会削波。工具用 ffmpeg 的 EBU R128 测量（`loudnorm` 滤镜的测量结果），然后对整段施加**一个固定的增益**，不用 `loudnorm` 的动态模式：动态处理会让循环的开头和结尾被区别对待，接缝就又出来了。目标和实测值都在报告里（`target_lufs`、`lufs`）。各曲目之间还想微调时用 `load_music` 的 `volume_db`，不要重新编码。

**音效没有生成模型。** 音效用 2.6 的合成器和预设做；只有过关、失败、强化这类带旋律的短曲才用音乐模型。

### 8.6 检查

`make games-check` 在第 5 节那些之外检查素材：单个文件不超过 4 MB；合计不超过 16 MB；音频是 `.ogg`（或短音效的 `.wav`）；任何图片的边长不超过 4096；平滑舞台的游戏里每张舞台用的图片都带 mipmap 导入。`make export-test` 把每款游戏的每张图片、每个音频文件、每份帧表在导出的资源包里加载一遍，并在包里把夹具 `fixture_gallery` 整局跑完。你自己的测试里，至少断言一次图集和音频都登记上了（`sprites.has_frame(...)`、`audio.has_track(...)`），以及关键时刻播了该播的东西（`audio.music_track`、`audio.played[...]`）。

### 8.7 来源记录与原创

每次生成，工具都往你指定的 `--log` 文件追加一行 JSON：日期、种类（`image` / `pose` / `music`）、模型、完整的提示词、输出文件、内容的 SHA-256、尺寸或时长、用到的参考图。这个文件和原始素材一起留在仓库外面；写 `ASSETS.md` 时照着它写每个成品文件的模型、提示词和后续处理，不要凭记忆。

第 0 节的原创规则对生成的素材同样成立，而且更要小心：提示词只描述你自己设计的东西（造型、配色、材质、情绪、配器、速度），**不得出现任何现有游戏、作品、角色、公司或作者的名字，也不得要求「像某某」的画风或曲风**；不得把别人的图片或音乐当参考输入。图里不能有文字、标志和水印。生成的图像和音乐在版权上的地位见 [legal/licenses](./legal/licenses.md) 的说明。

## 9. 提交前清单

- [ ] 只新增了 `apps/client/games/<id>/` 一个目录，没有改任何共享文件
- [ ] 名称、角色、美术、音频、关卡全部原创（第 0 节）
- [ ] `game.json` 通过 `make games-check`，中英文字段都填了
- [ ] 入口脚本继承 `GameModule`，输入只经 `input(slot)`，玩法的随机只经 `rng`，玩法逻辑全在 `_game_step` 里（不靠物理引擎、`Timer`、`Tween`）
- [ ] 目录顶层自带 `*_test.gd`，`make games-test` 通过
- [ ] 提交了 Godot 生成的 `.uid` 和 `.import` 文件，`git status` 干净
- [ ] `ASSETS.md` 记了每一个素材文件；生成的素材照来源记录写明模型、提示词和处理
- [ ] 素材在预算内（单个文件 4 MB、合计 16 MB 以内），音频是统一过响度的 Ogg Vorbis，循环曲的接缝听过
- [ ] 没有把生成的原始文件、来源记录或密钥提交进仓库
- [ ] `make ci` 与 `make ci-web` 通过
- [ ] 真实窗口里启动过一次，输出里没有 ERROR / WARNING
- [ ] 附了截图
