# 客户端架构（Godot）

更新时间：2026-11-11
状态：七个 feature 切片与单一组合根已完成；主场景已切换为主机风格启动器（见第 8 节）

## 1. 目录与依赖方向

```text
apps/client/
├── main.gd                         # 创建 AppRoot
├── app/
│   ├── app_root.gd                 # composition root，只装配
│   ├── screen_registry.gd          # screen 生命周期/查找
│   └── chrome/chrome_controller.gd # 全局 chrome
├── core/http/
│   ├── api_result.gd               # 统一结果类型
│   └── http_client.gd              # transport-only
├── features/
│   ├── identity/                   # 认证与 session
│   ├── catalog/                    # 发现、搜索、详情、资料
│   ├── creation/                   # AI、mod、草稿、发布
│   ├── community/                  # 评论、收藏、关系、消息
│   ├── engagement/                 # 下载、历史、房间、回放
│   ├── commerce/                   # 积分、会员、活动、支付
│   └── operations/                 # 账号、偏好、举报、反馈
├── shell/                          # 设计 token、路由、全局/创作会话工具
├── runtime/                        # 独立游戏运行时
├── platform/                       # 原生能力端口
└── ui/                             # 无业务 components 与 patterns
```

允许的依赖方向：

```text
main → app → features → core
              │
              ├── ui
              ├── platform ports
              └── GameSession
```

`core` 不依赖 feature；feature 的 endpoint 只属于本域 `*_api.gd`；feature 不能 import 另一 feature 的 screen。`scripts/check-client-boundaries.sh` 与 `scripts/check-architecture.sh` 在本地和 CI 中检查这些规则。

## 2. Feature 标准形态

每个 feature 由四种角色组成：

- `*_screen.gd`：渲染 store，发出用户意图；不知道 URL、token 和原始 HTTP 字典。
- `*_coordinator.gd`：执行用例、并发保护、错误策略和跨端口编排。
- `*_store.gd`：持有页面/领域状态，以 signal 通知 UI；不执行 I/O。
- `*_api.gd`：拥有 endpoint、请求/响应 DTO 映射，返回 `ApiResult`。

一次操作只有一个方向：

```text
screen intent → coordinator → gateway → ApiResult → store → screen
```

七个现有切片共同构成参考实现。新增 feature 应复制角色边界，不复制业务代码，也不能借用相邻域的 store、screen 或 gateway。

## 3. HTTP 与错误

`HttpClient` 是唯一 transport 实现，负责：

- bearer token 注入；
- JSON 编解码与公共响应信封；
- offline、unauthorized、validation、conflict、rate-limited、unexpected 分类；
- 返回 `ApiResult`，不操作 store 或 UI。

Feature API 提供业务方法并拥有 URL。Coordinator 根据 `ApiResult.kind` 决定重试、登录跳转、页面错误或 toast。Screen 只显示已经归一化的状态。

## 4. 应用根与导航

`AppRoot` 只做依赖构造、全局信号接线和 feature 生命周期管理。`ScreenRegistry` 负责注册/创建 screen；`ChromeController` 管理顶栏、底栏、toast 与全局遮罩。业务查询、提交和 DTO 组装不得回流到这三个对象。

`AppRoot` 是唯一应用组合根，构造 feature API/store/coordinator/screen，连接稳定的意图与状态信号，并持有 account-scoped transport 图。注销或换号时先推进 session epoch 和阻断旧提交，再取消旧请求；节点图延迟到当前 signal/coroutine 栈退出后销毁和重建，避免释放正在执行的按钮、screen 或 coordinator。

## 5. 状态所有权

- 跨 feature 只共享认证会话、locale、theme、全局未读等真正全局状态。
- 列表、详情、草稿、订单等数据归各自 feature store。
- 跨 feature 传稳定 ID 或不可变快照，不共享具体 screen 节点和可变 Dictionary 引用。
- Coordinator 负责重复提交抑制和取消/过期响应处理；不得用任意 timeout 修复竞态。

## 6. 公共 UI

公共 UI 分三层：

| 层 | 内容 | 禁止内容 |
|---|---|---|
| theme | color/type/spacing/radius token、Theme | 业务状态 |
| components | Button、Card、Input、VirtualList | game/order/user 语义 |
| patterns | AsyncContent、EmptyState、PagedList、ConfirmSheet | endpoint 与用例 |

组件只有在至少两个 feature 中真实复用后提取。页面专用控件先留在 feature 内，避免预先抽象。

## 7. Runtime 边界

Shell 与 Runtime 只通过 `runtime/game_session.gd` 通信。Shell 传 runtime ref 与完整有效 DSL；Runtime 发 `game_ended`/`game_error`。双方禁止读取对方内部节点、状态或文件。

`GameSession` 有两种用法。`start_game` 加载后立即回传摘要，用于校验与预览。`start_run` 是真实的一局：运行时保持挂载并持续模拟，直到通关、失败、超时，或宿主调用 `end_run`；期间宿主用 `set_paused` 暂停、`snapshot` 读取 HUD 所需的状态、`perform` 发送少量命令（移动、加速、护盾、放塔），并监听 `game_started` / `score_changed` / `paused_changed` / `game_ended`。结束时的结果包含 `play_seconds`（不含暂停）、`timed_out`、`aborted`。运行时以自身原点为中心绘制 `STAGE_SIZE`（960×540）的舞台，宿主把 `GameSession` 放进同尺寸的 `SubViewport` 再整体缩放。`baseline_payload(runtime_ref)` 返回某个运行时内置基线的启动参数，宿主因此不必自己读运行时目录里的文件。

Runtime 目录同时是仓库里其他部分的数据来源：`runtime/<name>/baseline.dsl.json` 是后端注册的基线，`runtime/shooter/testdata/fork_expected.dsl.json` 是客户端 `runtime/json_patch.gd` 与 Go 模块 `packages/dsl` 共用的 golden。两份补丁实现、两份迁移实现（`runtime/dsl_migrations.gd` 与 `packages/dsl/migrate.go`）必须同语义，改其中一侧时另一侧、两边的测试和共用的夹具要在同一个 PR 里一起改。对应的 schema 在 `packages/schemas`。

## 8. 主机风格启动器（launcher）

客户端的主场景是 `apps/client/launcher/launcher.tscn`：一个固定 1920×1080 画布（`canvas_items` 拉伸、`aspect=keep`）的主机风格启动器，键盘、手柄、鼠标都能完整操作。上面第 1 至 6 节描述的移动端应用壳（`app/`、`features/`、`shell/`、`ui/`）仍在仓库里并继续跑各自的测试，等启动器的全部屏幕就绪后整体移除。

```text
apps/client/launcher/
├── launcher.tscn / launcher_root.gd  # 外壳与组合根：背景层、游戏舞台、屏幕注册与切换、顶部导航、toast、输入分发
├── launcher_screen.gd                # 屏幕基类：生命周期、handle_action、页脚按键提示
├── launcher_tokens.gd                # 设计 token（颜色、字号、间距、动效时长、系统字体）
├── launcher_widgets.gd               # 文本、容器、分隔线等小工厂
├── launcher_controls.gd              # 可交互控件：FocusRow、Tab、Glyph、GlyphHint、ArtCard、Tile
├── launcher_input.gd                 # 输入动作名、事件到动作的翻译、按键覆盖
├── launcher_store.gd                 # 唯一本地存档 user://launcher.json
├── launcher_catalog.gd               # 数据驱动的游戏目录与成就定义
├── launcher_key_art.gd               # 每款游戏的主视觉（程序化占位，可被图片替换）
├── launcher_game_host.gd             # 经 GameSession 运行游戏并把结果写入存档
├── launcher_format.gd                # 分数、时长、「今天/昨天」等显示格式
├── home_screen.gd / game_screen.gd / unavailable_screen.gd
└── launcher_test.gd / launch_test.gd / launcher_shot.gd
```

依赖方向：

```text
launcher → i18n
        └→ runtime/game_session.gd（仅此一个文件）
```

- 启动器完全本地：不登录、不发网络请求，不依赖移动端应用壳的任何目录；运行时与移动端应用壳也不得反向依赖启动器。`scripts/check-client-boundaries.sh` 检查这几条。
- 屏幕不读 `InputEvent`。`LauncherRoot` 把每次按键、手柄按下和页脚提示的点击翻译成 `LauncherInput` 的动作名，交给当前屏幕的 `handle_action`；屏幕不处理的动作回落到外壳（LB/RB、LT/RT 切换顶层标签，B 返回）。
- 焦点由屏幕自己持有（分区名 + 序号），控件只负责外观并发出 `hovered` / `activated`，不使用 Godot 自带的键盘焦点。
- 屏幕上关于玩家的一切（游玩时长、上次游玩、最高分、收藏、最近游玩、成就）都读自 `LauncherStore`，只有真实游玩和真实操作会写入；没有记录时如实显示空状态。
- 游戏只经 `LauncherGameHost` 启动。它是外壳的一层而不是屏幕，游戏屏与暂停屏在它上面切换时舞台保持挂载。

## 9. 完成态不变量

- Godot 4.6.3 精确版本门禁和 fail-closed test runner；
- transport-only `HttpClient` 与统一 `ApiResult`；
- 七域 API/store/coordinator/screen 所有权；
- `AppRoot`、`ScreenRegistry`、`ChromeController` 单一装配与导航路径；
- account session epoch、旧请求取消、全域 cache 清理和延迟依赖图重建；
- AsyncContent、EmptyState、PagedList、ConfirmSheet 等无业务共享 pattern；
- 仓库级 fixture checker 拒绝旧入口、endpoint/transport 越界和跨 feature screen import。
