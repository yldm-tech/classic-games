# 术语表

统一项目内的叫法。表格前半是启动器与游戏的术语,后半是 Mod DSL 与可选在线服务的术语;后者在启动器的界面里不出现。

| 术语 | 定义 | 备注 |
|---|---|---|
| **启动器 (launcher)** | 客户端的主场景:选游戏、看记录与成就、改设置,并承载一局游戏的 HUD、暂停与结算。 | `apps/client/launcher`,见 [16-client-architecture](./16-client-architecture.md) 第 8 节 |
| **主机模式 / PC 模式** | 启动器的两种布局。主机模式面向手柄和键盘;PC 模式面向键盘和鼠标。数据相同。 | F11 或长按 View 切换;设置项 `default_mode` |
| **游戏目录 (catalog)** | 启动器提供哪些游戏:启动时从每个游戏目录的清单读出名称、类型、人数、一句话介绍、成就定义。 | `apps/client/games/*/game.json`,经 `launcher_catalog.gd` 查询 |
| **一局 (run)** | 从开局到通关、失败、超时或退出的一次游玩。每局结束时恰好写一次存档。 | `GameSession.start_run` / `end_run` |
| **本地存档** | 保存游玩记录、收藏、最近游玩、成就、设置与改键的唯一文件。 | `user://launcher.json`,`launcher_store.gd` |
| **主视觉 (key art)** | 启动器里代表一款游戏的插画,不是局内画面。 | 各游戏目录里清单 `art.image` 指向的图片,来源见该目录的 `ASSETS.md` |
| **成就** | 游戏目录里定义的条件,由一局结束时的结果判定;中途退出的一局不计。 | |
| **在线服务** | Go 后端、CLI、MCP 服务与 Go SDK 提供的账号、目录、Mod、社区、商业化等能力。可选,启动器没有接入。 | [04-architecture](./04-architecture.md)、[09-api-design](./09-api-design.md) |
| **Runtime** | 一款游戏的运行时,提供完整的游戏逻辑;玩什么由 DSL 决定。 | 目前有 `shooter`、`survivor`、`tower_defense` |
| **基线 (baseline)** | 每个 Runtime 自带的那份完整 DSL,启动器运行的就是它。 | `apps/client/runtime/<name>/baseline.dsl.json` |
| **Mod** | 在 Runtime 之上的一份增量修改(DSL 补丁)。 | 在线服务的概念。物理存储见 [10-data-model](./10-data-model.md) `mods` |
| **DSL** | 描述一个 Runtime 玩什么的结构化数据(JSON),受该 Runtime 的 JSON Schema 约束。 | Domain-Specific Language。详见 [05-dsl-design](./05-dsl-design.md) |
| **生效 DSL (effective DSL)** | Runtime 基线 + 沿父链逐层 apply 补丁后,实际喂给游戏的完整 DSL。 | = baseline + patch 链 |
| **Patch / 补丁** | 对一份 DSL 的修改;在线服务里是一个 Mod 相对其父级的 diff,启动器里是开局选项对基线的改动。 | **RFC 6902(JSON Patch)**,见 [ADR-013](./decisions.md) |
| **Fork** | 以某个游戏/Mod 的生效 DSL 为起点,创建自己的新版本。 | 在线服务的概念,启动器里没有 |
| **Fork Tree** | 一个游戏衍生出的全部 Fork 构成的树。 | 在线服务的概念 |
| **创作链 (lineage)** | Fork Tree 中从根到某节点的路径。 | 在线服务的概念 |
| **GameSession** | 客户端内启动器与 Runtime 之间的唯一通信边界(`start_run` / `game_ended` / `game_error` 等)。 | 架构纪律核心,见 [04-architecture](./04-architecture.md) |
| **RuntimeLoader** | Runtime 侧组件:读 DSL → 校验版本 → 套用到游戏。 | |
| **LLMProvider** | 后端调用模型的抽象接口。 | 在线服务;目前的实现是 Claude 与无 key 时的确定性 stub |
| **Runtime 版本治理** | 保证 Runtime 升级不使存量 Mod 集体失效的一套规则(pin 版本 + 语义化版本 + 迁移)。 | [05-dsl-design](./05-dsl-design.md) |
| **内容清单** | 某 Runtime 预埋的素材/机制枚举集合,DSL 只能从中选择。 | [11-runtime-content](./11-runtime-content.md) |
| **评测集** | 量化 AI 改 DSL 质量的真实意图样例集 + 指标。 | 在线服务;[12-ai-prompt](./12-ai-prompt.md) |
| **创作点 (credits)** | 在线服务里的虚拟货币/积分。 | 在线服务的概念,启动器里没有 |

## 界面用词对照

启动器内置中文和英文两种界面语言,文案在 `apps/client/i18n/launcher_strings.gd`。

| 中文 | English |
|---|---|
| 经典厅 | Classic Games |
| 首页 | Home |
| 游戏库 | Library |
| 成就 | Achievements |
| 设置 | Settings |
| 开始游戏 | Start game |
| 游戏菜单 | Game menu |
| 玩法与操作 | How to play |
| 主机模式 | Console mode |
| PC 模式 | PC mode |
