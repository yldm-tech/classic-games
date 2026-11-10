# 测试策略

按「风险在哪、测试就重在哪」分配。本项目风险集中在 DSL/AI 链路和跨 5 端,测试也往这两处倾斜。

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

- **逻辑单元测试**:用 GUT(Godot Unit Test)或等价框架测 `RuntimeLoader`、DSL→游戏状态映射、纯逻辑组件。
- **GameSession 边界测试**:喂各种 DSL(合法/非法/版本不符)给 `start_game`,验证 `game_ended`/`game_error` 行为符合契约([04](./04-architecture.md))。这条边界是架构纪律,要有测试钉住。
- **虚拟列表组件测试**:大数据量下节点回收正确、无泄漏(性能回归)。

## 跨平台验证(5 端,本项目特有的重头)

不能只在编辑器里测,必须真机覆盖:

- **导出冒烟**:CI 每次导出 5 端产物 + 启动冒烟(能起来、不黑屏、核心导航可达)。
- **真机矩阵**:iOS / Android / macOS / Windows 至少各一台真机;Web 在主流浏览器。
- **重点回归项**(Godot 已知痛点,见 [06-challenges](./06-challenges.md)):
  - **中文/日文 IME 输入**——每个有输入框的页面,真机实测打字。这是全 Godot 命门,回归必查。
  - 长列表滚动手感与 FPS。
  - 深浅主题、横竖屏、各端窗口 chrome。
  - 原生集成(登录/分享/支付)各端真机走通。

## 端到端

核心闭环必须有 E2E 覆盖:

```
登录 → 进游戏 → AI 改 DSL(「换成猫」)→ 即时看到变化 → 发布 → 别人 Fork → Fork 后再改 → 再发布
```

这条链断在哪都是产品死穴,值得投入维护 E2E。

## 非功能测试

- **AI 接口压测 + 限流验证**:确认配额/限流生效,防滥用拖垮成本([14](./14-security-compliance.md))。
- **性能**:游戏帧率、列表 FPS、Web 包体与首屏加载(影响「即点即玩」)。
- **审核绕过测试**:尝试用 Fork/AI 生成绕过内容审核,验证双重审核拦得住([14](./14-security-compliance.md))。

## 测试在仓库里的位置

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `packages/dsl` | RFC 6902 补丁、DSL 迁移、schema 校验;与客户端共用 baseline + golden 的双端一致性测试在这里 | `make dsl-test` |
| `packages/sdk` | 后端 HTTP API 客户端:逐端点断言 method/path/query/body 与错误映射(httptest) | `make sdk-test` |
| `apps/server` | 领域服务、AI 编排重试链路、七模块装配与路由归属、迁移 registry | `make test` |
| `apps/cli` | 完整命令树对内存后端和仓库里的真实 baseline/schema | `make cli-test` |
| `apps/mcp` | 真实 MCP 客户端会话经内存传输驱动工具与资源,另有 stdio 子进程与 HTTP 传输 | `make mcp-test` |
| `apps/client` | Godot headless:HTTP 契约、七个 feature、共享 pattern、应用根、runtime spike、UI、启动 | `make http-test` … `make launch-test` |
| `scripts/tests` | 门禁脚本自身的 fail-closed 契约(测试 runner、两个架构检查器) | `make script-test`、`make boundary-test`、`make architecture-test` |
| `apps/web` | 类型检查、构建、文档同步与两道断链检查 | `make ci-web` |

`make ci` 把 Go 与 Godot 的门禁全部跑一遍,其中 Go 模块在 workspace 和 `GOWORK=off` 两种模式下各跑一次;`scripts/spike-integration.sh` 起真实后端,让 Godot 客户端调真实接口。`packages/sdk` 与 `apps/cli` 另有对真实后端的 e2e 测试(`TestE2E`),需要设置 `CLASSIC_GAMES_SDK_E2E_URL` / `CLASSIC_GAMES_CLI_E2E_URL` 才运行,不在 `make ci` 里。

## 质量门(CI)

- 后端 lint(zero-warnings 倾向)+ 单元/集成测试绿。
- DSL/补丁/版本测试绿。
- 客户端逻辑测试 + 5 端导出冒烟绿。
- **AI 评测集分数不低于基准线**(回归门)。
- 失败一律根因分析,不跳过、不注释掉测试(全局规范)。

## Spike 阶段的测试(Phase 0)

Phase 0 不写完整测试套件,但 spike 的退出标准本身就是验证(见 [07-roadmap](./07-roadmap.md)):IME 可接受、列表达标、5 端跑通、端到端 DSL 闭环通一次。把这些做成可重复的检查清单,Phase 1 直接沉淀为自动化测试。
