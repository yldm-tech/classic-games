# 测试策略

按「风险在哪、测试就重在哪」分配。本项目风险集中在 DSL/AI 链路、双端共用的运行时数据和启动器的交互状态,测试也往这几处倾斜。

## 分层

### 后端(Go)

- **单元测试**:业务逻辑、DSL 补丁 apply、Fork 链解析、版本兼容判断。纯函数优先,易测。
- **集成测试**:API 契约([09-api-design](./09-api-design.md))、DB 读写、审核队列流转。用测试库,不 mock 数据库行为(见全局规范:不要测 mock 的行为)。
- **契约测试**:`runtimes/:name/:version/schema` 返回的 schema 与 Runtime 实际加载逻辑一致——schema 是三方契约([05](./05-dsl-design.md)),必须有测试守住。

### DSL / AI 链路(本项目最该重测的地方)

- **DSL 校验测试**:合法样例必过、非法样例(超范围、未知枚举、缺 runtime_version)必拒。
- **补丁链测试**:多层 Fork 的 patch apply 结果确定、可重放;合并语义(RFC 7386/6902)边界用例。
- **版本治理测试**:major 升级的 DSL 迁移正确;不兼容版本加载返回 `RUNTIME_VERSION_MISMATCH` 而非崩溃([05](./05-dsl-design.md))。
- **AI 评测集(回归基准)**:见 [12-ai-prompt](./12-ai-prompt.md)。50+ 真实意图,量化合法率/意图命中率/token/重试。**每次换模型或改 prompt 必跑**,防质量退化。这是 AI 产品质量的核心抓手,不是可选项。

### 客户端(Godot)

客户端是主机风格启动器加三个游戏运行时([16-client-architecture](./16-client-architecture.md)),不联网,所以它的测试全部是 headless 的本地测试,不需要后端。每个测试是一个 `extends SceneTree` 的脚本,经 `scripts/run-godot-test.sh` 运行:先校验 Godot 精确版本并导入资源,再跑脚本;进程退出码非零、出现脚本解析或加载错误、退出时有泄漏的对象或资源、没有打印约定的成功摘要,任何一条都算失败。

| 测试 | 目标 | 内容 |
|---|---|---|
| `spike_test.gd` | `make spike` | 运行时:`GameSession` 的 `game_ended` / `game_error` 边界、RFC 6902 补丁链与 `packages/dsl` 共用的 golden、DSL 迁移与版本不符、三个运行时的加载与玩法规则、Shooter 的武器 / Boss / 掉落、联机快照的单调性 |
| `launcher/launcher_test.gd` | `make launcher-test` | 存档(原子写入、损坏文件恢复、游玩记录)、游戏目录与成就条件、显示格式、文案表(中英 key 一致、占位符一致)、工程设置与按键覆盖、经 `GameSession` 的真实一局、首页导航、开局与结算 |
| `launcher/library_test.gd` | `make library-test` | 游戏库与成就屏:网格焦点与滚动、分类、排序、搜索、收藏 |
| `launcher/settings_test.gd` | `make settings-test` | 各设置项及其在启动时的应用、改键与冲突、存档导入导出、手柄连发 |
| `launcher/game_flow_test.gd` | `make game-flow-test` | 游戏菜单、局内 HUD 与输入、暂停、结算、每局只记录一次 |
| `launcher/pc_mode_test.gd` | `make pc-mode-test` | PC 模式:筛选排序、模式切换、详情页与游戏库、键鼠操作、开局与返回 |
| `launcher/launch_test.gd` | `make launch-test` | 等主场景 ready 后验证装配并显式释放 |

两条结构性门禁不跑 Godot,只扫描源码:`make boundary-test`(依赖方向、启动器不联网)与 `make architecture-test`(已移除的手机应用壳不得回归,另含后端与 Go 模块的规则)。两个检查器都先跑自测(`scripts/tests/`),用最小的违例样本证明每条规则确实会失败。

`make launcher-shot SCREEN=<屏幕> STATE=<played|fresh>` 把启动器的某一屏渲染成 1920×1080 的 PNG,供人工查看视觉效果([19-design-system](./19-design-system.md))。它需要真实的渲染器,不在 `make ci` 里。

## 跨平台验证

`apps/client/export_presets.cfg` 保留 Web、Windows、macOS、Android、iOS 五个导出预设,`scripts/export-all.sh` 依次导出。CI 目前不做导出,也没有真机矩阵;启动器按 16:9 的固定画布设计,面向键盘、手柄和鼠标,在桌面平台上开发和验证。发布某个平台之前需要在该平台上人工确认:

- 能启动、不黑屏,首页、游戏库、成就、设置可达,三款游戏能开始并结算;
- 手柄的按键与摇杆、键盘改键、鼠标悬停与点击;
- 窗口模式切换(窗口、全屏、独占全屏)、垂直同步与帧率上限;
- 系统字体里有中文字形(仓库不带字体文件,见 [18-i18n](./18-i18n.md))。

## 后端与客户端之间

客户端不调用后端,二者之间没有端到端流程。它们共享的是数据:`apps/client/runtime/<name>/baseline.dsl.json` 是后端注册的基线,`apps/client/runtime/shooter/testdata/fork_expected.dsl.json` 是 GDScript 与 Go 两份补丁实现共用的 golden。守住这层一致性的有三处:`make spike`(客户端一侧)、`make dsl-test`(Go 一侧),以及 `scripts/spike-integration.sh`。后者编译并启动真实后端(临时目录里的全新数据库),经 HTTP 验证:未登录的写请求被拒、游客登录、三个运行时的基线与客户端文件一致、schema 可取、`/ai/validate` 接受基线并以 `DSL_INVALID` 拒绝越界值、未配置模型密钥时 `/ai/mod` 由内置的 stub 给出补丁、根 mod → Fork → 子 mod 的生效 DSL 等于共用的 golden。它需要 `go`、`curl`、`jq`,不在 `make ci` 里。

## 非功能测试

- **AI 接口压测 + 限流验证**:确认配额/限流生效,防滥用拖垮成本([14](./14-security-compliance.md))。
- **性能**:游戏帧率、启动器滚动与切屏的流畅度。
- **审核绕过测试**:尝试用 Fork/AI 生成绕过内容审核,验证双重审核拦得住([14](./14-security-compliance.md))。

## 测试在仓库里的位置

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `packages/dsl` | RFC 6902 补丁、DSL 迁移、schema 校验;与客户端共用 baseline + golden 的双端一致性测试在这里 | `make dsl-test` |
| `packages/sdk` | 后端 HTTP API 客户端:逐端点断言 method/path/query/body 与错误映射(httptest) | `make sdk-test` |
| `apps/server` | 领域服务、AI 编排重试链路、七模块装配与路由归属、迁移 registry | `make test` |
| `apps/cli` | 完整命令树对内存后端和仓库里的真实 baseline/schema | `make cli-test` |
| `apps/mcp` | 真实 MCP 客户端会话经内存传输驱动工具与资源,另有 stdio 子进程与 HTTP 传输 | `make mcp-test` |
| `apps/client` | Godot headless:运行时(`spike_test.gd`)与启动器的六个测试 | `make spike`、`make launcher-test`、`make library-test`、`make settings-test`、`make game-flow-test`、`make pc-mode-test`、`make launch-test` |
| `scripts/tests` | 门禁脚本自身的 fail-closed 契约(测试 runner、两个架构检查器) | `make script-test`、`make boundary-test`、`make architecture-test` |
| `apps/web` | 类型检查、构建、文档同步与两道断链检查 | `make ci-web` |

`make ci` 把 Go 与 Godot 的门禁全部跑一遍,其中 Go 模块在 workspace 和 `GOWORK=off` 两种模式下各跑一次;`scripts/spike-integration.sh` 起真实后端并经 HTTP 核对它与客户端运行时文件的一致性(见上文),不在 `make ci` 里。`packages/sdk` 与 `apps/cli` 另有对真实后端的 e2e 测试(`TestE2E`),需要设置 `CLASSIC_GAMES_SDK_E2E_URL` / `CLASSIC_GAMES_CLI_E2E_URL` 才运行,不在 `make ci` 里。

## 质量门(CI)

`.github/workflows/ci.yml` 的四个 job 与本地的 `make ci`、`make ci-web` 对应:

- 后端:`go vet` 与 `go test`。
- Go 模块:gofmt、`go.mod` / `go.sum` 整洁、workspace 与 `GOWORK=off` 两种模式下的 vet 和测试、CLI 与 MCP 可编译。
- 官网:类型检查、构建与断链检查。
- 客户端:测试 runner 与检查器的自测、依赖边界、仓库架构、运行时测试、启动器的六个测试;仓库公开后另查任何 ref 的历史都不含内部文档。
- 失败一律根因分析,不跳过、不注释掉测试。
