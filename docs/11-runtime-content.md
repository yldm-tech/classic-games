# Shooter Runtime 内容清单

> **这是 Phase 1 真正的工作量。** [05-dsl-design](./05-dsl-design.md) 已论证:用户的创造边界 = Runtime 预埋的素材与机制枚举数量。DSL 的语法是死的,这份清单才决定「用户能不能改出有创造感的版本」。本文档列出 Shooter Runtime(`shooter@1.0.0`)预埋的内容,权威定义是 [`packages/schemas/shooter-1.0.0.schema.json`](../packages/schemas/shooter-1.0.0.schema.json),两者不一致时以 schema 为准。Survivor 与 Tower Defense 的内容目前只记录在各自的 schema 里([`survivor-1.0.0`](../packages/schemas/survivor-1.0.0.schema.json)、[`tower_defense-1.0.0`](../packages/schemas/tower_defense-1.0.0.schema.json)),本文档不覆盖。

本文只适用于由 DSL 配置的内置运行时(`apps/client/runtime/`)。启动器里的每款游戏,包括运行在这三个运行时上的三款,都由 `apps/client/games/<id>/game.json` 描述(名称、成就、玩法说明、操作表、HUD、开局选项);不经 DSL、自带代码的游戏是游戏模块,它们的内容在各自的目录里,契约见 [20-adding-a-game](./20-adding-a-game.md),不在这份清单里。

## 设计目标

- **少而精,且高度可组合**。不是堆数量,是让有限元素的组合产生足够多样的结果。
- 每个可改维度都要有「肉眼可见的差异」——换了武器、换了 Boss,玩起来明显不同,用户才有「这是我的版本」的感觉。
- 所有枚举值都对应一个真实的 Godot 实现(sprite/逻辑),AI 只能从这些 key 里选,不能凭空造。

## 1. 玩家(player)

| 维度 | 类型 | 第一版预埋 |
|---|---|---|
| sprite | 枚举 | plane(默认)、cat、ufo、dragon、tank、ghost(≥6) |
| hp | 数值 [1,999] | 默认 100 |
| speed | 数值 [1,30] | 默认 10 |
| size | 数值 [0.5,2.0] | 碰撞体与表现缩放 |

## 2. 武器(weapon)

武器是「差异感」最强的维度,第一版要给足:

| type(枚举) | 行为特征 | 可调数值 |
|---|---|---|
| straight | 直线单发 | damage, fire_rate |
| spread | 散射(扇形多发) | damage, fire_rate, bullet_count |
| laser | 持续激光 | damage, width |
| missile | 追踪导弹 | damage, fire_rate, turn_rate |
| boomerang | 回旋镖(往返) | damage, range |
| orbit | 环绕弹(护体) | damage, orbit_count |

共享数值:`damage [1,200]`、`fire_rate [1,20]`、`bullet_count [1,12]`。

## 3. 敌人(enemies,以稳定 id 为 key 的 map)

| type(枚举) | behavior(枚举) | 可调数值 |
|---|---|---|
| dog | chase(追玩家) | count, hp, speed |
| bird | sine(正弦飘飞) | count, hp, speed |
| turret | static(固定射击) | count, hp, fire_rate |
| bomber | dive(俯冲) | count, hp, speed |
| swarm | flock(群聚) | count, hp |

`enemies` 的每个 key 是一个稳定 id(`^[a-z0-9_]{1,32}$`),值是一组同类敌人;补丁按 `/enemies/<id>/...` 定位,理由见 [decisions ADR-013](./decisions.md)。

behavior 与 type 解耦:同一个 sprite 配不同 behavior 就是不同体验。

Shooter 没有波次结构:每个条目在开局按 `count` 一次生成,血量与速度按 `stage.difficulty` 缩放。结构化的波次序列(`waves`,同样是以稳定 id 为 key 的 map)在 Survivor 与 Tower Defense 的 schema 里,见 [decisions](./decisions.md) 的 OPEN-2。

## 4. Boss

| 维度 | 类型 | 第一版预埋 |
|---|---|---|
| enabled | 开关 | |
| sprite | 枚举 | godzilla、kraken、mecha、demon、worm(≥5) |
| skill | 枚举 | fireball、laser_sweep、summon_minions、bullet_hell、charge(≥5) |
| hp | 数值 [100,9999] | |
| phase_count | 数值 [1,3] | 阶段数(血量分段换招) |

## 5. 掉落(drops,以稳定 id 为 key 的 map)

| type(枚举) | 效果 | 可调 |
|---|---|---|
| heal | 回血 | rate(掉率) |
| shield | 临时护盾 | rate |
| power | 武器强化 | rate |
| coin | 创作点/分数 | rate |
| bomb | 清屏 | rate |

`rate ∈ [0,1]`。

## 6. 全局(stage)

| 维度 | 类型 | 第一版预埋 |
|---|---|---|
| background | 枚举 | space、city、ocean、lava、forest |
| bgm | 字符串 key(可省) | 任意 key,不设枚举;由 `apps/client/runtime/shooter/procedural_bgm.gd` 按 key 程序化合成,基线用 `ignition` |
| difficulty | 数值 [1,5] | 整体难度系数(影响敌人血量/速度缩放) |
| duration | 数值 [30,300] | 单局时长(秒) |

## 组合空间估算

即便第一版,组合空间已经很大:
6 player sprite × 6 武器 × (5 敌人 × 5 行为) × (5 Boss sprite × 5 skill) × 5 背景 …
**数量不是问题,关键是每个维度的差异要「玩起来明显」**。这是内容设计和手感打磨的活,不是填表的活。

## 与 DSL Schema 的对应

本清单的每一行 = `runtimes.schema`(见 [10-data-model](./10-data-model.md))里的一个字段定义:

- 枚举维度 → schema 的 `enum` 列表
- 数值维度 → schema 的 `minimum`/`maximum`
- 开关 → `boolean`
- 字符串 key(只有 `stage.bgm`) → 不带 `enum` 的 `string`,是三类之外的例外,见 [05-dsl-design](./05-dsl-design.md) 的字段原则

清单一变,schema 和 Godot 实现要同步——这是「修改共享契约」,做广度扫描([05](./05-dsl-design.md) §Schema 即契约)。

## 验收标准

- 每个枚举值在 Godot 里都有可玩实现,不是占位。
- 随机抽 10 组合法 DSL,玩起来彼此**明显不同**(主观但要团队达成共识)。
- AI 用 50 条真实意图测试,能把意图映射到这些枚举/数值上的命中率达标(见 [12-ai-prompt](./12-ai-prompt.md))。
