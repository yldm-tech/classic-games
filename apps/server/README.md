# ForgePlay server

Go backend for ForgePlay，使用 **gin** + **GORM**。数据库目前只支持 SQLite（基于 wasm2go 的无 CGO 驱动 `gormlite`），`FORGEPLAY_DB` 是 SQLite 文件路径；PostgreSQL 是生产目标，驱动尚未接入。架构决策见 [`../../docs/decisions.md`](../../docs/decisions.md) ADR-011。

## Layout

```
apps/server/
├── cmd/server/         # main.go：仅管理进程生命周期
├── internal/app/       # 配置、migration registry、七域 installer、HTTP engine
├── internal/<domain>/  # 细粒度领域服务、HTTP adapter、repository adapter
├── pkg/                # 错误信封、分页游标、来源标记等无业务基础设施
└── docs/               # 生成的 OpenAPI 描述
```

补丁（RFC 6902）、DSL 迁移和 schema 校验不在本模块内，而在共享模块 [`../../packages/dsl`](../../packages/dsl)（`forgeplay/dsl`），`go.mod` 以相对路径 `replace` 引用它；CLI 与 MCP 服务用的是同一份实现。schema 文件在 [`../../packages/schemas`](../../packages/schemas)，Runtime 基线在 [`../client/runtime`](../client/runtime)。

`cmd/server/main.go` 只调用 `app.New`。`internal/app` 按 identity、creation、catalog、commerce、community、engagement、operations 的固定无环顺序装配领域；installer 之间只传具名 callable 或最小接口。生产 schema 由 `internal/app/migrations.go` 的有序 registry 在启动时统一迁移。

## Run and verify

在本目录下：

```bash
go run ./cmd/server
go test ./...
go vet ./...
```

或在仓库根目录用 `make dev`、`make test`、`make vet`、`make build`（产物 `apps/server/bin/server`）。本模块属于根目录 `go.work` 的 workspace，加 `GOWORK=off` 也能独立构建。

默认监听 `:8080`，可通过 `PORT` 修改。内容路径的默认值相对本目录：`FORGEPLAY_SCHEMA_DIR=../../packages/schemas`、`FORGEPLAY_RUNTIME_DIR=../client/runtime`，所以要从 `apps/server` 启动，或显式设置这些变量；全部变量见 [`../../.env.example`](../../.env.example)。设置 `ANTHROPIC_API_KEY` 后启用 Claude；未设置时使用确定性本地 provider，便于离线开发。Swagger UI 位于 `/swagger/index.html`。改了接口注解后在本目录重新生成 `docs/`：`go run github.com/swaggo/swag/cmd/swag@v1.16.6 init -g cmd/server/main.go -o docs --parseDependency --parseInternal`。

`FORGEPLAY_ENV=development`（默认）下，启动时会补齐 9 个展示作品，让 `/games` 与 `/ranking` 在本地有数据可返回。展示作品背后没有 mod：`mod_id` 与 `runtime` 为空，`/games/:id/dsl`、`/lineage`、`/fork-tree`、`/fork` 对它们返回 `404 GAME_HAS_NO_MOD`，客户端也不为它们显示「改一版」。它们的游玩、Fork、点赞数是虚构的，所以 `FORGEPLAY_ENV=production` 不预置任何作品，新数据库的作品列表为空。

部署在反向代理后时，将实际 Nginx/Ingress/CDN 的 IP 或 CIDR 以逗号分隔写入 `FORGEPLAY_TRUSTED_PROXIES`。默认不信任任何代理；不要使用 `0.0.0.0/0`，否则客户端可伪造来源 IP 绕过登录与 AI 配额限制。

## Key references

- HTTP contract: [`../../docs/09-api-design.md`](../../docs/09-api-design.md)
- Data model: [`../../docs/10-data-model.md`](../../docs/10-data-model.md)
- Architecture & module table: [`../../docs/04-architecture.md`](../../docs/04-architecture.md)
- Deployment: [`../../docs/08-deployment.md`](../../docs/08-deployment.md)

AI calls run here (not on the client): the backend owns API keys, rate limits, quotas, audit, and cost accounting, and validates every AI-produced DSL against its JSON Schema before returning it.
