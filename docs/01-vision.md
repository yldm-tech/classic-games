# 蓝图与愿景

## 一句话

打造一个 AI 原生的游戏创作社区:用户不需要学 Unity、不需要学 Godot,只要说「把 Boss 改成哥斯拉」,就能创造属于自己的游戏版本,并发布、被他人 Fork,形成持续增长的 UGC 与 Fork 生态。

## 核心理念:Fork,而非从零创造

传统范式:

```
用户 → 创建游戏
```

ForgePlay 范式:

```
用户 → Fork 游戏 → AI 修改 → 发布作品
```

这个取舍基于一个判断:**AI 更擅长增量修改,而非从零创造。**
让 AI「生成一个完整可玩的游戏」既不可靠也不可控;让 AI「在一个已经能跑的游戏上改几个参数和素材」则稳定得多。
因此平台提供多个官方维护的 Runtime 作为创作基础,所有创作都是在 Runtime 之上的增量修改。

这也是平台的核心定位:**平台的价值不是游戏本身,而是 Runtime + AI Mod 系统 + Fork 社区生态这三者的组合。**

## 四层架构

### Layer 1 — Runtime(运行时)

官方维护的游戏运行时,提供完整的游戏逻辑框架。
用户**无法直接修改 Runtime**,只能通过 Mod 层扩展。
这是「约束创造自由」的设计:正因为 Runtime 把游戏跑通了,用户的增量修改才总是能得到一个可玩的结果。

初期规划的 Runtime:

| Runtime | 对标 | 可改对象 |
|---|---|---|
| Shooter | 飞机大战、弹幕射击、生存射击 | 玩家属性、武器、敌人、Boss、掉落物 |
| Survivor | Vampire Survivors | 技能、Buff、装备、敌人波次 |
| Tower Defense | 植物大战僵尸、王国保卫战 | 防御塔、怪物、路径、波次 |
| Roguelike | 元气骑士、哈迪斯简化版 | 地图、房间、道具、技能 |

Phase 1 只做 **Shooter Runtime**,跑通最短闭环。

### Layer 2 — Mod DSL

AI 和用户操作的**唯一对象**。
一份描述「在 Runtime 上改了什么」的结构化数据(JSON)。
详见 [05-dsl-design](./05-dsl-design.md)——这是整个产品的核心赌注。

### Layer 3 — AI Layer

把自然语言翻译成 DSL 修改。

```
用户:「把飞机换成猫」      → AI:{ "player": { "sprite": "cat" } }
用户:「加一个会喷火的 Boss」 → AI:{ "boss": { "enabled": true, "skill": "fireball" } }
```

AI 职责:DSL 生成、DSL 修改、DSL 优化、平衡性建议。
**AI 不允许生成可执行代码**——它永远只产出 DSL,由 Runtime 解释执行。
这是安全边界,也是可控性的来源:AI 的输出空间被 DSL schema 限死,跑不出非法或危险的东西。

### Layer 4 — Community(社区)

每个游戏都是一棵 **Fork Tree**:

```
Official Shooter
├── Cat Shooter
│   ├── Cat Shooter EX
│   └── Cat Shooter Online
└── Zombie Shooter
```

社区功能:发布、点赞、收藏、评论、Fork、排行榜。
Fork 在数据上是「DSL 补丁链」,极廉价——这是把 GitHub 的 fork 模型搬到游戏创作上的关键(详见 [05-dsl-design](./05-dsl-design.md))。

## 成功指标

| 阶段 | 用户 | Mod | Fork |
|---|---|---|---|
| MVP | 100 | 1,000 | 500 |
| 第一阶段 | 1,000 | 10,000 | 5,000 |

长期目标:构建一个持续增长的 AI 原生游戏创作与 Fork 生态。

### 指标背后要盯的真实健康度

上面是规模指标,但真正说明「模式成立」的是这几个比率,Phase 1 就要埋点:

- **Fork 转化率**:看到一个游戏的人里,有多少真的 Fork 了它。低 → 「Fork 创作」的冲动不成立。
- **AI 改完发布率**:开始用 AI 改的人里,有多少改到满意并发布。低 → DSL 表达力不够,改不出「我的版本」的感觉。
- **二级 Fork 深度**:Fork Tree 有没有长到第 3、4 层。只有一层 → 社区是「各玩各的」,没有真正的协作演化。

这三个比率比用户数更早告诉你产品成不成。
