# Mod DSL 设计(核心赌注)

> 说明:本文是在「Fork + AI 改游戏」的早期定位下写的,DSL 的结构、补丁语义与版本治理仍是现行契约(`packages/schemas`、`packages/dsl` 与客户端 `runtime/`)。当前的主机风格启动器只在本地运行各 Runtime 的基线 DSL,没有 Fork、AI 改造和发布的入口;这些流程由在线服务的 API 以及 CLI、MCP 服务提供,已实现并有测试,属于可选组件,启动器没有接入。产品定位见 [01-vision](./01-vision.md),决策见 [ADR-016](./decisions.md)。

> **这是整个产品的成败所在。** 引擎、后端、UI 都是工程问题,可估工、可解决。
> 唯一可能「做出来但没人用」的地方,是 DSL 设计失衡。本文档需要在 spike 后持续深化。

## 为什么 DSL 是核心赌注

产品价值押在一对矛盾的平衡上:

- **DSL 太「死」**(只能改 hp / sprite / 数量)→ 用户 Fork 出来的东西「都差不多」,没有创造感,Roblox 那种「这是我的游戏」的成就感出不来。飞轮转不起来。
- **DSL 太「活」**(能描述新机制、新关卡逻辑)→ AI 生成的 JSON 经常非法 / 不平衡 / 跑不起来,Runtime 接不住,体验崩。

整个团队的核心工程目标,就是为每个 Runtime 找到这条平衡线。

## 关键认知:用户的创造边界 = Runtime 预埋的枚举数量

看原始设计的两个例子:

```
「把飞机换成猫」      → { "player": { "sprite": "cat" } }
「加一个会喷火的 Boss」 → { "boss": { "enabled": true, "skill": "fireball" } }
```

两个都是**枚举型替换**:`cat` 必须是资源库里已有的 sprite,`fireball` 必须是 Runtime 里**预先实现好**的技能。
这意味着:

> **用户能创造的上限 = 你在 Runtime 里预埋的素材和机制数量。**

这跟「无需编程即可创造游戏」的愿景之间有张力,必须正视:
Classic Games 给的不是「无限自由」,而是「在一个精心设计的可能性空间里自由组合」。
这个空间够大、组合够多样,用户就有创造感;预埋太少,就是换皮工具。

**推论:Phase 1 真正的工作量,是 Shooter Runtime 里预埋多少种武器/敌人/Boss 技能/掉落,以及它们能怎样组合。** 这个「内容清单」比 DSL 的语法更决定成败,且原始文档完全没写——是 Phase 1 必须先定的东西。

## DSL 结构(Shooter Runtime)

> 权威 schema 实体:[`packages/schemas/shooter-1.0.0.schema.json`](../packages/schemas/shooter-1.0.0.schema.json)。
> 下面的示例必须与它、以及 [11-runtime-content](./11-runtime-content.md) 的枚举清单**逐一对齐**(三者是同一契约的三种表述)。
> 原则:**字段分三类** —— 枚举(从预埋集选)、数值(带范围约束)、开关(布尔)。AI 的输出空间主要由这三类框住。现有 schema 里的例外只有几处:`meta` 下的簿记字段(`runtime_version`、`fork_of`);按 id 引用同一份 DSL 里其他条目的字段(Tower Defense 的 `placements.<id>.tower`);有长度上限的列表(Tower Defense 的 `path.points`、Survivor 的 `progression.upgrades`);以及 Shooter 的 `stage.bgm`,它是不设枚举的字符串,Runtime 只把它当作程序化合成 BGM 的种子(见 [11-runtime-content](./11-runtime-content.md) §6)。新增字段不应再扩大这份例外清单。

**关键结构决策**:`enemies` / `drops` 不是匿名数组,而是**以稳定 id 为 key 的对象(map)**。
原因见下文「Fork 模型」与 [decisions ADR-013](./decisions.md):数组下标在补丁链里不稳定(头部插入会让既有 `/enemies/0` patch 全部错位),map 的 key 让 RFC 6902 路径 `/enemies/<id>/count` 永远稳定,AI 也能按 id 精确引用某个敌人。

```jsonc
{
  "meta": {
    "runtime": "shooter",
    "runtime_version": "1.0.0",    // 必填,版本治理基础
    "fork_of": "mod_abc123"        // 可空,Fork 来源
  },
  "player": {
    "sprite": "cat",               // 枚举:plane/cat/ufo/dragon/tank/ghost
    "hp": 100,                     // 数值:范围 [1, 999]
    "speed": 10,                   // 数值:范围 [1, 30]
    "weapon": {                    // 按 type 分支(见 schema 的 oneOf)
      "type": "laser",             // 枚举:straight/spread/laser/missile/boomerang/orbit
      "damage": 20,                // 共享数值:范围 [1, 200]
      "width": 1.5                 // laser 专属字段(missile→turn_rate / orbit→orbit_count / spread→bullet_count …)
    }
  },
  "enemies": {                     // map,key = 稳定 id
    "dog_1": {
      "type": "dog",               // 枚举:dog/bird/turret/bomber/swarm
      "behavior": "chase",         // 枚举:chase/sine/static/dive/flock(与 type 解耦)
      "count": 20,                 // 数值:范围 [1, 200]
      "hp": 30,
      "speed": 8                   // 移动型用;turret 改用 fire_rate
    }
  },
  "boss": {
    "enabled": true,               // 开关
    "sprite": "godzilla",          // 枚举:godzilla/kraken/mecha/demon/worm
    "skill": "fireball",           // 枚举:fireball/laser_sweep/summon_minions/bullet_hell/charge
    "hp": 2000,                    // 数值:范围 [100, 9999]
    "phase_count": 2               // 数值:范围 [1, 3],阶段数
  },
  "drops": {                       // map,key = 稳定 id
    "shield_1": { "type": "shield", "rate": 0.1 }  // 枚举 + 数值 [0,1]
  },
  "stage": {
    "background": "space",         // 枚举:space/city/ocean/lava/forest
    "difficulty": 3,               // 数值:范围 [1, 5]
    "duration": 90                 // 数值:范围 [30, 300] 秒
  }
}
```

### Schema 即契约

每个 Runtime 维护一份 **JSON Schema 实体文件**(Shooter 第一版见 [`packages/schemas/shooter-1.0.0.schema.json`](../packages/schemas/shooter-1.0.0.schema.json)),它同时是三个东西的契约:

1. **AI 输出约束**:喂给模型(structured output / tool input_schema),约束输出格式合法(语义合法性仍需后端 apply 后二次校验,见 [12-ai-prompt](./12-ai-prompt.md) M 区说明)。
2. **后端校验依据**:`ai` 模块和 `mods` 入库前用它校验。
3. **Runtime 加载契约**:`RuntimeLoader` 按它解析。

Schema 改了,三处 + 内容清单([11](./11-runtime-content.md))同步——这是「修改共享契约」,要做广度扫描。
**落地注**:JSON Schema 不支持属性继承,`weapon` 的 oneOf 各分支落地时要把 `type/damage/fire_rate` + 专属字段写全并 `additionalProperties:false`(schema 文件里 `$comment` 已标注)。

## 平衡性

合法 ≠ 好玩。`hp: 999 + damage: 200 + enemy count: 1` 合法但无聊。
AI 职责里有「平衡性建议」,落地为:

- Schema 层面用数值范围挡掉极端值。
- AI 在生成后可附带一个「平衡性评分/提示」(非阻断,给用户参考)。
- Phase 3 目标「AI 自动平衡」,但 Phase 1 先不做,靠范围约束兜底。

## Fork 模型:DSL 补丁链

这是把 GitHub fork 搬到游戏创作的关键,也是 DSL 设计得当带来的红利:

```
Runtime 基线 DSL
  └─ Mod A = 基线 + patch_A
       └─ Mod B(Fork A)= 基线 + patch_A + patch_B
            └─ Mod C(Fork B)= 基线 + patch_A + patch_B + patch_C
```

- 每个 Mod 只存**相对父级的 diff**(JSONB),不存整快照 → Fork 极廉价,Fork Tree 可以很深。
- 生效 DSL = 从 Runtime 基线起,沿父链逐层 apply patch。
- 「创作链」展示(原型里的「《熔岩环道》→ 漂移改版 → 本作 → 你的版本」)天然由这条链得到。

### 补丁语义:RFC 6902 + map 化集合(已定,ADR-013)

补丁合并语义**定为 JSON Patch / RFC 6902**,不用 Merge Patch / RFC 7386。原因:

- 产品核心是「精确定位、省 token、补丁链可叠加」。Merge Patch 对数组只能**整体替换**,无法表达「删某个敌人」「只改第 N 项」——直接让补丁链失效。
- 6902 能精确定位(`add`/`remove`/`replace` + 路径),但它对**数组**用数字下标定位,深 Fork 链下头部插入会让既有下标全部错位。
- 解法:把会增删元素的集合(`enemies`/`drops`)**设计成以稳定 id 为 key 的 map**(见上文 DSL 结构)。这样 6902 路径走 `/enemies/<id>/...`,key 稳定、增删互不影响、AI 可按 id 引用。
- 纯标量/对象字段(player/boss/stage)6902 路径天然稳定,无此问题。

这条决策是 `mods.patch` 入库([10-data-model](./10-data-model.md))、Fork 链 apply、AI 输出([12-ai-prompt](./12-ai-prompt.md))三处共用的地基,必须统一,不能拖到 spike 后。

## Runtime 版本治理(必须 Phase 1 就想清楚)

Mod 依附 Runtime,**官方 Runtime 一升级,存量 Mod 可能集体失效**——这是 NexusMods/模组生态的永恒痛点。规则:

- DSL 必带 `runtime_version`,Mod **pin 到具体版本**。
- Runtime 升级遵循语义化版本:
  - **patch / minor**:向后兼容,旧 DSL 必须照常加载。
  - **major**:允许破坏性变更,但必须提供 **DSL 迁移**(把旧版 DSL 转成新版),不能让存量 Mod 直接死。
- `RuntimeLoader` 加载前校验版本:不兼容且无迁移 → `game_error`,而不是崩溃或乱跑。
- Fork 链跨 Runtime 版本(父用旧、子用新)的处理策略,需在 spike 后定清楚。

不在 Phase 1 立规矩,等到几千个 Mod 时就是灾难。

## 待定 / 开放问题

- ~~补丁合并语义最终选 RFC 7386 还是 6902。~~ **已定:RFC 6902 + map 化集合,见上文与 [ADR-013](./decisions.md)。**
- ~~AI 改 DSL 用 JSON Patch 路径还是整份重写?~~ **已定:JSON Patch(6902),见 [12-ai-prompt](./12-ai-prompt.md);稳定性仍待 spike 验证(ADR-006)。**
- DSL 能否描述「关卡/波次序列」这类结构,还是只能改参数(**表达力天花板,OPEN-2**)。**注意**:Phase 1 只验「参数化」这个弱命题(波次仅「随时间递增 count」,见 [11-runtime-content](./11-runtime-content.md));产品成败其实押在「结构化波次/关卡」这个被绕开的强命题上。弱命题成立**不能**推出产品成立——见 [07-roadmap](./07-roadmap.md) 对此的诚实标注。
- 资源(sprite/音效)如何扩充:只能用官方预埋,还是允许用户/AI 上传?后者打开自由度但引入审核与版权问题(**OPEN-3**)。
