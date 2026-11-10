# 术语表

统一项目内的叫法,避免「分叉/二创/fork」这类同义混用(原型迭代里踩过这个坑)。
面向用户的中文文案用「二创/改一版」,技术文档和代码用「Fork」。

| 术语 | 定义 | 备注 |
|---|---|---|
| **Runtime** | 官方维护的游戏运行时,提供完整游戏逻辑框架。用户不可直接改,只能经 Mod 扩展。 | Layer 1。初期:Shooter / Survivor / TD / Roguelike |
| **Mod** | 在 Runtime 之上的一份增量修改(DSL 补丁)。 | Layer 2。物理存储见 [10-data-model](./10-data-model.md) `mods` |
| **DSL** | Mod 的结构化表达(JSON)。AI 和用户操作的唯一对象。 | Domain-Specific Language。详见 [05-dsl-design](./05-dsl-design.md) |
| **生效 DSL (effective DSL)** | Runtime 基线 + 沿父链逐层 apply 补丁后,实际喂给游戏的完整 DSL。 | = baseline + patch 链 |
| **Patch / 补丁** | 一个 Mod 相对其父级的 DSL diff。 | **RFC 6902(JSON Patch)**,见 [ADR-013](./decisions.md) |
| **Fork** | 以某个游戏/Mod 的生效 DSL 为起点,创建自己的新版本。 | 用户文案叫「二创」「改一版」 |
| **Fork Tree** | 一个游戏衍生出的全部 Fork 构成的树。 | Layer 4 |
| **创作链 (lineage)** | Fork Tree 中从根到某节点的路径。 | 如「熔岩环道 → 漂移改版 → 本作 → 你的版本」 |
| **GameSession** | 客户端内 Shell 与 Runtime 之间的唯一通信边界(`start_game` / `game_ended` / `game_error`)。 | 架构纪律核心,见 [04-architecture](./04-architecture.md) |
| **RuntimeLoader** | Runtime 侧组件:读 DSL → 校验版本 → 套用到游戏。 | |
| **Shell** | 客户端的非游戏部分:社区/发现/编辑器/社交/个人中心。全 Godot 实现。 | |
| **LLMProvider** | 后端对多模型(Claude/GPT/Gemini/本地)的统一抽象接口。 | |
| **Runtime 版本治理** | 保证 Runtime 升级不使存量 Mod 集体失效的一套规则(pin 版本 + 语义化版本 + 迁移)。 | [05-dsl-design](./05-dsl-design.md) |
| **内容清单** | 某 Runtime 预埋的素材/机制枚举集合。决定用户创造边界。 | [11-runtime-content](./11-runtime-content.md) |
| **评测集** | 量化 AI 改 DSL 质量的真实意图样例集 + 指标。 | [12-ai-prompt](./12-ai-prompt.md) |
| **创作点 (credits)** | 平台内虚拟货币/积分。创作奖励、消费、充值。 | |
| **Spike** | Phase 0 的技术验证,不写业务,只买「选型对不对」的确定性。 | [07-roadmap](./07-roadmap.md) |

## 文案术语对照(用户侧)

迭代中确定的中文用户文案(避免程序员黑话):

| 技术词 | 用户文案 |
|---|---|
| Fork | 二创 / 改一版 |
| forge / 生成 | 创作 / 生成 |
| explore | 发现 |
| fork lineage | 创作链 |
| play now | 立即开玩 |

多语言(中/英/日)文案库见客户端 i18n。
