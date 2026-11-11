# 决策记录(ADR Log)

集中登记关键技术/产品决策,便于日后回看「当初为什么这么选」。
格式:决策 / 状态 / 理由 / 代价 / 推翻条件。新决策追加在表后,不删旧的;推翻了就改状态并记原因。

状态:✅ 已定 · 🧪 待 spike 验证 · ⏳ 待定 · ❌ 已推翻

---

## ADR-001 客户端用全 Godot,不嵌入异构壳

- **状态**:✅ 已定。原先要等 Phase 0 spike 验证 IME/列表后再确认;2026-11-11 客户端改为主机风格启动器(ADR-016),不再有评论、私聊和长列表,这项验证不再需要。
- **理由**:游戏必须 5 端原生跑(钉死 Godot);在 5 端把 Godot 嵌入原生/Flutter/RN 壳存在未知雷(桌面端嵌入无先例)。全 Godot 把风险收敛为可估工的 App UI 体力活,消除「嵌入失败推倒重来」。平台越多,全 Godot 边际成本越低。
- **代价**:接受 Godot 在 IME 输入、长列表、原生集成上的已知短板,逐项工程化。
- **推翻条件**:spike 中中文 IME 差到不可接受且私聊/评论为核心场景 → 退回「Flutter 壳 + 嵌 Godot」。
- 详见 [03-research](./03-research.md) §1、[04-architecture](./04-architecture.md) ADR。

## ADR-002 RN 在 5 端要求下出局

- **状态**:✅ 已定
- **理由**:一旦 Windows/macOS 是硬要求,RN 桌面端(微软的 rn-windows/rn-macos)是二等公民,长期补窟窿。
- **代价**:放弃 RN 复用 React 原型组件的便利。
- **推翻条件**:产品收缩为「只做 iOS/Android」时,RN 重新成为候选。
- 详见 [03-research](./03-research.md) §1。

## ADR-003 Shell 与 Runtime 经 GameSession 单一边界

- **状态**:✅ 已定
- **理由**:即便全 Godot,也把游戏与壳当两个进程,只经 `start_game`/`game_ended`/`game_error` 通信。保留「将来某端换原生壳、游戏侧原样拆出」的逃生口。
- **代价**:多一层接口约束,禁止两侧互抓内部。
- **推翻条件**:无;这是架构纪律核心。
- 详见 [04-architecture](./04-architecture.md)、[16-client-architecture](./16-client-architecture.md)。

## ADR-004 AI 只产出 DSL,绝不生成可执行代码

- **状态**:✅ 已定(源自产品设计)
- **理由**:把 AI 输出空间限死在 DSL Schema 内,保证可控、安全(无 eval)、可校验。AI 擅长增量改 DSL,不擅长从零写可靠代码。
- **代价**:用户创造边界 = Runtime 预埋枚举数量,非无限自由。
- **推翻条件**:无;这是核心范式。
- 详见 [01-vision](./01-vision.md)、[12-ai-prompt](./12-ai-prompt.md)、[14-security-compliance](./14-security-compliance.md)。

## ADR-005 Mod 存 DSL 补丁,不存整快照

- **状态**:✅ 已定
- **理由**:Fork 链才廉价、Fork Tree 才能深,符合 GitHub fork 心智。
- **代价**:读生效 DSL 要 apply 整条链 → 用 `effective_dsl` 缓存兜底。
- **推翻条件**:若补丁链 apply 的复杂度/歧义不可控,退回「存快照 + 单独记 Fork 关系」。
- 详见 [05-dsl-design](./05-dsl-design.md)、[10-data-model](./10-data-model.md)。

## ADR-006 AI 输出用 JSON Patch 精确定位,不整份重写

- **状态**:🧪 待 spike 验证模型产出稳定性
- **理由**:省 token、降改错率、天然就是入库补丁形态(与 ADR-005 统一)。
- **代价**:依赖模型稳定产出合法 JSON Patch。
- **推翻条件**:模型产 JSON Patch 不稳 → 退回「整份重写 + 后端 diff」。
- 详见 [12-ai-prompt](./12-ai-prompt.md)。

## ADR-007 AI 调用放后端,客户端不直连模型

- **状态**:✅ 已定
- **理由**:统一管控 API key、限流、配额、审计、成本核算,便于切换供应商。
- **代价**:多一跳网络;后端要承载 AI 流量。
- **推翻条件**:无明确推翻场景。
- 详见 [04-architecture](./04-architecture.md)、[14-security-compliance](./14-security-compliance.md)。

## ADR-008 Phase 1 直连一家模型,网关抽象先占位

- **状态**:✅ 已定;ClaudeProvider 已落地(`apps/server/internal/ai/claude_provider.go`)
- **理由**:不在验证核心假设的阶段引入不成熟中间件(LibreFang 待评估)。用 `LLMProvider` 接口占位,稳定后再接统一网关。
- **落地**:官方 anthropic-sdk-go,默认模型 **claude-opus-4-8**,用 tool use(`emit_dsl_patch`)强制结构化 6902 patch 输出;httptest mock 验证。无 `ANTHROPIC_API_KEY` 时退回 StubProvider。
- **代价**:早期只支持一家模型。
- **推翻条件**:统一网关验证成熟 → 接入多模型路由(接口不变,换实现)。
- 详见 [03-research](./03-research.md) §3、[12-ai-prompt](./12-ai-prompt.md)。

## ADR-009 MVP 砍掉社区壳,只验核心闭环

- **状态**:❌ 已推翻(2026-11-11)。产品不再以「玩→AI改→发布→Fork」闭环为目标,见 ADR-016。
- **理由**:精美社区壳(签到/商城/私聊)对验证「AI Mod 创作成立吗」无帮助。Phase 1 集中火力跑「玩→AI改→发布→Fork」最短闭环。
- **代价**:MVP 看起来「功能少」。
- **推翻条件**:无;这是 MVP 聚焦原则。
- 详见 [07-roadmap](./07-roadmap.md)。

## ADR-010 Phase 0 spike 先行,作为全量开发的决策门

- **状态**:❌ 已推翻(2026-11-11)。spike 要把关的是手机应用壳的全量开发,该方向已停止,见 ADR-016。
- **理由**:用 1-2 周买「技术栈选型对不对 + 5 端导出通不通」的确定性,再投三个月。
- **代价**:正式业务推迟 1-2 周。
- **推翻条件**:无。
- 详见 [07-roadmap](./07-roadmap.md)。

## ADR-011 后端用 Go,替换原定 NestJS

- **状态**:✅ 已定(2026-06-12 拍板)
- **理由**:团队主力 Go 技术栈(gin + GORM),自有沉淀与运维经验可直接复用;Go 单二进制部署、并发模型适合 AI 网关这类 I/O 密集 + 高并发转发场景,容器镜像更小、冷启动更快。依赖图由 `internal/app` 七个显式 installer 编译期类型检查，不引入代码生成式 injector。
- **代价**:放弃 NestJS「TypeScript 一把梭、模块化开箱即用」的便利;Go 侧需维护显式装配、窄端口和强类型配置/校验，样板略多，但依赖顺序与 route ownership 可直接测试。
- **推翻条件**:无明确推翻场景;若后端团队结构变为 TS 主力,可回看本条。
- **被替换决策**:原定 NestJS,理由见 [03-research](./03-research.md) §4(保留原结论,附决策变更说明)。
- 详见 [04-architecture](./04-architecture.md)、[08-deployment](./08-deployment.md)。

## ADR-012 单仓(monorepo),docs / client / server 同库

- **状态**:✅ 已定(2026-06-12 拍板)
- **理由**:早期小团队,文档、客户端、后端强耦合迭代(DSL Schema 是三方契约,跨 client/server 同步改),同仓一处改一个 PR,省跨仓对版本的开销。
- **代价**:仓库混合 Godot + Go 两套工具链,CI 要按子目录分别触发;后端团队独立时需拆仓。
- **推翻条件**:后端团队独立、需独立 CI/权限/发布节奏 → 拆出独立后端仓。
- **布局细节已被 ADR-015 取代**:「单仓」的结论与理由不变;标题里的 `docs / client / server` 是当时的顶层目录,现在的目录是 `apps/`(client、server、cli、mcp、web)+ `packages/`(schemas、dsl、sdk)+ `docs/`,工具链也不再只有 Godot 和 Go 两套(官网是 Node + pnpm)。
- 详见根 [README](../README.md)。

## ADR-013 补丁语义用 RFC 6902,集合字段 map 化(消解原 OPEN-1)

- **状态**:✅ 已定(2026-06-12 拍板,源自文档交叉互审 H1-H4)
- **理由**:补丁链要求「精确定位 + 可叠加 + 省 token」。Merge Patch(7386)对数组只能整体替换,做不到「删某敌人/改第 N 项」,会让补丁链失效;故选 JSON Patch(6902)。6902 对数组按下标定位,深 Fork 链头部插入会错位,故把会增删元素的集合(`enemies`/`drops`)设计成**以稳定 id 为 key 的 map**,6902 路径走 `/enemies/<id>/...`,key 稳定、AI 可按 id 引用。
- **代价**:DSL 里 `enemies`/`drops` 是 map 不是数组;id 命名/去重要约定(schema 已加 `propertyNames` 约束)。
- **推翻条件**:若 spike 中 6902 patch 在补丁链 apply 出现不可控复杂度 → 退回 ADR-005 的兜底(存快照 + 单独记 Fork 关系)。
- **产物**:[`packages/schemas/shooter-1.0.0.schema.json`](../packages/schemas/shooter-1.0.0.schema.json) 已按此落地。
- 详见 [05-dsl-design](./05-dsl-design.md)、[10-data-model](./10-data-model.md)、[12-ai-prompt](./12-ai-prompt.md)。

## ADR-014 服务端 DSL 校验用 santhosh-tekuri/jsonschema(draft 2020-12)

- **状态**:✅ 已定(2026-06-12 拍板,源自 spike 代码评审 schema-F6)
- **理由**:DSL 的权威校验在 Go 后端(docs/12-ai-prompt.md);需要一个支持 JSON Schema draft 2020-12 的库(schema 用了 oneOf/if-then/propertyNames)。`santhosh-tekuri/jsonschema/v6` 是 Go 生态标准、维护活跃、支持 2020-12。
- **代价**:引入一个外部依赖(+ 间接 golang.org/x/text)。
- **落地**:`packages/dsl/schema_validator.go`(Go 模块 `github.com/yldm-tech/classic-games/packages/dsl`,后端、CLI、MCP 共用)的 `SchemaValidator`,按 runtime 版本加载 `packages/schemas/<name>-<version>.schema.json`,编译缓存、并发安全。`MinimalValidator` 降为零配置兜底。
- **推翻条件**:库停止维护或 2020-12 支持出问题 → 换等价库(接口不变,只换实现)。
- 详见 [12-ai-prompt](./12-ai-prompt.md)、[09-api-design](./09-api-design.md)。

## ADR-015 仓库按 apps/ + packages/ 组织,抽出共享 Go 模块,以 Apache-2.0 开源

- **状态**:✅ 已定(2026-11-10 拍板)
- **决策**:
  - 顶层目录分两类:`apps/` 放可独立运行或发布的程序(`client` Godot 客户端、`server` Go 后端、`cli` 命令行、`mcp` MCP 服务、`web` 官网),`packages/` 放被多个程序共用的契约与库(`schemas` Mod DSL 的 JSON Schema、`dsl`、`sdk`)。依赖只允许 `apps → packages`。
  - 补丁(RFC 6902)、DSL 迁移、schema 校验从 `apps/server/internal/ai` 抽成 Go 模块 `github.com/yldm-tech/classic-games/packages/dsl`(`packages/dsl`);后端 HTTP API 的类型化客户端做成 Go 模块 `github.com/yldm-tech/classic-games/packages/sdk`(`packages/sdk`)。CLI 与 MCP 服务经 `github.com/yldm-tech/classic-games/packages/sdk` 走 HTTP 访问后端、经 `github.com/yldm-tech/classic-games/packages/dsl` 做离线校验,不 import `github.com/yldm-tech/classic-games/apps/server`。
  - 五个 Go 模块用根目录 `go.work` 组成 workspace,同时彼此以 `require classic-games/<name> v0.0.0` + 相对路径 `replace` 引用,每个模块在 `GOWORK=off` 下也能独立构建和测试。
  - 新增三个对外入口:CLI `classic-games`(cobra)、MCP 服务 `classic-games-mcp`(官方 `modelcontextprotocol/go-sdk`)、官网与文档站(Astro + Starlight,pnpm)。官网在构建时从 `docs/` 同步文档,不另存副本。
  - 项目以 Apache-2.0 开源,第三方归属记在根目录 `NOTICE` 与 [legal/licenses](./legal/licenses.md)。
  - 公开仓库从一个全新的根提交开始,不带本仓库此前的 git 历史。早期提交跟踪过后来移出公开目录的内部文档(文档索引里缺的 2、15、17 号,以及进度记录与计划目录);把文件移出工作树并不会把它们从历史里去掉,只要这些提交被推到公开 remote,内容就仍然可读。因此首次公开推送的内容必须是只含最终公开树的 orphan 根提交(或等价的压缩导入),现有分支及其祖先提交只留在私有仓库。没有选用 `git filter-repo` 改写历史:它同样会改掉全部提交的 SHA,还要求把要剔除的路径逐条列全,漏一条就泄露,而全新根提交按构造就不含旧内容。
- **理由**:
  - CLI 和 MCP 服务要对同一份 DSL 得出与后端完全相同的结论。若各自实现补丁与校验,就会在 Go 侧再出现「两份实现必须逐字节一致」的负担(客户端 GDScript 与 Go 之间已经有一份,见 ADR-013);抽成一个模块后 Go 侧只有一份实现,仍由与客户端共用的 baseline + golden 钉住。
  - `internal/` 下的包无法被仓库里的其他模块 import,所以共享代码必须放到 `apps/server` 之外。把后端当成应用而不是库,CLI/MCP 只依赖公开的 HTTP 契约,后端内部重构不会波及它们。
  - `apps/` 与 `packages/` 的划分让「谁依赖谁」可以机械检查:`scripts/check-architecture.sh` 拒绝 `packages/*` import 应用模块、CLI/MCP import 后端模块,以及后端重新长出私有的 DSL 实现。
  - 选 Apache-2.0 是因为它带明确的专利授权和贡献条款(第 5 条,inbound = outbound),并且与现有依赖(MIT / BSD / Apache-2.0)和 Godot(MIT)兼容。
- **代价**:
  - Go 模块从 1 个变成 5 个,`replace` 指令不会传递:一个模块依赖另一个本地模块时,要为后者的本地依赖再写一遍 `replace`;依赖版本要在五个 `go.mod` 之间保持一致,CI 因此同时跑 workspace 与 `GOWORK=off` 两种模式。
  - 模块路径 `classic-games/<name>` 只在本仓库内有效,没有发布到模块代理,仓库外的项目不能 `go get`,CLI 和 MCP 服务也只能在仓库检出内构建。要对外提供 Go SDK,需要把模块路径改成带域名的可解析路径,这是一次破坏性改名。
  - `packages/schemas` 不是 Go 模块,schema 无法 `go:embed` 进 CLI 或 MCP 的二进制:离线校验需要磁盘上的 schema 目录(仓库检出内自动找到,否则用 `CLASSIC_GAMES_SCHEMA_DIR` 指定)。
  - 双端一致性的 golden 测试随代码移到了 `packages/dsl`,它读取 `apps/client/runtime/shooter` 下的 baseline 与 golden;这是 `packages → apps` 方向上唯一的例外,只存在于测试数据,不是代码依赖。
  - 工具链从两套变成三套(Go、Godot、Node + pnpm),官网的构建会因为 `docs/` 里的断链而失败,写文档的人需要知道这一点。
  - `github.com/yldm-tech/classic-games/packages/sdk` 自己定义了 `PatchOp`,没有依赖 `github.com/yldm-tech/classic-games/packages/dsl`(为了保持只用标准库),CLI/MCP 在两种补丁类型之间要逐元素转换。
  - 公开仓库看不到开源之前的提交历史,`git blame` 与 `git log` 只能追溯到导入提交。`scripts/check-architecture.sh` 只检查当前工作树没有跟踪内部文档目录,看不到历史;历史由 `scripts/check-public-history.sh` 单独检查,它在任何 ref 的历史里出现过这些路径或内容时失败,并且拒绝在浅克隆上运行。私有仓库的现有历史按定义过不了这项检查,所以它是发布门禁而不是日常门禁:首次公开推送前必须在待公开的仓库上跑通,并确认待推送分支的根提交(`git rev-list --max-parents=0 <分支>`)是新建的导入提交。
- **推翻条件**:需要对外发布 Go SDK 或独立发版 CLI → 改用可解析的模块路径并给各模块打 tag;后端团队独立 → 按 ADR-012 的推翻条件拆仓,`packages/` 随契约的归属方走。
- 详见根 [README](../README.md)、[04-architecture](./04-architecture.md)、[CONTRIBUTING](../CONTRIBUTING.md)。

## ADR-016 产品改为主机风格启动器 + 经典类型的原创游戏合集

- **状态**:✅ 已定(2026-11-11 拍板)
- **背景**:
  - 此前的产品是竖屏手机上的 UGC 应用:Fork 一个游戏,用自然语言让 AI 修改 Mod DSL,发布到社区再被他人 Fork(见 [01-vision](./01-vision.md) 的「决策变更」)。客户端为此实现了信息流、AI 创作流程、社区、商业化与账号等界面,后端实现了对应的 API。
  - 该方向自己定义的决策门在改向时仍未通过:[07-roadmap](./07-roadmap.md) 原 Phase 0 清单里的中文 IME 真机实测、虚拟列表原型、5 端真机导出、创造感盲测和裸 PGC 留存都没有完成,其中后两项验证的是「产品该不该做」。
  - 同一时间,客户端里已经有一个完整的主机风格启动器(`apps/client/launcher`)和三款可以完整游玩的游戏,并由无头测试覆盖。
- **决策**:
  - Classic Games(经典厅)是一个开源的主机风格游戏启动器,自带一组经典类型的原创游戏,用手柄或键盘游玩,另有面向键盘鼠标的 PC 模式。这是项目所有者的产品决定。
  - 客户端的主场景是启动器。启动器完全本地:不登录、不发网络请求,全部进度保存在一个本地存档里。
  - 现有三款游戏是星环巡航 / Orbit Patrol、长夜草原 / Meadow Vigil、隘口守卫 / Gatewatch,分别运行 `shooter`、`survivor`、`tower_defense` 三个 Runtime 的基线 DSL。后续计划加入更多经典类型的原创游戏(基地防御坦克、横版平台跳跃、合作平台跳跃、迷宫炸弹、合作清版街机、跑动射击),不设日期。
  - **游戏内容必须原创。** 可以做经典的类型,不得复刻任何现有商业游戏的名称、角色、美术或关卡,不得使用其商标,也不得加入从其他游戏提取的素材或来源、许可不明的素材。每一份素材的来源与许可记在 [legal/licenses](./legal/licenses.md)。
  - 客户端里的手机应用壳(信息流、AI 创作流程、社区、商业化、账号界面及其 feature 切片、组合根、公共 UI 和测试)整体移除。
  - Go 后端、CLI、MCP 服务、Go SDK、`packages/dsl` 与 `packages/schemas` 原样保留。它们实现了 Mod DSL(schema 校验、RFC 6902 补丁、迁移、与 GDScript 实现共用 golden 文件的一致性测试)和一套在线服务的 API(账号、目录、Mod、社区、商业化),定位是可选组件:可以运行、有测试,启动器没有接入。本决策不包含把启动器接到在线服务上的计划。
- **后果**:
  - Runtime、Mod DSL 与 `GameSession` 边界(ADR-003、ADR-013、ADR-014)继续有效,从「可被 Fork 的创作基础」变成「每款游戏的实现方式」。新增一款游戏 = 一个 Runtime + 一份 schema 与基线 + 启动器目录里的一条数据。
  - ADR-004、ADR-005、ADR-006、ADR-007、ADR-008 约束的是在线服务里的 AI 生成与 Mod 存储,对在线服务继续有效,与启动器无关。ADR-009 与 ADR-010 被本决策推翻;ADR-001 中等待 spike 验证的 IME 与长列表风险随手机应用壳一起消失。
  - 原创要求成为评审规则:不符合的贡献不合并,无论质量如何。类型本身不受限制,受限制的是对某一款具体游戏的表达的复制。现有三张主视觉由图像生成模型生成,其来源已按此要求记录。
  - 仓库里保留着一套启动器不使用的后端与工具。它们继续占用 CI 时间和维护成本,文档必须在每处说明「可选、未接入」,避免读者以为启动器依赖它们。
  - 原先按用户数、Mod 数、Fork 数设定的成功指标不再适用,新的衡量方式尚未确定。
  - 局内画面目前是几何图形,没有贴图美术;对外材料(README、官网)必须如实展示,主视觉不得被当作实际画面。
  - 早期文档([03-research](./03-research.md)、[06-challenges](./06-challenges.md) 等)保留原貌作为记录,在开头注明写作时的定位。
- **推翻条件**:决定让启动器接入在线服务 → 另立 ADR,先回答账号、隐私与离线可用性;决定收录非原创内容 → 必须先取得明确的授权并另立 ADR,否则不做。
- 详见 [01-vision](./01-vision.md)、[07-roadmap](./07-roadmap.md)、[16-client-architecture](./16-client-architecture.md)、根 [CONTRIBUTING](../CONTRIBUTING.md)。

---

## 待定项(需后续拍板)

| 编号 | 议题 | 关联 |
|---|---|---|
| ~~OPEN-1~~ | ~~补丁合并语义选 RFC 7386 还是 6902~~ → **已定,见 ADR-013** | [05-dsl-design](./05-dsl-design.md) |
| ~~OPEN-2~~ | ~~DSL 能否描述关卡/波次序列结构~~ → **已定：稳定 ID 的 map 化 waves/enemies，结构生成与三 Runtime 已验证** | [05](./05-dsl-design.md) / [11-runtime-content](./11-runtime-content.md) |
| OPEN-3 | 资源是否允许用户/AI 上传(打开自由度但引入审核/版权) | [05](./05-dsl-design.md) / [14-security-compliance](./14-security-compliance.md) |
| OPEN-4 | Fork Tree 存储:邻接表何时升级闭包表/ltree | [10-data-model](./10-data-model.md) |
| OPEN-5 | 抽成/分成比例 | — |
