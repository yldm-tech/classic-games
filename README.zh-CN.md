# ForgePlay

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

[English](./README.md) | 简体中文

AI 驱动的小游戏创作与社区平台。用户无需编程，通过自然语言对现有游戏做修改、扩展、再创作，并发布到社区供他人体验和 Fork。形态上是 GitHub + Roblox + NexusMods 的混合体。

核心范式不是「从零创建游戏」，而是「Fork 游戏 → AI 改 → 发布」——AI 擅长增量修改，不擅长从零创造。核心赌注是 **Mod DSL**：AI 只生成和修改 DSL，**绝不生成可执行代码**，输出空间被 DSL 的 JSON Schema 死死框住。

项目尚未发布：没有公开的二进制、软件包或应用商店版本，下面的一切都从源码开始。

## 工作方式

1. **Fork。** 一个游戏是 Runtime 基线之上的一条补丁链。Fork 一个游戏会生成一个以该游戏的 mod 为父节点的草稿 mod，所以 Fork 存的是补丁，不是游戏的副本。
2. **AI 改。** 客户端把当前生效 DSL 和用户的一句话发给后端。后端让模型产出 JSON Patch，应用补丁，按 schema 校验结果，校验失败就把错误回灌给模型重试（次数有上限）。模型的输出空间就是 schema，不存在从模型输出通向代码执行的路径。
3. **发布。** 草稿提交为游戏，经过审核后公开，其他人可以继续 Fork。

同样的三步既可以在 Godot 客户端里完成，也可以用命令行 `forgeplay` 完成，AI 助手则通过 `forgeplay-mcp` 完成。

## 仓库结构

```
forgeplay/
├── apps/
│   ├── client/      单一 Godot 4.6 工程，一套代码导出 5 端（iOS / Android / macOS / Windows / Web）
│   ├── server/      Go 后端（gin + GORM），模块 forgeplay/server：领域服务、HTTP API、AI 编排
│   ├── cli/         命令行工具 forgeplay（cobra），模块 forgeplay/cli：目录、mod、AI 生成，离线校验 / 补丁 / 迁移
│   ├── mcp/         MCP 服务 forgeplay-mcp（官方 Go SDK），模块 forgeplay/mcp：把同样的能力作为工具交给 AI 助手
│   └── web/         官网：落地页 + 文档站（Astro + Starlight，pnpm）
├── packages/
│   ├── schemas/     Mod DSL 的 JSON Schema（AI 输出约束、后端校验、Runtime 加载共用）
│   ├── dsl/         Go 模块 forgeplay/dsl：RFC 6902 补丁、DSL 迁移、schema 校验，后端 / CLI / MCP 共用
│   └── sdk/         Go 模块 forgeplay/sdk：后端 HTTP API 的类型化客户端，CLI / MCP 共用
├── docs/            技术文档（愿景 / 架构 / DSL / API / 测试 / 合规），中文
├── scripts/         仓库门禁与辅助脚本（架构边界检查、Godot 测试 runner、双端集成）
├── go.work          Go workspace，串起上面五个 Go 模块
└── .github/         CI：Go 各模块、官网、Godot headless，跑在 GitHub 托管 runner
```

依赖只有一个方向：`apps` 依赖 `packages`。五个 Go 模块由 [`go.work`](./go.work) 组成 workspace，同时彼此用 `require forgeplay/<name> v0.0.0` 加相对路径 `replace` 引用，所以每个模块在 `GOWORK=off` 下也能独立构建。这些模块路径只在本仓库内有效，没有发布到模块代理。

单仓（monorepo）的理由见 [decisions ADR-012](./docs/decisions.md)，`apps/` + `packages/` 布局、共享模块与许可证的决策见 [ADR-015](./docs/decisions.md)。

### apps/client/

单一 Godot 工程，以应用装配根、纵向 feature 和 Runtime 边界组织（详见 [16-client-architecture](./docs/16-client-architecture.md)）：

- `app/`、`core/`、`features/` — composition root、公共 transport 与七个按用户旅程组织的业务切片
- `ui/`、`shell/` — 无业务公共 UI，以及保留的设计 token、路由、全局会话/创作会话工具；不含应用根、业务 screen 或全局 API
- `runtime/` — 游戏运行时；`game_session.gd` 是 Shell↔Runtime 的**唯一**通信边界
- `platform/` — 各端原生能力插件（GDExtension）
- `i18n/`、`assets/` — 多语言与本地兜底资源

**纪律**：Shell 与 Runtime 只经 `runtime/game_session.gd` 通信，谁都不许伸手进对方内部（[ADR-003](./docs/decisions.md)）。守住这条边界，「将来某端换原生壳、游戏侧原样拆出」的逃生口才有效。

运行时关键件：

- `runtime/runtime_loader.gd` — 读 DSL → 校验 runtime 版本（同 major 兼容）→ 把枚举/数值套到游戏对象
- `runtime/json_patch.gd` — 最小 RFC 6902 实现，服务 Fork 补丁链

### apps/server/

Go 后端，栈选型 [ADR-011](./docs/decisions.md)。框架无关的核心层（不绑 gin，可单测）：

- `internal/ai/service.go` — `Service.GenerateMod`：调 provider → apply 6902 补丁 → 校验生效 DSL → 失败把错误回灌重试（有限次）→ 记录 `ai_calls`。provider 只保证补丁**格式**合法，**语义**合法由 apply + 校验保证，两者不捆绑。
- `internal/ai/provider.go` — `LLMProvider` / `Validator` / `Recorder` 接口。目前的实现只有 `ClaudeProvider` 和无 API key 时使用的确定性 `StubProvider`；接口为以后接入 GPT / Gemini / 本地模型预留，这些 provider 尚未实现（见 [ADR-008](./docs/decisions.md)）

`internal/app` 通过七个领域 installer 统一装配 HTTP API、GORM 仓储、AI provider、迁移、配额和 Swagger；跨领域连接只暴露具名窄端口，`cmd/server` 只管理进程生命周期。契约见 [09-api-design](./docs/09-api-design.md)，模块说明见 [apps/server/README](./apps/server/README.md)。

**AI 调用放后端，客户端不直连模型**（[ADR-007](./docs/decisions.md)）：统一管控 API key、限流、配额、审计、成本核算。

### packages/dsl/

补丁、迁移与 schema 校验不在 `apps/server` 内，而在共享 Go 模块 `packages/dsl`（`forgeplay/dsl`），后端、CLI、MCP 共用同一份实现（说明见 [packages/dsl/README](./packages/dsl/README.md)）：

- `patch.go` — RFC 6902 实现，与客户端 `json_patch.gd` **刻意同语义**
- `migrate.go` — 历史 DSL 大版本升级（shooter 0.x → 1.0.0）
- `schema_validator.go` — 权威校验器，按 runtime 版本加载对应 JSON Schema 文件做完整校验（draft 2020-12，编译结果按 ref 缓存）

### packages/sdk/

`forgeplay/sdk` 是后端 HTTP API 的类型化 Go 客户端，只依赖标准库。CLI 和 MCP 服务都经它访问后端，不 import `forgeplay/server`。方法列表见 [packages/sdk/README](./packages/sdk/README.md)。

### apps/cli/ 与 apps/mcp/

- `forgeplay`：联网命令（`auth` / `server` / `games` / `mods` / `ai`）走 `forgeplay/sdk`，离线命令（`dsl validate` / `dsl patch` / `dsl migrate`）走 `forgeplay/dsl`，与后端对同一份 DSL 得出同一个结论。命令说明见 [apps/cli/README](./apps/cli/README.md)。
- `forgeplay-mcp`：14 个工具（离线的 schema / 校验 / 补丁，后端的游戏与 mod 读写），stdio 与 streamable HTTP 两种传输，`--read-only` 时不注册写工具。保存补丁前先在本地应用并校验，不合 schema 的内容不会落库。工具列表、客户端配置与安全说明见 [apps/mcp/README](./apps/mcp/README.md)。

### apps/web/

官网与文档站。`docs/` 下的 Markdown 在构建时同步进站点，不在 `apps/web` 里另存副本；落地页上的补丁示例在构建期用仓库里的 baseline 与 golden 重放，结果不一致则构建失败。说明见 [apps/web/README](./apps/web/README.md)。

## Mod DSL 契约

DSL 是 AI 输出约束、后端校验、Runtime 加载三方共用的同一份契约。schema 在 [`packages/schemas`](./packages/schemas)，Shooter 第一版权威 schema：[`shooter-1.0.0.schema.json`](./packages/schemas/shooter-1.0.0.schema.json)。目前有三个 Runtime：`shooter`、`survivor`、`tower_defense`。

两个关键结构决策（[ADR-013](./docs/decisions.md)）：

- 补丁语义定为 **RFC 6902（JSON Patch）**，不用 Merge Patch——后者对数组只能整体替换，表达不了「删某个敌人」，会让 Fork 补丁链失效。
- `enemies` / `drops` 设计成**以稳定 id 为 key 的 map**（非匿名数组），让 6902 路径 `/enemies/<id>/...` 在深 Fork 链里稳定不错位，AI 也能按 id 精确引用。

客户端（GDScript，[`apps/client/runtime/json_patch.gd`](./apps/client/runtime/json_patch.gd)）与 Go 侧（[`packages/dsl`](./packages/dsl)）各有一份 6902 实现，**同一条补丁链两端 apply 必须得到相同生效 DSL**，否则「客户端预览」与「服务端入库/校验」会分叉。这条一致性由两端测试共用同一份 baseline + golden 输出（[`fork_expected.dsl.json`](./apps/client/runtime/shooter/testdata/fork_expected.dsl.json)）钉死。支持的操作是 `add`、`replace`、`remove`、`test`；`move` 与 `copy` 在所有实现里都被拒绝。

## 快速开始

需要 Go 1.26（较旧的 Go 会按需下载工具链）、GNU Make，客户端需要精确的 Godot 4.6.3（版本锁在 [`apps/client/.godot-version`](./apps/client/.godot-version)）。官网另需 Node.js 22.23.4 以上与 pnpm 12。

```bash
git clone https://github.com/yldm-tech/classic-games.git
cd classic-games
make help                             # 列出全部目标
```

后端：

```bash
make dev                              # 监听 :8080，改端口用 PORT=9090 make dev
curl http://localhost:8080/healthz    # {"ok":true}
```

不设任何环境变量时，后端以开发模式运行，数据库是一个 SQLite 文件，模型由确定性的 stub 代替，所以不需要 API key 就能走通「一句话 → 补丁 → 校验」整条链路。设置 `ANTHROPIC_API_KEY` 后调用真实模型。全部环境变量见 [`.env.example`](./.env.example)，接口文档在 `http://localhost:8080/swagger/index.html`。

客户端：

```bash
make import GODOT=/path/to/godot      # 首次导入资源
FORGEPLAY_API=http://127.0.0.1:8080 /path/to/godot --path apps/client
```

CLI：

```bash
make cli-build                        # 产物在 apps/cli/bin/forgeplay
export PATH="$PWD/apps/cli/bin:$PATH"

forgeplay dsl validate apps/client/runtime/shooter/baseline.dsl.json   # 离线
forgeplay server health
forgeplay auth login                  # 游客会话
forgeplay ai generate "turn the player into a cat" --runtime shooter@1.0.0 --save
forgeplay mods list
```

MCP 服务：

```bash
make mcp-build                        # 产物在 apps/mcp/bin/forgeplay-mcp
export FORGEPLAY_TOKEN="$(forgeplay auth token)"    # 可选；不设则匿名运行
claude mcp add forgeplay --env FORGEPLAY_SERVER_URL=http://localhost:8080 --env FORGEPLAY_TOKEN="$FORGEPLAY_TOKEN" -- "$PWD/apps/mcp/bin/forgeplay-mcp"
```

官网：

```bash
pnpm install
pnpm web:dev                          # http://localhost:4321
```

## 本地开发与验证

所有门禁都是仓库根目录的 `make` 目标。

```bash
make ci GODOT=/path/to/godot          # Go 与 Godot 的全部门禁（需精确安装 Godot 4.6.3）
make ci-web                           # 官网：安装、类型检查、构建与断链检查
make ci-all GODOT=/path/to/godot      # 两者都跑
GODOT=/path/to/godot scripts/spike-integration.sh    # 真实客户端对真实后端，占用 8099 端口
```

`make ci` 覆盖五个 Go 模块的 `gofmt`、`go mod tidy`、`go vet`、`go test`（workspace 与 `GOWORK=off` 各一遍）、CLI 与 MCP 的编译、架构检查（[`scripts/check-architecture.sh`](./scripts/check-architecture.sh)、[`scripts/check-client-boundaries.sh`](./scripts/check-client-boundaries.sh)）和 Godot headless 测试。只改某一块时可以跑更窄的目标，例如 `make test`（后端）、`make dsl-test`、`make sdk-test`、`make cli-test`、`make mcp-test`、`make spike`；按领域的完整列表见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## CI

[`.github/workflows/ci.yml`](./.github/workflows/ci.yml)，push / PR 到 main 触发，跑在 GitHub 托管 runner（`ubuntu-latest`）上，来自 fork 的 PR 同样执行：

- `server (go)` — 后端 `go vet` + `go test ./...`
- `go modules (dsl, sdk, cli, mcp)` — 格式与 tidy 检查，全部模块的 vet / test（workspace 与 `GOWORK=off`），CLI 与 MCP 编译
- `web (astro)` — `pnpm install --frozen-lockfile`、类型检查、构建与断链检查
- `client spike (godot headless)` — 精确版本检查、边界检查、HTTP/feature/app/spike/UI/launch 门禁

托管 runner 每个 job 用一台全新的虚拟机，跑完即弃，所以可以安全地构建来自 fork 的 PR；不要把这些 job 挪到常驻的 self-hosted runner 上。

## 文档

从 [`docs/README.md`](./docs/README.md) 进，有完整索引和阅读顺序。关键决策汇总见 [decisions（ADR Log）](./docs/decisions.md)；概念不清查 [术语表](./docs/glossary.md)。官网（`apps/web`）发布同一套文档，另有 CLI、MCP 服务与 Go SDK 的开发者指南。

## 当前状态

模块化架构重构已完成：客户端由单一 `AppRoot` 装配 identity、catalog、creation、community、engagement、commerce、operations 七个纵向切片；服务端由对应七个 installer 组成模块化单体。旧的全局壳与全局 API 入口已删除，架构边界由 `scripts/check-architecture.sh`、客户端 boundary checker、Go/Godot 测试和真实双端集成共同守护。

仓库已整理为 `apps/` + `packages/` 的 monorepo：补丁、迁移与 schema 校验抽成共享模块 `forgeplay/dsl`，后端 API 客户端抽成 `forgeplay/sdk`，在其上新增了 CLI、MCP 服务和官网。

## 参与贡献

欢迎贡献。工具、提交前要过的检查和评审时坚持的架构规则见 [CONTRIBUTING.md](./CONTRIBUTING.md)（英文，含中文指引）。参与者须遵守 [行为准则](./CODE_OF_CONDUCT.md)。变更记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 安全

疑似漏洞请按 [SECURITY.md](./SECURITY.md) 私下报告，不要开公开 issue。

## 许可证

ForgePlay 以 [Apache License 2.0](./LICENSE) 发布。第三方归属见 [NOTICE](./NOTICE) 与 [docs/legal/licenses.md](./docs/legal/licenses.md)。
