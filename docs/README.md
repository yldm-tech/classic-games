# Classic Games 项目文档

AI 驱动的小游戏创作与社区平台。
用户无需编程,通过自然语言对现有游戏进行修改、扩展、重新创作,并发布到社区供他人体验和 Fork。
形态上是 GitHub + Roblox + NexusMods 的混合体。

## 一页纸概览

| 维度 | 结论 |
|---|---|
| 核心范式 | 不是「用户从零创建游戏」,而是「用户 Fork 游戏 → AI 改 → 发布」。AI 擅长增量修改,不擅长从零创造。 |
| 核心赌注 | **Mod DSL 的表达力 vs 约束性**。产品成败 90% 押在这,不是引擎选型。见 [05-dsl-design](./05-dsl-design.md)。 |
| 客户端技术 | **全 Godot,一套工程导 5 端**(iOS / Android / macOS / Windows / Web)。决策与理由见 [04-architecture](./04-architecture.md)。 |
| 后端 | Go(gin + GORM)模块化单体；七个领域 installer 经窄端口装配。数据库目前只支持 SQLite(后端只链接了 `gormlite` 驱动);PostgreSQL 与 S3/MinIO 对象存储是生产目标,尚未实现。栈选型见 [ADR-011](./decisions.md)。 |
| AI | 后端经 `LLMProvider` 接口调用模型,目前只有 Claude 一个真实 provider,外加无 API key 时使用的确定性 stub;接入 GPT / Gemini / 本地模型的多模型网关是目标,尚未实现([ADR-008](./decisions.md))。AI 只生成和修改 DSL,**绝不生成可执行代码**。 |
| 第一步 | **不写业务,先写 1-2 周技术 spike**:验中文 IME、虚拟列表、5 端导出闭环。spike 绿了才全量开干。见 [07-roadmap](./07-roadmap.md)。 |
| MVP 目标 | 验证「AI 改 DSL 创作」是否成立。100 用户 / 1000 Mod / 500 Fork。周期 4~6 周。 |

## 文档索引

**战略层**

1. [蓝图与愿景](./01-vision.md) — 产品定位、核心理念、四层架构、成功指标

**技术层**

3. [技术调研](./03-research.md) — Godot / 跨平台框架 / AI 网关 / DSL 方案的调研与选型依据
4. [技术架构](./04-architecture.md) — 客户端、后端、数据、AI、存储,以及「全 Godot」决策记录
16. [客户端架构](./16-client-architecture.md) — 全 Godot 工程结构、Shell 拆分、虚拟列表/输入/导航、平台插件
5. [Mod DSL 设计](./05-dsl-design.md) — 核心赌注:DSL 结构、Runtime 契约、版本治理、Fork 模型
9. [API 设计](./09-api-design.md) — 后端 HTTP 契约
10. [数据模型](./10-data-model.md) — 表结构详细设计(按生产目标 PostgreSQL 描述)
11. [Runtime 内容清单](./11-runtime-content.md) — Shooter 预埋素材/机制(Phase 1 真正的工作量)
12. [AI Prompt 工程](./12-ai-prompt.md) — DSL 生成流程、约束、评测集、安全边界
18. [国际化](./18-i18n.md) — 中/英/日、Godot i18n、数字/渠道本地化、文案质量
19. [设计系统](./19-design-system.md) — 设计 token → Godot Theme 映射、组件库、设计评审

**执行层**

6. [难点与风险](./06-challenges.md) — 11 项难点按严重度排序 + 速查表
7. [开发计划](./07-roadmap.md) — spike 先行、Phase 1/2/3 里程碑、范围边界
13. [测试策略](./13-testing.md) — 分层测试、AI 评测集、5 端验证、质量门
14. [安全与合规](./14-security-compliance.md) — 内容审核、监管合规、数据/AI 安全、滥用防护
8. [部署与运维](./08-deployment.md) — 后端部署、CI/CD、5 端客户端发布、监控

**参考**

- [决策记录(ADR Log)](./decisions.md) — 关键决策汇总 + 待定项
- [术语表](./glossary.md) — 统一叫法 + 用户侧文案对照
- [开源许可说明](./legal/licenses.md)、[用户协议](./legal/terms.md)、[隐私政策](./legal/privacy.md)

## 仓库里的其他入口

本目录只放设计与规划文档。代码按 `apps/` + `packages/` 组织(决策见 [ADR-015](./decisions.md)),各部分的使用说明在各自目录的 README 里:

| 路径 | 内容 | 说明 |
|---|---|---|
| `apps/client` | Godot 4.6 客户端与游戏 Runtime | [16-client-architecture](./16-client-architecture.md) |
| `apps/server` | Go 后端 | [apps/server/README](../apps/server/README.md) |
| `apps/cli` | 命令行工具 `classic-games` | [apps/cli/README](../apps/cli/README.md) |
| `apps/mcp` | MCP 服务 `classic-games-mcp` | [apps/mcp/README](../apps/mcp/README.md) |
| `apps/web` | 官网与文档站,构建时同步本目录的文档 | [apps/web/README](../apps/web/README.md) |
| `packages/schemas` | Mod DSL 的 JSON Schema | [05-dsl-design](./05-dsl-design.md) |
| `packages/dsl` | Go 模块 `github.com/yldm-tech/classic-games/packages/dsl`:补丁、迁移、schema 校验 | [packages/dsl/README](../packages/dsl/README.md) |
| `packages/sdk` | Go 模块 `github.com/yldm-tech/classic-games/packages/sdk`:后端 HTTP API 客户端 | [packages/sdk/README](../packages/sdk/README.md) |

根目录的 [README](../README.md)(英文)与 [README.zh-CN](../README.zh-CN.md)(中文)是仓库首页,[CONTRIBUTING](../CONTRIBUTING.md) 说明贡献流程与门禁。

## 阅读顺序建议

- 想了解「做什么、为什么」:1 → 5
- 想了解「怎么做」:4 → 16 → 5 → 10 → 9 → 12 → 6 → 7
- 要动手:直接看 [07-roadmap](./07-roadmap.md) 的 spike 清单;Phase 1 内容看 [11-runtime-content](./11-runtime-content.md)
- 决策回看:[decisions](./decisions.md);概念不清:查 [术语表](./glossary.md)

## 关键约定

- 这些是项目的技术与规划文档,持续迭代,不是一次性产物。编号沿用历史顺序,缺号(2、15、17)对应未公开的内部文档。
- 当前运行架构以 [04-architecture](./04-architecture.md) 与 [16-client-architecture](./16-client-architecture.md) 为准。
- 技术决策若推翻,在对应文档里追加「决策变更」段落,保留旧结论和推翻理由,不要直接删。
- 公开仓库的 README / PR / issue 用英文(另有一份中文首页 `README.zh-CN.md`);这套文档用中文。
- 官网(`apps/web`)在构建时把本目录同步成站点页面:每篇文档必须有一个 H1,相对链接必须指向仓库里真实存在的路径,否则官网构建失败。
