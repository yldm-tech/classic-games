# 技术架构

更新时间：2026-11-10
状态：模块化架构已完成并由自动门禁守护

## 1. 全局视图

```text
Godot 4.6.3 client
  app composition root
    ├── feature slices: screen → coordinator → store → typed API
    ├── shared core/ui/platform
    └── GameSession ── runtime
                    HTTPS
                      │
Go 1.26 modular monolith
  cmd/server → internal/app → domain modules/adapters
                      │
                GORM + SQLite(dev)/PostgreSQL(prod)
```

Classic Games 保留一个 Godot 客户端和一个 Go 模块化单体。当前不拆微服务：跨域事务、部署规模和团队规模都不支持由网络边界带来的额外复杂度。业务边界通过目录、接口、装配和自动检查落实。

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
apps/client ──HTTP──→ apps/server        （GDScript 侧另有一份同语义的补丁实现）
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

客户端采用单向 feature slice：

```text
Screen intent → Coordinator → Feature API / GameSession / Platform port
                                ↓
                           ApiResult
                                ↓
Store state ─────────────────→ Screen render
```

- `apps/client/app/app_root.gd` 是应用装配根。
- `ScreenRegistry` 负责 screen 创建与查找，`ChromeController` 负责顶栏、底栏和 toast 等全局 chrome。
- `apps/client/core/http/http_client.gd` 只处理 transport、认证 header、JSON 与错误信封。
- URL 只能属于对应 feature 的 typed API gateway。
- screen 不直接使用 `HTTPRequest`/`HttpClient`，store 不发网络请求，coordinator 不操作具体 UI 节点。
- feature 之间不 import 对方 screen；跨 feature 跳转通过 app router/registry 和稳定 payload。

七个业务域均位于 `apps/client/features/<domain>`，遵循相同的 API/store/coordinator/screen 所有权。应用只有 `AppRoot` 一个组合根；账号切换会推进 session epoch、取消旧 transport、清空所有 account-scoped store/screen，并在当前回调栈退出后重建依赖图，防止跨账号迟到响应和节点生命周期竞态。

## 4. Shell 与 Runtime

Shell 与 Runtime 继续被视为两个进程，只经 `apps/client/runtime/game_session.gd` 交换数据：

```gdscript
GameSession.start_game({"runtime": "shooter@1.0.0", "mod": effective_dsl})
signal game_ended(result)
signal game_error(error)
```

Runtime 不读 Shell 状态或 UI 节点；Shell 不访问游戏 scene 内部。DSL 和结果是唯一业务载荷。该边界是未来替换某端 Shell 而保留游戏运行时的逃生口。

## 5. 公共能力

公共代码只有在至少两个业务域使用且不携带业务语义时才进入共享层：

- `core/http`：transport 和统一 `ApiResult`。
- `ui/theme`：设计 token 与 Theme。
- `ui/components`：无业务 Button、Card、Input、VirtualList。
- `ui/patterns`：AsyncContent、EmptyState、PagedList、ConfirmSheet。
- `platform`：支付、分享、推送、文件选择等平台端口。

游戏、订单、用户、创作等语义组件保留在 feature 内，避免形成新的“公共杂物间”。

## 6. 架构门禁

权威本地门禁：

```bash
make ci GODOT=/Applications/Godot.app/Contents/MacOS/Godot
GODOT=/Applications/Godot.app/Contents/MacOS/Godot scripts/spike-integration.sh
make ci-web
git diff --check
```

`make ci` 覆盖五个 Go 模块的 gofmt、`go mod tidy`、vet/test（workspace 与 `GOWORK=off` 各一遍）、CLI 与 MCP 的编译、七模块装配与完整路由归属、Godot 版本锁定、测试 runner fail-closed、客户端依赖边界、全部 feature/app 契约、runtime spike、UI 和启动；`scripts/spike-integration.sh` 是真实 server-client 集成；`make ci-web` 是官网的类型检查、构建与断链检查。`scripts/check-architecture.sh` 额外拒绝旧客户端入口、页面/状态/协调器中的 endpoint、越界 transport、跨 feature screen import、分散 migration、业务进程生命周期和陈旧架构状态文档，并守住仓库级模块边界：CLI/MCP 不得依赖后端模块，`packages/*` 不得依赖应用模块，后端不得保留私有的 DSL 实现，内部文档目录不得入库。
