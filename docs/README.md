# Classic Games 项目文档

Classic Games(经典厅)是一个开源的主机风格游戏启动器,自带一组经典类型的原创游戏,用手柄或键盘游玩,另有面向键盘鼠标的 PC 模式。
全部进度保存在本机,启动器不发网络请求。

## 一页纸概览

| 维度 | 结论 |
|---|---|
| 产品 | 主机风格的游戏启动器 + 一组经典类型的原创游戏。定位与原则见 [01-vision](./01-vision.md),决策见 [ADR-016](./decisions.md)。 |
| 现有游戏 | 星环巡航 / Orbit Patrol(飞行射击)、长夜草原 / Meadow Vigil(生存动作)、隘口守卫 / Gatewatch(塔防),都是原创、单人。 |
| 操作 | 手柄或键盘完成全部操作;PC 模式面向键盘鼠标,F11 切换。键盘按键可在设置里修改。 |
| 客户端技术 | Godot 4.6.3 单一工程。启动器在 `apps/client/launcher`,游戏 Runtime 在 `apps/client/runtime`,两者只经 `GameSession` 通信。见 [16-client-architecture](./16-client-architecture.md)。 |
| 游戏即数据 | 每款游戏由一份 Mod DSL 文档描述,启动器运行各 Runtime 自带的基线。见 [05-dsl-design](./05-dsl-design.md)。 |
| 数据 | 全部进度在本机的一个存档文件里;启动器不登录、不联网。 |
| 可选的在线服务 | Go 后端(gin + GORM,目前只支持 SQLite)、CLI、MCP 服务与 Go SDK 实现了 Mod DSL 的校验与补丁,以及账号、目录、Mod、社区、商业化等 API。可以运行、有测试,启动器没有接入。见 [04-architecture](./04-architecture.md)。 |
| 内容原则 | 游戏内容必须原创,不复刻现有商业游戏的名称、角色、美术或关卡。 |
| 计划 | 更多经典类型的原创游戏,没有日期。见 [07-roadmap](./07-roadmap.md)。 |

## 文档索引

**战略层**

1. [蓝图与愿景](./01-vision.md) — 产品定位、三层结构、现有游戏、原创原则

**技术层**

3. [技术调研](./03-research.md) — 早期定位下 Godot / 跨平台框架 / AI 网关 / DSL 方案的调研与选型依据
4. [技术架构](./04-architecture.md) — 仓库布局、启动器与 Runtime、可选在线服务的后端、架构门禁
16. [客户端架构](./16-client-architecture.md) — 启动器的屏幕、设置、游戏流程、PC 模式,以及 Runtime 边界
5. [Mod DSL 设计](./05-dsl-design.md) — DSL 结构、Runtime 契约、版本治理、补丁链
9. [API 设计](./09-api-design.md) — 可选在线服务的 HTTP 契约
10. [数据模型](./10-data-model.md) — 可选在线服务的表结构(按生产目标 PostgreSQL 描述)
11. [Runtime 内容清单](./11-runtime-content.md) — Shooter 预埋的素材与机制
12. [AI Prompt 工程](./12-ai-prompt.md) — 可选在线服务的 DSL 生成流程、约束、评测集、安全边界
18. [国际化](./18-i18n.md) — 界面语言与文案
19. [设计系统](./19-design-system.md) — 启动器的设计系统

**执行层**

6. [难点与风险](./06-challenges.md) — 早期定位下登记的 11 项难点 + 速查表
7. [开发计划](./07-roadmap.md) — 已完成的部分、已知不足、计划中的游戏类型
13. [测试策略](./13-testing.md) — 分层测试与质量门
14. [安全与合规](./14-security-compliance.md) — 可选在线服务的内容审核、合规、数据/AI 安全、滥用防护
8. [部署与运维](./08-deployment.md) — 在线服务的后端部署、CI/CD、客户端分发、监控

**参考**

- [决策记录(ADR Log)](./decisions.md) — 关键决策汇总 + 待定项
- [术语表](./glossary.md) — 统一叫法 + 界面用词对照
- [开源许可说明](./legal/licenses.md)、[用户协议](./legal/terms.md)、[隐私政策](./legal/privacy.md)

## 仓库里的其他入口

本目录只放设计与规划文档。代码按 `apps/` + `packages/` 组织(决策见 [ADR-015](./decisions.md)),各部分的使用说明在各自目录的 README 里:

| 路径 | 内容 | 说明 |
|---|---|---|
| `apps/client` | Godot 4.6 工程:启动器与游戏 Runtime | [16-client-architecture](./16-client-architecture.md) |
| `apps/server` | 可选在线服务的 Go 后端 | [apps/server/README](../apps/server/README.md) |
| `apps/cli` | 命令行工具 `classic-games` | [apps/cli/README](../apps/cli/README.md) |
| `apps/mcp` | MCP 服务 `classic-games-mcp` | [apps/mcp/README](../apps/mcp/README.md) |
| `apps/web` | 官网与文档站,构建时同步本目录的文档 | [apps/web/README](../apps/web/README.md) |
| `packages/schemas` | Mod DSL 的 JSON Schema | [05-dsl-design](./05-dsl-design.md) |
| `packages/dsl` | Go 模块 `github.com/yldm-tech/classic-games/packages/dsl`:补丁、迁移、schema 校验 | [packages/dsl/README](../packages/dsl/README.md) |
| `packages/sdk` | Go 模块 `github.com/yldm-tech/classic-games/packages/sdk`:后端 HTTP API 客户端 | [packages/sdk/README](../packages/sdk/README.md) |

根目录的 [README](../README.md)(英文)与 [README.zh-CN](../README.zh-CN.md)(中文)是仓库首页,[CONTRIBUTING](../CONTRIBUTING.md) 说明贡献流程与门禁。

## 阅读顺序建议

- 想了解「做什么、为什么」:1 → [ADR-016](./decisions.md) → 7
- 想了解启动器和游戏怎么实现:16 → 4 → 5 → 11
- 想了解可选的在线服务:4 → 9 → 10 → 12 → 14 → 8
- 要动手:先看根目录的 [CONTRIBUTING](../CONTRIBUTING.md),再看 [16-client-architecture](./16-client-architecture.md)
- 决策回看:[decisions](./decisions.md);概念不清:查 [术语表](./glossary.md)

## 关键约定

- 这些是项目的技术与规划文档,持续迭代,不是一次性产物。编号沿用历史顺序,缺号(2、15、17)对应未公开的内部文档。
- 当前运行架构以 [04-architecture](./04-architecture.md) 与 [16-client-architecture](./16-client-architecture.md) 为准。
- 3、6 两篇以及 5、9、10、12、14 里与 Fork、AI 创作、社区有关的内容写于 2026-11-11 改变定位之前([ADR-016](./decisions.md)),现在描述的是早期调研或可选的在线服务,各篇开头有说明。
- 技术决策若推翻,在对应文档里追加「决策变更」段落,保留旧结论和推翻理由,不要直接删。
- 公开仓库的 README / PR / issue 用英文(另有一份中文首页 `README.zh-CN.md`);这套文档用中文。
- 官网(`apps/web`)在构建时把本目录同步成站点页面:每篇文档必须有一个 H1,相对链接必须指向仓库里真实存在的路径,否则官网构建失败。
