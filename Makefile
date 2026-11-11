# Classic Games monorepo — build/test orchestration.
# apps/server/ = Go backend, apps/client/ = Godot 4.6 project, apps/cli/ = classic-games CLI, apps/mcp/ = classic-games-mcp server, apps/web/ = website (pnpm).
# packages/dsl/ and packages/sdk/ = Go modules shared by the apps.
# Targets mirror .github/workflows/ci.yml so `make ci` reproduces the Go and Godot gates locally; `make ci-web` reproduces the website gate and `make ci-all` runs both.
#
# Override tool paths if they are not on PATH, e.g.:
#   make spike GODOT=/Applications/Godot.app/Contents/MacOS/Godot

GO         ?= go
GOFMT      ?= gofmt
GODOT      ?= godot
PNPM       ?= pnpm
SERVER_DIR := apps/server
CLIENT_DIR := apps/client
CLI_DIR    := apps/cli
MCP_DIR    := apps/mcp
WEB_DIR    := apps/web
DSL_DIR    := packages/dsl
SDK_DIR    := packages/sdk
# Every Go module of the workspace (go.work), libraries first.
GO_MODULES := $(DSL_DIR) $(SDK_DIR) $(SERVER_DIR) $(CLI_DIR) $(MCP_DIR)
GO_MOD_FILES := $(foreach module,$(GO_MODULES),$(module)/go.mod $(module)/go.sum)

# Version information linked into the classic-games CLI. Recursive variables, so git and date only run for the targets that use them.
VERSION    ?= dev
COMMIT      = $(shell git rev-parse --short HEAD 2>/dev/null || echo none)
BUILD_DATE  = $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

.DEFAULT_GOAL := help

.PHONY: help
help: ## 列出所有可用目标
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# ---- server (Go) ----

.PHONY: dev
dev: ## 启动后端 HTTP 服务(go run cmd/server,默认 :8080,改端口用 PORT=xxxx)
	cd $(SERVER_DIR) && $(GO) run ./cmd/server

.PHONY: build
build: ## 编译后端为 apps/server/bin/server
	cd $(SERVER_DIR) && $(GO) build -o bin/server ./cmd/server

.PHONY: test
test: ## go test 后端(同 CI)
	cd $(SERVER_DIR) && $(GO) test ./... -count=1

# ---- shared Go packages ----

.PHONY: dsl-test
dsl-test: ## go test packages/dsl(补丁 / 迁移 / schema 校验,含与客户端共用的 golden)
	cd $(DSL_DIR) && $(GO) test ./... -count=1

.PHONY: sdk-test
sdk-test: ## go test packages/sdk(后端 HTTP API 客户端)
	cd $(SDK_DIR) && $(GO) test ./... -count=1

# ---- cli (Go) ----

.PHONY: cli-build
cli-build: ## 编译 CLI 为 apps/cli/bin/classic-games(版本号用 VERSION=x.y.z 注入)
	cd $(CLI_DIR) && $(GO) build -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(BUILD_DATE)" -o bin/classic-games ./cmd/classic-games

.PHONY: cli-test
cli-test: ## go test CLI
	cd $(CLI_DIR) && $(GO) test ./... -count=1

# ---- mcp (Go) ----

.PHONY: mcp-build
mcp-build: ## 编译 MCP 服务为 apps/mcp/bin/classic-games-mcp
	cd $(MCP_DIR) && $(GO) build -o bin/classic-games-mcp ./cmd/classic-games-mcp

.PHONY: mcp-test
mcp-test: ## go test MCP 服务
	cd $(MCP_DIR) && $(GO) test ./... -count=1

# ---- all Go modules ----

.PHONY: vet
vet: ## go vet 全部 Go 模块(同 CI)
	@set -e; for module in $(GO_MODULES); do echo "go vet $$module"; (cd $$module && $(GO) vet ./...); done

.PHONY: go-test
go-test: test dsl-test sdk-test cli-test mcp-test ## go test 全部 Go 模块(workspace 模式)

.PHONY: go-standalone
go-standalone: ## 每个 Go 模块在 GOWORK=off 下 vet + test(验证 replace 指令可独立构建)
	@set -e; for module in $(GO_MODULES); do echo "GOWORK=off $$module"; (cd $$module && GOWORK=off $(GO) vet ./... && GOWORK=off $(GO) test ./... -count=1); done

.PHONY: build-all
build-all: build cli-build mcp-build ## 编译后端、CLI 与 MCP 服务

.PHONY: fmt
fmt: ## gofmt 格式化全部 Go 模块
	$(GOFMT) -w $(GO_MODULES)

.PHONY: fmt-check
fmt-check: ## 检查全部 Go 代码已 gofmt(有未格式化文件即失败)
	@unformatted="$$($(GOFMT) -l $(GO_MODULES))"; if [ -n "$$unformatted" ]; then echo "gofmt needed (run 'make fmt'):"; echo "$$unformatted"; exit 1; fi

.PHONY: tidy
tidy: ## 整理全部 Go 模块的 go.mod / go.sum
	@set -e; for module in $(GO_MODULES); do echo "go mod tidy $$module"; (cd $$module && GOWORK=off $(GO) mod tidy); done

# The second step exists because tidy regenerates a go.sum that was never added to git, and an untracked file is invisible to `git diff`.
.PHONY: tidy-check
tidy-check: tidy ## 检查 go.mod / go.sum 已整理且已纳入 git(tidy 后有 diff 或未跟踪文件即失败)
	git diff --exit-code -- $(GO_MOD_FILES)
	@untracked="$$(git ls-files --others --exclude-standard -- $(GO_MOD_FILES))" || exit 1; if [ -n "$$untracked" ]; then echo "go.mod / go.sum not tracked by git (git add them):"; echo "$$untracked"; exit 1; fi

# ---- web (Astro + Starlight, pnpm) ----

.PHONY: web-install
web-install: ## 按锁文件安装官网依赖(pnpm install --frozen-lockfile)
	$(PNPM) install --frozen-lockfile

.PHONY: web-check
web-check: ## 官网类型检查(astro check)
	$(PNPM) web:check

.PHONY: web-build
web-build: ## 构建官网静态站到 apps/web/dist(含文档同步与断链检查)
	$(PNPM) web:build

# ---- client (Godot) ----

.PHONY: import
import: ## Godot 导入资源、预热缓存(需本机装 Godot 4.6)
	$(GODOT) --headless --path $(CLIENT_DIR) --import

.PHONY: spike
spike: ## 跑运行时 headless 测试(DSL 补丁与迁移、三个运行时的加载与玩法规则、联机快照),退出码即门禁(同 CI)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://spike_test.gd '^=== spike 结果: [0-9]+ passed, 0 failed ===$$'

.PHONY: boundary-test
boundary-test: ## 验证客户端依赖方向(启动器只经 GameSession 进入运行时、启动器不联网)及检查器自身契约
	bash scripts/tests/check-client-boundaries_test.sh
	scripts/check-client-boundaries.sh

.PHONY: architecture-test
architecture-test: ## 验证仓库级架构:已移除的手机端不得回归、Go 模块边界、后端迁移与进程生命周期、公开文档
	bash scripts/tests/check-architecture_test.sh
	scripts/check-architecture.sh

.PHONY: launcher-test
launcher-test: ## 跑主机风格启动器测试(存档、目录、首页焦点、开局与结算)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/launcher_test.gd '^launcher_test: [0-9]+ passed, 0 failed$$'

.PHONY: settings-test
settings-test: ## 跑启动器设置屏测试(各类设置项、启动时应用、改键与冲突、存档导入导出、手柄连发)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/settings_test.gd '^settings_test: [0-9]+ passed, 0 failed$$'

.PHONY: library-test
library-test: ## 跑启动器游戏库与成就屏测试(网格焦点与滚动、分类、排序、搜索、收藏、成就)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/library_test.gd '^library_test: [0-9]+ passed, 0 failed$$'

.PHONY: launch-test
launch-test: ## 等待主场景(启动器)ready 后验证装配并显式释放
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/launch_test.gd '^launch_test: 1 passed, 0 failed$$'

.PHONY: pc-mode-test
pc-mode-test: ## 跑启动器 PC 模式测试(筛选排序、模式切换、详情页与游戏库、键鼠操作、开局与返回)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/pc_mode_test.gd '^pc_mode_test: [0-9]+ passed, 0 failed$$'

.PHONY: game-flow-test
game-flow-test: ## 跑游戏流程测试(游戏菜单、局内 HUD 与输入、暂停、结算、每局只记录一次)
	GODOT="$(GODOT)" scripts/run-godot-test.sh res://launcher/game_flow_test.gd '^game_flow_test: [0-9]+ passed, 0 failed$$'

.PHONY: launcher-shot
launcher-shot: ## 把启动器某一屏渲染成 1920x1080 PNG(需桌面会话,不进 CI;SCREEN=home STATE=played)
	GODOT="$(GODOT)" scripts/run-launcher-shot.sh $(SCREEN) $(STATE)

.PHONY: script-test
script-test: ## 测试构建/测试脚本自身的 fail-closed 契约
	bash scripts/tests/run-godot-test_test.sh
	bash scripts/tests/check-public-history_test.sh

# Not part of `make ci`: it needs the full history of every ref and fails by design on a history that ever held the internal notes. CI runs it once the repository is public.
.PHONY: publish-check
publish-check: ## 公开前门禁:任何 ref 的历史都不得含内部文档(需完整历史,不进 make ci)
	scripts/check-public-history.sh

# ---- aggregate ----

.PHONY: ci
ci: fmt-check tidy-check vet go-test go-standalone cli-build mcp-build script-test boundary-test architecture-test spike launcher-test settings-test library-test launch-test pc-mode-test game-flow-test ## 本地复现 Go 与 Godot 的全部 CI 门禁

.PHONY: ci-web
ci-web: web-install web-check web-build ## 本地复现官网 CI 门禁(需 Node 与 pnpm)

.PHONY: ci-all
ci-all: ci ci-web ## 全部门禁:Go + Godot + 官网

.PHONY: clean
clean: ## 清理构建产物与 Godot 导入缓存
	rm -rf $(SERVER_DIR)/bin $(SERVER_DIR)/server $(CLI_DIR)/bin $(MCP_DIR)/bin $(WEB_DIR)/dist $(WEB_DIR)/.astro $(CLIENT_DIR)/.godot
