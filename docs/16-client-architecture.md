# 客户端架构（Godot）

更新时间：2026-11-11
状态：客户端是主机风格启动器，游戏是 `games/` 下由清单描述的目录（现有三款运行在三个 DSL 运行时上，另可以是游戏模块）；原先的竖屏手机应用壳（`app/`、`features/`、`shell/`、`ui/`、`core/`、`platform/`）已整体移除

## 1. 目录与依赖方向

```text
apps/client/
├── project.godot          # 主场景 launcher/launcher.tscn，1920×1080 画布，launcher_* 输入动作，无 autoload
├── default_bus_layout.tres # 音频总线：Master 之下 Music 与 SFX 两条
├── export_presets.cfg     # Web / Windows / macOS / Android / iOS 导出预设
├── launcher/              # 主机风格启动器：外壳、屏幕、控件、本地存档、PC 模式，以及它们的测试（第 3 节）
├── runtime/               # 游戏运行时：GameSession、RuntimeLoader、JSON Patch、DSL 迁移、shooter / survivor / tower_defense（第 2 节）
├── games/                 # 每款游戏一个目录（清单 game.json、主视觉、ASSETS.md，模块游戏另有脚本和测试），以及共用支持库 games/shared/（第 2.1 节）
├── testing/               # 只供测试用：夹具模块、故意写错的清单、模块契约测试；不随导出发布
├── i18n/                  # 界面文案：strings.gd（入口）与 launcher_strings.gd（启动器文案表），见 18-i18n
├── assets/                # 目前为空
└── spike_test.gd          # 运行时的 headless 测试（make spike）
```

允许的依赖方向：

```text
launcher      → i18n
             └→ runtime/game_session.gd（仅此一个文件）
runtime       → runtime/ 与 games/shared/
games/shared  → 不依赖 games/shared/ 之外的任何目录
games/<id>    → 自己的目录与 games/shared/（不依赖启动器、runtime、别的游戏）
i18n          → 不依赖 i18n/ 之外的任何目录
```

客户端不发任何网络请求，没有账号、登录和服务端状态。后端（`apps/server`）、CLI、MCP 与 SDK 仍在仓库里，它们与客户端之间只通过 `runtime/` 下的数据文件相连（见第 2 节末尾），不通过网络。

`scripts/check-client-boundaries.sh` 在本地和 CI 中检查这些规则：

- 启动器里出现的每个 `res://` 路径都必须属于 `res://launcher/`、`res://i18n/` 或恰好是 `res://runtime/game_session.gd`；不得按类名使用运行时的类（`RuntimeLoader`、`JsonPatch`、`Shooter*` 等）；
- 启动器里不得出现网络类（`HTTPRequest`、`HTTPClient`、`WebSocketPeer` 等）、`/api/` 端点和网址；
- 启动器不得按类名使用游戏支持库的类（`GameModule`、`GameRegistry`、`GameManifest`、`GameInput`、`GameAudio` 等），游戏的清单只经 `GameSession.catalog()` 得到；
- 运行时只引用 `res://runtime/` 与 `res://games/shared/`，不按类名使用任何 `Launcher*` 类，也不自己打开网络连接或持有地址；某款游戏的入口脚本按清单里的路径在运行时加载，不写在代码里；
- 共用支持库 `games/shared/` 只引用自己；
- 每个游戏目录（`games/<id>/`，以及测试夹具 `testing/games/<id>/`）只引用自己的目录和 `res://games/shared/`，不使用启动器和运行时的类（包括 `GameSession`），不联网，不声明 `class_name`，不碰宿主的东西（`Input`、`InputMap`、`_input`、`user://`、`OS`、`AudioServer`、`DisplayServer`、`ClassDB`、窗口、视口与场景树，不写文件）；资源一律写完整的 `res://` 路径，`uid://`、经过上级目录的相对路径和运行时拼出来的 `res://` 前缀在客户端的每一棵树里都不允许，因为按路径的规则看不见它们；
- `i18n/` 只引用 `res://i18n/`；
- `*_screen.gd` 只存在于 `launcher/`。

`scripts/check-architecture.sh` 另外保证已移除的手机应用壳不回到仓库：`apps/client` 下不得再出现 `app/`、`features/`、`shell/`、`ui/`、`main.gd`、`main.tscn`，客户端源码和 `project.godot` 也不得再引用它们或 `AppState` autoload。

## 2. Runtime 边界

启动器与游戏只通过 `runtime/game_session.gd` 通信，双方禁止读取对方内部节点、状态或文件。`GameSession` 承载两种游戏：DSL 游戏（内置运行时加一份 DSL，启动器传 runtime ref 与完整有效 DSL）和游戏模块（`games/<id>/` 里继承 `GameModule` 的入口脚本，启动器传目录条目、开局选项、人数、种子和语言，见 2.1）。两种游戏的生命周期、快照和信号相同（`game_started` / `score_changed` / `paused_changed` / `game_ended` / `game_error`），不同的只是输入怎样到达：DSL 游戏经 `perform` 接收命令，模块经 `set_control(slot, control, strength)` 接收每位玩家的逻辑控制。

`GameSession.catalog(root)` 也是启动器得知「有哪些游戏」的唯一途径：它返回 `{ games, problems }`，前者是通过校验的清单（附解析好的 `dir`、`entry_path`、`art.image_path`），后者是清单缺失、不是合法 JSON 或不符合 schema 的目录及其全部问题。`GameSession.stage_for(entry)` 给出一款游戏的舞台（逻辑尺寸、是否像素美术、整数缩放倍数、原点是否居中）。

`GameSession` 有两种用法。`start_game` 加载后立即回传摘要，用于校验与预览。`start_run` 是真实的一局：运行时保持挂载并持续模拟，直到通关、失败、超时，或宿主调用 `end_run`；期间宿主用 `set_paused` 暂停、`snapshot` 读取 HUD 所需的状态、`perform` 发送少量命令（移动、加速、护盾、放塔），并监听 `game_started` / `score_changed` / `paused_changed` / `game_ended`。结束时的结果包含 `play_seconds`（不含暂停）、`timed_out`、`aborted`。DSL 运行时以自身原点为中心绘制 `STAGE_SIZE`（960×540）的舞台；模块以左上角为原点绘制清单声明的舞台。宿主把 `GameSession` 放进 `SubViewport`，按 `stage_for` 的结果设置它（3.3）。`baseline_payload(runtime_ref)` 返回某个运行时内置基线的启动参数，宿主因此不必自己读运行时目录里的文件。

Runtime 目录同时是仓库里其他部分的数据来源：`runtime/<name>/baseline.dsl.json` 是后端注册的基线，`runtime/shooter/testdata/fork_expected.dsl.json` 是客户端 `runtime/json_patch.gd` 与 Go 模块 `packages/dsl` 共用的 golden。两份补丁实现、两份迁移实现（`runtime/dsl_migrations.gd` 与 `packages/dsl/migrate.go`）必须同语义，改其中一侧时另一侧、两边的测试和共用的夹具要在同一个 PR 里一起改。对应的 schema 在 `packages/schemas`。

`runtime/network_match_session.gd` 与 `runtime/network_match_runtime.gd` 是联机对局的运行时：前者只接纳服务端按 tick 递增的权威快照，后者把快照里的玩家画出来。它们不自己联网，由宿主传入一个端口对象来收发；启动器目前没有联机入口，所以现在只有 `spike_test.gd` 用到它们。

### 2.1 游戏目录、清单与游戏模块

```text
apps/client/games/
├── shared/                 # 共用支持库，不是游戏
│   ├── game_module.gd      # GameModule：模块契约的全部（生命周期、输入、快照、结束、信号）
│   ├── game_input.gd       # GameInput：一位玩家的逻辑输入状态，与固定步对齐
│   ├── game_audio.gd       # GameAudio：合成的音效与曲子，以及音频文件的音乐（循环、交叉淡化）、过场短曲（压低或暂停音乐）和音效，输出到 SFX / Music 总线
│   ├── game_synth.gd       # GameSynth：音效合成器（叠层振荡器与噪声、ADSR、音高包络、滤波扫频、FM / 环形调制、回声与混响）
│   ├── game_sfx.gd         # GameSfx：现成的音效预设
│   ├── game_sprites.gd     # GameSprites：高清美术的图集与帧表、按逻辑坐标绘制、帧动画、平铺与九宫格
│   ├── game_text.gd        # GameText：游戏里的平滑文字（系统字体）
│   ├── game_rng.gd         # GameRng：确定性的随机数（xorshift32）
│   ├── game_fixed_step.gd  # GameFixedStep：把可变帧时间换成整数个固定步
│   ├── game_manifest.gd    # GameManifest：清单 schema 与校验
│   ├── game_registry.gd    # GameRegistry：发现 games/*/game.json
│   ├── manifest_check.gd   # make games-check 运行的检查脚本
│   ├── media_check.gd      # make export-test 在导出包内运行：加载每款游戏的每张图片、每个音频文件、每份帧表
│   ├── synth_dump.gd       # 把音效预设写成 WAV 的小工具
│   └── shared_test.gd      # 支持库自己的测试
├── shooter/ survivor/ tower_defense/   # kind: "dsl"，各有 game.json、key_art.jpg、site_screenshot.png、ASSETS.md
└── <id>/                   # 以后的游戏：kind: "module"，另有入口脚本、素材和 *_test.gd
```

- **发现。** 启动时（第一次有屏幕读目录时）`GameRegistry` 列出 `res://games` 下除 `shared` 之外的每个目录，读它的 `game.json` 并校验。没有任何地方登记游戏列表，所以加一个目录就是加一款游戏。导出版里 `res://` 是资源包而不是磁盘目录，`DirAccess` 仍能列出包内的目录；清单是 `.json`，在「导出全部资源」下会被打包，`export_presets.cfg` 的每个预设另外在 `include_filter` 里写明 `*.json`，并用 `exclude_filter` 排除 `testing/*` 和只给官网用的 `games/*/site_screenshot.*`。`make export-test` 导出一个资源包并在包内运行发现来守住这一点。
- **无效的清单不会让启动器崩溃。** 该游戏不进目录；启动器启动时用 toast 说明有几款没能加载以及第一条原因，「设置 › 关于」逐条列出，`make games-check` 则直接失败。
- **启动器不持有任何单款游戏的数据。** `launcher_catalog.gd` 与 `launcher_game_guide.gd` 只剩查询逻辑：名称、类型、人数、配色、成就及其条件、玩法说明、操作表、HUD 字段、开局选项全部读自清单。原有三款游戏的清单是 `kind: "dsl"`，照旧运行各自运行时的基线 DSL；它们特有的字段（`runtime`、`options[].path`、`towers`、`tuning`）也在清单里。
- **游戏模块的契约**见 [20-adding-a-game](./20-adding-a-game.md)：入口脚本的 API、清单字段、舞台与缩放、每位玩家的输入、能碰与不能碰的东西。
- **测试夹具** `apps/client/testing/games/fixture_duo/` 是一个用到整个契约的最小模块（双人、卷轴、倒计时、生命、首领、选项、合成声音），`fixture_arena/` 补上它没有的部分（单人座位、平滑舞台、模拟量移动、成就读取 `finish()` 附带的字段），`fixture_gallery/` 覆盖高清美术与录制音频（精灵图集与帧表、平铺贴图、平滑文字、循环音乐文件、过场短曲、文件音效、预设音效）。三者只供测试使用，不在随附的目录里；`LauncherCatalog.use_root()` 让测试把目录指向它们。`testing/unfit_games/` 是清单有效但目录不合格的样本，供清单检查的自测使用。
- **舞台渲染。** 舞台是启动器里一个固定 1920×1080 的 `SubViewport`。像素舞台（`stage.pixel_art: true`）按逻辑分辨率渲染，由容器以整数倍、最近邻过滤放大；平滑舞台把 `size_2d_override` 设为逻辑尺寸并开启拉伸，逻辑坐标映射到 1920×1080 上再栅格化，模块节点的贴图过滤是线性加 mipmap（`GameSprites.FILTER`，由 `GameSession` 在挂载模块时设置），项目的导入默认值让新导入的贴图都生成 mipmap。高清美术按「画多大就多大」的逻辑坐标绘制，源图的分辨率由帧表里的 `scale` 换算，详见 [20-adding-a-game](./20-adding-a-game.md) 第 8 节。

## 3. 主机风格启动器（launcher）

客户端的主场景是 `apps/client/launcher/launcher.tscn`：一个固定 1920×1080 画布（`canvas_items` 拉伸、`aspect=keep`）的主机风格启动器，键盘、手柄、鼠标都能完整操作。

```text
apps/client/launcher/
├── launcher.tscn / launcher_root.gd  # 外壳与组合根：背景层、游戏舞台、屏幕注册与切换、顶部导航、toast、输入分发
├── launcher_screen.gd                # 屏幕基类：生命周期、handle_action、页脚按键提示
├── launcher_tokens.gd                # 设计 token（颜色、字号、间距、动效时长、系统字体）
├── launcher_widgets.gd               # 文本、容器、分隔线等小工厂
├── launcher_controls.gd              # 可交互控件：FocusRow、Tab、Glyph、GlyphHint、ArtCard、Tile
├── launcher_input.gd                 # 输入动作名、事件到动作的翻译、按键覆盖
├── launcher_store.gd                 # 唯一本地存档 user://launcher.json
├── launcher_catalog.gd               # 游戏目录：经 GameSession.catalog() 读清单，查询与成就条件求值，不含任何单款游戏的数据
├── launcher_players.gd               # 本地玩家座位与设备分配，把输入事件翻译成「第几位玩家的哪个控制」
├── launcher_key_art.gd               # 每款游戏的主视觉（程序化占位，可被图片替换）
├── launcher_game_host.gd             # 经 GameSession 运行游戏并把结果写入存档
├── launcher_format.gd                # 分数、时长、「今天/昨天」等显示格式
├── home_screen.gd                    # 首页
└── launcher_test.gd / launch_test.gd / launcher_shot.gd
```

其余屏幕各有一小节：3.1 游戏库与成就，3.2 设置，3.3 游戏流程（游戏菜单、局内、暂停），3.4 PC 模式。

- 启动器完全本地：不登录、不发网络请求，唯一的持久状态是 `LauncherStore` 的 `user://launcher.json`；运行时不得反向依赖启动器（第 1 节）。
- 屏幕不读 `InputEvent`。`LauncherRoot` 把每次按键、手柄按下和页脚提示的点击翻译成 `LauncherInput` 的动作名，交给当前屏幕的 `handle_action`；屏幕不处理的动作回落到外壳（LB/RB、LT/RT 切换顶层标签，B 返回）。
- 焦点由屏幕自己持有（分区名 + 序号），控件只负责外观并发出 `hovered` / `activated`，不使用 Godot 自带的键盘焦点。
- 屏幕上关于玩家的一切（游玩时长、上次游玩、最高分、收藏、最近游玩、成就）都读自 `LauncherStore`，只有真实游玩和真实操作会写入；没有记录时如实显示空状态。
- 游戏只经 `LauncherGameHost` 启动。它是外壳的一层而不是屏幕，游戏屏与暂停屏在它上面切换时舞台保持挂载。
- 成就图标（目录的 `icon` 字段：`star`、`bolt`、`cup`、`shield`，以及 `lock`）只有一份实现 `LauncherControls.Icon.draw_badge`，主机屏幕的 `Icon` 和 PC 模式的 `Symbol` 都经它绘制。

### 3.1 游戏库与成就

```text
apps/client/launcher/
├── library_screen.gd / achievements_screen.gd  # 游戏库（分类、排序、搜索、封面网格）与成就
├── launcher_scroll_grid.gd           # 按整行滚动的等大单元格网格，游戏库封面与成就列表共用
└── library_test.gd                   # 游戏库与成就屏的无头测试（make library-test）
```

- 页内标签用 LB/RB，顶层标签用 LT/RT：游戏库的分类和成就屏的筛选都吃掉 LB/RB，其余屏幕不处理时 LB/RB 仍回落到外壳。
- 网格类屏幕用 `LauncherScrollGrid`：屏幕持有焦点序号，网格只负责摆放、把指定单元格滚进可视行、画右侧位置条；`LauncherScrollGrid.step()` 统一四个方向的边界行为（左右到行尾停住，向下落到较短的末行时取其最后一格）。会滚动的单元格用自己的 `pointed` 信号（真实鼠标移动）而不是 `hovered` 来接管焦点，否则网格滚动时停在原地的指针会把焦点抢走。
- 游戏库的数据入口是 `LauncherLibraryScreen.entries`（默认取自 `LauncherCatalog.all()`，`set_entries()` 可整体替换），分类只有全部、最近游玩、收藏和目录里出现的类型；搜索按拼音首字母或英文名的词首匹配。
- 文本输入是「屏幕不读 `InputEvent`」的唯一例外：游戏库的搜索层打开期间，其根节点在 `_input` 里先于外壳取走字母键和退格键当作文字，其余按键照常翻译成动作；手柄用同一层上的屏幕键盘。
- 成就屏只显示目录定义的成就及其真实解锁时间，存档里目录已不再定义的解锁记录不计数；没有稀有度和排行榜。
- 游戏库的 Menu 键和成就屏详情面板的按钮都以 `{"game": id}` 打开该游戏的游戏菜单（3.3），从那里返回时回到原来的屏幕和焦点。

### 3.2 设置屏与设置项

`settings_screen.gd`（屏幕）、`settings_controls.gd`（设置行、开关、滑块、对话框按钮、改键时读取原始按键的 `KeyCapture`）和 `launcher_settings.gd`（设置项的键、默认值、取值范围，以及把它们应用到引擎的代码）组成设置屏，测试在 `settings_test.gd`（`make settings-test`）。

- 每个设置项都经 `LauncherStore.set_setting` 保存，修改时立即生效，并在下次启动时由 `LauncherRoot._ready` 调用 `LauncherSettings.apply_all` 再次应用。读取一律走 `LauncherSettings.value(store, key)`：存档文件可以被手改，不在取值范围内的值按默认值处理。
- 设置项的键（存档 `settings` 段）：`lang`（`zh` / `en`）、`clock_24h`（布尔，外壳时钟 24 / 12 小时制）、`default_mode`（`console` / `pc`）、`window_mode`（`windowed` / `maximized` / `fullscreen` / `exclusive`，默认 `maximized`）、`vsync`（布尔）、`max_fps`（`0` 为不限，或 30 / 60 / 120 / 144）、`volume_master`、`volume_music` 与 `volume_sfx`（0 至 10 的音量档位）、`audio_mute`（布尔）。
- `default_mode` 由设置屏写入，设置屏自己不读取：`LauncherRoot._ready` 在启动时读取它，决定是否直接进入 PC 模式（3.4）。
- 窗口模式与垂直同步只在启动器就是真实窗口的内容时才会应用（`LauncherSettings.drives_window`）；headless 测试和把启动器挂在离屏视口里的截图脚本不会改动窗口。
- 音频总线定义在 `apps/client/default_bus_layout.tres`：`Master` 之下有 `Music` 与 `SFX` 两条总线。运行时和游戏模块的背景音乐（合成的曲子、音乐文件和过场短曲）输出到 `Music`，游戏模块经 `GameAudio` 播放的音效（合成的和文件的）输出到 `SFX`，设置屏「声音」页的「音乐」「音效」两行分别控制它们。
- 「玩家按键」页列出游戏模块用的两套键盘方案（`project.godot` 里的 `game_p1_*` 与 `game_p2_*`，各十个控制：四个方向和 A B X Y L R），和「控制」页一样可以逐个改键、按页恢复默认。冲突只在两套方案之间检查（界面的键和玩家的键可以相同，二者不会同时生效），替换时照样交换，所以哪位玩家都不会失去某个控制的按键；暂停用的键（Menu、Back）和玩家按键不能共用，哪一侧想占用对方的键都会被拒绝并提示。手柄不经 `InputMap`：`LauncherPlayers.PAD_BUTTONS` 按位置固定映射。
- 改键只改键盘按键，保存在存档的 `bindings` 段（只保存与 `project.godot` 默认值不同的操作），由 `LauncherInput.reset_and_apply` 应用。一次改键把该操作换成单独一个新键；新键已被别的操作占用时先弹出确认，替换后对方若因此没有按键，就接过本操作原来的按键，所以任何操作都不会失去键盘按键。`LauncherInput.apply_bindings` 会跳过不含有效按键的条目。手柄按键是固定的，设置屏只按 `InputMap` 的内容把它们列出来。
- 手柄连发：十字键或摇杆的方向保持按下时，`LauncherRoot` 在 `LauncherInput.REPEAT_DELAY` 秒后开始按 `REPEAT_INTERVAL` 的间隔重复派发该方向，每帧至多一次；松开、手柄断开或窗口失去焦点时停止。键盘方向键仍依靠系统自身的按键重复。
- 存档页的导出把完整存档写成 `classic-games-profile-<日期>-<时间>.json`（默认在系统的「文档」文件夹）；导入从同一文件夹列出最近的导出文件，经 `LauncherStore.read_profile`（与读取存档相同的版本检查和规范化）后用 `replace_progress` 只替换进度（游玩记录、收藏、最近游玩、成就），设置和按键保持不变，并可在提示消失前撤销；清除进度前必须确认，确认框的默认焦点在「取消」。
- 启动器目录不允许出现网址（`check-client-boundaries.sh` 的本地化约束），所以「关于」页的仓库地址只作展示，不会打开浏览器。

### 3.3 游戏流程：游戏菜单、局内、暂停

```text
apps/client/launcher/
├── menu_screen.gd            # 单款游戏的菜单：开始、玩法与操作、游玩记录、成就、开局选项、收藏
├── game_screen.gd            # 局内：HUD、输入到游戏指令的翻译、结算
├── pause_screen.gd           # 暂停：继续、重新开始、主音量、退出到游戏菜单，右侧是这款游戏的操作表
├── launcher_game_guide.gd    # 从清单读每款游戏的玩法说明、操作表、HUD 取数、塔的显示名、开局选项、人数（只有查询，没有数据）
├── launcher_game_widgets.gd  # 这三屏共用的控件：键帽、进度条、HUD 按钮、滑块行、确认对话框等
└── game_flow_test.gd         # make game-flow-test
```

- **一局的生命周期。** `LauncherGameHost` 只在一局结束时写存档，别处都不写；`GameSession.end_run` 对已经结束的一局什么也不做。所以无论怎么结束（打完、暂停里退出、暂停里重新开始、从别的入口离开游戏屏或暂停屏、关窗口、启动器被销毁），每局都恰好记录一次。游戏屏打开暂停屏时这一局保持挂载并冻结；从暂停屏「继续」或「重新开始」回到游戏屏时舞台上仍有一局，其余任何离开方式都会结束它。窗口失去焦点会自动暂停。
- **一局进行期间不能切到 PC 模式。** 只要 `game_host.is_running()`（正在玩，或停在暂停屏、暂停屏的确认框上），F11 和长按 View 都被 `LauncherRoot.toggle_pc_mode` 拒绝，只弹出 toast `launcher.pc.busy_game`，这一局不受影响。一局结束后（结算界面）可以切换。
- **本地双人与玩家座位。** `LauncherGameHost.players`（`LauncherPlayers`）持有座位和设备：设备是 `kb1`、`kb2`（两套键盘方案）和每个已连接手柄的 `pad:<设备 id>`。单人时两套键盘方案和所有手柄都控制玩家一；双人时每个座位恰好一个设备，默认没有手柄时是两套键盘方案、一个手柄时玩家一用键盘而玩家二用手柄、两个手柄时各用一个，未分配的设备的输入被忽略。清单允许两人的游戏在游戏菜单里多出「玩家人数」一行（按游戏记在设置键 `game_players.<游戏 id>`），选两人时再多出每位玩家一行设备（左右切换，选中对方的设备则两人互换）。设备分配不存盘，因为手柄 id 不跨重启。
- **模块游戏的输入不经过屏幕。** 一局模块游戏进行时，`LauncherRoot._unhandled_input` 先把每个输入事件交给 `LauncherGameHost.feed_event`，由 `LauncherPlayers.translate` 翻译成「座位、控制、力度」，经 `GameSession.set_control` 写进该玩家的 `GameInput`；事件不被消耗，随后照常被看作启动器动作。游戏屏对模块游戏只处理暂停：任何来源的 Menu，以及来自键盘的 Back（Esc）。手柄的 B、Y、LB、RB 在模块游戏里是游戏按键，所以不暂停、不隐藏 HUD、不切标签。窗口失去焦点时所有控制被松开。
- **暂停归属。** 暂停的那位玩家拥有这次暂停（`game_host.pause_owner`）：双人时只有他的设备能操作暂停屏，另一位的输入被忽略并用 toast 说明；鼠标算键盘一侧。没有归属的暂停（失去焦点、手柄拔出）、单人局、归属者的设备已拔出，以及在暂停屏里改过设备之后，任何输入都可以操作，所以不会有人被锁在暂停屏外。
- **加入、退出与设备断开。** 清单声明 `players.join_in_progress` 的游戏，暂停屏多出「加入玩家 2 / 移除玩家 2」一行；双人时暂停屏还有每位玩家的设备行，可以当场换设备。正在玩的座位的手柄被拔出时，这一局自动暂停并提示，玩家可以在暂停屏里换到还在的设备，或让那位玩家退出。
- **HUD 的第二个玩家角。** 能坐两人的模块游戏在右上角有玩家二的一角（标记色 `PLAYER_TWO`），与左上角玩家一的一角对称：分数、清单 `hud.vital` 的条、`hud.player_stats` 的计数，取自快照的 `players[座位]`；座位空着时显示「P2 可从暂停菜单加入」或「P2 未加入」。共享的计数（`hud.stats`）和首领血条排在它下面。结算界面在总分旁列出每位玩家的分数。
- **局内输入（DSL 游戏）。** 按下的动作照常经 `handle_action` 到达游戏屏。有两件事「按下」表达不了，由游戏屏每帧从同一批启动器动作轮询：按住（射击游戏的加速）和带力度的方向（塔防准星）。飞机和主角的移动由运行时自己读 Godot 内置的 `ui_*` 动作，启动器不转发。
- **HUD 只读 `game_host.snapshot()`。** 显示哪些字段由 `LauncherGameGuide` 的 `clock` / `vital` / `stats` 决定。运行时放在节点上而没进摘要的数据由 `GameSession.snapshot()` 补出：`max_hp`、`base_hp_max`、`shield_hits`、`boost`、`boss_hp` / `boss_max_hp`、塔的目录 `towers`。
- **舞台分辨率。** `LauncherGameHost` 在开局前按 `GameSession.stage_for` 设置舞台视口。普通舞台（三款 DSL 游戏的 960×540，以及 `pixel_art` 为 false 的模块）：视口与画布同为 1920×1080，用 `size_2d_override` 把逻辑坐标映射上去，图形按满分辨率栅格化。像素美术舞台：视口就是逻辑分辨率（如 480×270），由 `SubViewportContainer.stretch_shrink` 按整数倍、最近邻过滤放大，每个逻辑像素是一个清晰的方块。`to_stage` / `to_canvas` 按当前舞台的尺寸换算。
- **开局选项。** 清单的 `options` 列出的参数才出现在菜单里（三款 DSL 游戏里目前只有射击游戏的 `stage.difficulty`）。选项值存在设置里（键 `game_option.<游戏 id>.<选项 id>`）；DSL 游戏开局时把它变成基线 DSL 上的一条 JSON Patch `replace`（清单的 `options[].path`），模块游戏则原样收到这些值。选项可以给每个值配显示名（`labels`）。
- **护盾冷却在启动器一侧。** 运行时对每次 `shield` 指令都会加一层护盾，不设上限；游戏屏规定已有护盾时不能再开，护盾被打掉后要等射击游戏清单里 `tuning.shield_cooldown` 秒。
- **主音量。** 与设置屏共用设置键 `volume_master`（整数 0 到 10，默认 10），暂停屏调整时和每次开局时应用到 Master 音频总线；静音开关归设置屏。
- **`LauncherRoot.close_to(id, args, closing)`** 用来离开一段嵌套流程：先把 `closing` 里的屏幕从返回历史里去掉再显示目标屏，这样从结算或暂停退到游戏菜单后，按返回是回到进入这段流程之前的地方，而不是回到已经结束的那一局。

### 3.4 PC 模式

F11 或长按 View 在主机模式与 PC 模式之间切换；`LauncherStore` 的设置项 `default_mode`（`"console"` 默认，或 `"pc"`）决定启动时进入哪一个。PC 模式是同一份数据的另一种布局，面向键盘和鼠标，不新增任何状态来源。

```text
apps/client/launcher/
├── pc_mode.gd            # LauncherPcMode：标题条、侧栏、状态条、焦点与输入、菜单、进出主机屏幕
├── pc_detail_view.gd     # 单个游戏的页面：主视觉、开始 / 游戏菜单 / 收藏 / 更多、概览与成就两个标签
├── pc_library_view.gd    # 游戏库：排序、网格 / 列表切换、类型筛选、可滚动的卡片或行
├── pc_library.gd         # 纯函数：分类、搜索、类型筛选与排序
├── pc_controls.gd        # PC 模式控件：Clickable 及其派生、Menu、SearchField、Flow
├── pc_tokens.gd          # PC 模式专用的颜色与尺寸
└── pc_mode_test.gd
```

- 挂载：`LauncherRoot` 默认注册 `pc_mode.gd`（`register_pc_mode` 可替换，传 `null` 则没有 PC 模式）。第一次进入时实例化并调用 `setup(shell)`，此后 PC 模式开启期间每个动作都交给它的 `handle_action`，主机层（屏幕、顶部导航、背景）整体隐藏。
- 窗口：应用运行在真实的系统窗口里，标题条只放品牌和「主机模式」按钮，不绘制最小化、最大化、关闭按钮。
- 选中的游戏双向保持：进入 PC 模式时取首页的 `hero_id`，离开时交还给首页。
- 借用主机屏幕：PC 模式没有自己的游戏画面、游戏菜单、完整成就页和设置页。需要它们时调用 `open_console(screen_id, args)`，切回主机模式并打开那一屏，这一趟叫一次「借用」。借用总是从首页出发（主机层此前停在别的屏幕时先回到首页），所以从借来的屏幕返回一定到达首页。
- 借用何时结束只有一条规则，写在 `LauncherPcMode._on_screen_changed`：**主机外壳到达首页时借用结束，PC 模式接回画面。** 从借来的屏幕返回、结算界面的「返回首页」、启动失败后的自动返回，都会自己到达首页。直接进游戏的借用（开始游戏、双击、Enter）多一个出口：游戏流程在一局结束后退到该游戏的游戏菜单（暂停屏确认退出、结算界面的「返回游戏菜单」或 B），而玩家并没有打开过那个菜单，所以外壳被接着送到首页，借用随之结束。「再来一局」和「重新开始」不离开游戏屏，借用继续。从游戏菜单的借用里开始的一局，退出后回到那个菜单，再返回才回到 PC 模式。主机模式下的游戏流程（3.3）不受这条规则影响。
- 借用结束回到 PC 模式时，选中的游戏、视图（游戏页或游戏库）、搜索与筛选都保持原样；借用期间在设置里换了语言，回来时整个 PC 模式按新语言重建，状态不变。玩家自己按 F11 则以玩家为准：借用就此结束，之后在主机模式里的操作不再把他带回 PC 模式。一局进行期间不能切到 PC 模式（见 3.3）。
- 鼠标：控件自带悬停与按下状态；单击选中，双击开始游戏，右键打开该游戏的菜单，滚轮滚动。
- 键盘与手柄：焦点是分区（搜索、侧栏、主区）加分区内的行列位置。Tab / Shift+Tab 换分区，方向键在分区内移动并可越过边界，Enter 激活（落在游戏上即开始），Ctrl+F 或 `/` 跳到搜索框，Esc 清空搜索，Y 收藏，M 打开游戏菜单，Q / E 在游戏页与游戏库之间切换，PageUp / PageDown 滚动。搜索框是启动器里唯一使用 Godot 自带键盘焦点的控件，因为输入文字需要它。
- 布局用容器搭建，网格列数由可用宽度算出，所以 PC 模式的区域变窄时会重排；`set_entries` 可以换入更多条目来检验（测试和截图工具使用），目录之外的条目能列出但不能开始。

## 4. 不变量

- Godot 4.6.3 精确版本门禁（`apps/client/.godot-version`）和 fail-closed 的测试 runner（`scripts/run-godot-test.sh`）：版本不符、脚本解析错误、资源泄漏、缺少成功摘要、超过时限都算失败；
- 启动器只经 `runtime/game_session.gd` 进入运行时和游戏，运行时与游戏都不认识启动器；
- 一款游戏是 `games/` 下的一个自足的目录：加一款游戏不改任何共享文件，游戏之间互不引用；
- 客户端不联网，玩家数据只在 `user://launcher.json`；
- 每一局恰好记录一次，屏幕上关于玩家的数据都来自真实游玩；
- 两个检查器（`check-client-boundaries.sh`、`check-architecture.sh`）各有自测（`scripts/tests/`），先证明规则会在违例时失败，再检查仓库。
