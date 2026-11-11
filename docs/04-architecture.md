# 技术架构

更新时间：2026-11-10
状态：模块化架构已完成并由自动门禁守护

> 说明：本文第 2 节描述的在线服务（账号、目录、创作与 Mod、社区、互动、商业化、运营等 API）已实现并有测试，属于可选组件；当前的主机风格启动器完全在本地运行，没有接入它。产品定位见 [01-vision](./01-vision.md)，决策见 [ADR-016](./decisions.md)。

## 1. 全局视图

```text
Godot 4.6.3 client
  launcher（主机风格启动器，完全本地）
    └── LauncherGameHost → GameSession ── runtime

Go 1.26 modular monolith（可选的在线服务，启动器不访问）
  cmd/server → internal/app → domain modules/adapters
                      │
                GORM + SQLite(dev)/PostgreSQL(prod)
```

Classic Games 保留一个 Godot 客户端和一个 Go 模块化单体，两者之间没有网络调用。当前不拆微服务：跨域事务、部署规模和团队规模都不支持由网络边界带来的额外复杂度。业务边界通过目录、接口、装配和自动检查落实。

### 1.1 仓库布局

仓库是一个 monorepo，顶层按「程序」与「共享契约/库」分成两类目录（决策见 [ADR-015](./decisions.md)）：

```text
apps/
  client   Godot 4.6.3 客户端与游戏 Runtime
  server   Go 后端，模块 github.com/yldm-tech/classic-games/apps/server
  cli      命令行工具 classic-games，模块 github.com/yldm-tech/classic-games/apps/cli
  mcp      MCP 服务 classic-games-mcp，模块 github.com/yldm-tech/classic-games/apps/mcp
  web      官网与文档站（Astro + Starlight）
packages/
  schemas  Mod DSL 的 JSON Schema，三方契约
  dsl      Go 模块 github.com/yldm-tech/classic-games/packages/dsl：RFC 6902 补丁、DSL 迁移、schema 校验
  sdk      Go 模块 github.com/yldm-tech/classic-games/packages/sdk：后端 HTTP API 的类型化客户端
```

依赖只有一个方向：`apps → packages`。

```text
apps/server ──────────────→ packages/dsl ──读取──→ packages/schemas
apps/cli ──→ packages/sdk ──HTTP──→ apps/server
         └─→ packages/dsl
apps/mcp ──→ packages/sdk ──HTTP──→ apps/server
         └─→ packages/dsl
apps/client                              （不访问 apps/server；GDScript 侧另有一份与 packages/dsl 同语义的补丁实现）
apps/web ──构建期读取──→ docs/、packages/schemas、apps/client/runtime 的 baseline
```

- 后端是应用，不是库：CLI 与 MCP 服务只经 `github.com/yldm-tech/classic-games/packages/sdk` 走公开的 HTTP 契约访问它，不 import `github.com/yldm-tech/classic-games/apps/server`。
- 补丁、迁移与校验在 Go 侧只有 `packages/dsl` 一份实现，后端、CLI、MCP 共用；它与客户端的 `runtime/json_patch.gd`、`runtime/dsl_migrations.gd` 由同一份 baseline + golden 钉成同语义。
- 五个 Go 模块由根目录 `go.work` 组成 workspace，同时各自带相对路径 `replace`，在 `GOWORK=off` 下也能独立构建。

## 2. 服务端

### 2.1 进程与应用边界

- `apps/server/cmd/server/main.go` 只加载强类型配置、建立 signal context、构造 `app.App`、运行和关闭进程。
- `apps/server/internal/app` 是唯一 composition root，拥有 HTTP engine、数据库连接、provider 选择、模块装配和生命周期。
- `app.Config` 集中解析环境变量并做跨字段校验；敏感值不会出现在格式化输出中。
- `app.Run` 使用 `http.Server` 和有界 graceful shutdown，不由业务模块直接启动进程或调用 `log.Fatal`。

### 2.2 数据库与迁移

所有生产 schema 变更统一由 `apps/server/internal/app/migrations.go` 的有序 registry 执行。仓储构造器只构造仓储，不允许调用 `AutoMigrate`。该约束由 `internal/app` 架构测试持续检查。

当前开发环境使用 `github.com/ncruces/go-sqlite3/gormlite`，避免 CGO 与已停止维护的 SQLite driver；生产数据库仍以 PostgreSQL 为目标。

### 2.3 业务模块

业务边界是：

| 边界 | 主要能力 |
|---|---|
| `identity` | 登录、会话、账号安全、用户身份 |
| `catalog` | 发现、搜索、详情、榜单、公开资料 |
| `creation` | runtime、DSL、AI、mod、draft、发布 |
| `community` | 评论、圈子、关注、聊天 |
| `engagement` | 游戏记录、下载、直播、房间、回放 |
| `commerce` | 积分、会员、福利、活动、支付、收益 |
| `operations` | 审核、举报、屏蔽、偏好、反馈、分析 |

`internal/app/module.go` 按固定、无环依赖顺序调用七个领域 installer；每个 installer 只构造本域仓储并注册本域完整路由集。后续模块只能消费 exported callable 或最小接口，不能取得相邻域的仓储、GORM model 或完整 service。安装前后的 route delta、装配文件大小和具体 service 泄漏均有架构测试。

### 2.4 请求方向

```text
HTTP adapter → application service → domain rule → repository/remote port
```

Gin/GORM/第三方 SDK 只属于 adapter 或 app 装配层。跨模块调用经显式端口；写操作由用例所有者编排，不允许仓储互调。

## 3. 客户端

客户端是主机风格的启动器，主场景是 `apps/client/launcher/launcher.tscn`：固定 1920×1080 画布，键盘、手柄、鼠标都能操作，另有 PC 模式。

```text
输入事件 → LauncherRoot（翻译成动作名）→ 当前屏幕 handle_action
LauncherStore（user://launcher.json）──→ 屏幕渲染
LauncherGameHost → GameSession → runtime
```

- `apps/client/launcher/launcher_root.gd` 是启动器的外壳与组合根，负责屏幕注册与切换、顶部导航、toast 和输入分发。
- 启动器完全本地：不登录、不发网络请求，全部进度保存在唯一的本地存档 `user://launcher.json`（`launcher_store.gd`）。
- 游戏目录在启动时从 `apps/client/games/<id>/game.json` 发现：每款游戏是一个自足的目录，加一款游戏不改共享文件（[20-adding-a-game](./20-adding-a-game.md)）。随附三款游戏，分别运行 `shooter`、`survivor`、`tower_defense` 三个运行时的基线 DSL；不经 DSL 的游戏是继承 `GameModule` 的游戏模块，同样经 `GameSession` 运行。
- 游戏只经 `launcher_game_host.gd` 启动，它是启动器里唯一使用运行时的地方。

屏幕、设置、游戏流程与 PC 模式的细节见 [16-client-architecture](./16-client-architecture.md)。

## 4. 启动器与 Runtime

启动器与 Runtime 只经 `apps/client/runtime/game_session.gd` 交换数据：

```gdscript
session.start_run(GameSession.baseline_payload("shooter@1.0.0"))
signal game_ended(result)
signal game_error(error)
```

Runtime 不读启动器的状态或 UI 节点；启动器不访问游戏 scene 内部。DSL 和结果是唯一业务载荷。这条边界让宿主界面可以整体替换而不改动游戏运行时。

## 5. 公共能力

启动器内部的公共代码不携带单个屏幕的语义：

- `launcher_tokens.gd`：设计 token（颜色、字号、间距、动效时长）。
- `launcher_widgets.gd`、`launcher_controls.gd`：文本、容器等小工厂与可交互控件。
- `launcher_input.gd`：输入动作名、事件到动作的翻译、按键覆盖。
- `apps/client/i18n`：文案表，是启动器在 `launcher/` 与 `runtime/game_session.gd` 之外唯一依赖的目录。

## 6. 架构门禁

权威本地门禁：

```bash
make ci GODOT=/Applications/Godot.app/Contents/MacOS/Godot
make ci-web
git diff --check
```

`make ci` 覆盖五个 Go 模块的 gofmt、`go mod tidy`、vet/test（workspace 与 `GOWORK=off` 各一遍）、CLI 与 MCP 的编译、七模块装配与完整路由归属、Godot 版本锁定、测试 runner fail-closed、客户端依赖边界、runtime spike，以及启动器的无头测试（存档与首页、设置、游戏库与成就、主场景启动、PC 模式、游戏流程）；`make ci-web` 是官网的类型检查、构建与断链检查。`scripts/check-architecture.sh` 额外拒绝分散 migration、业务进程生命周期和陈旧架构状态文档，并守住仓库级模块边界：CLI/MCP 不得依赖后端模块，`packages/*` 不得依赖应用模块，后端不得保留私有的 DSL 实现，内部文档目录不得入库。
