# AI 层:Prompt 工程与 DSL 生成

AI 的唯一职责:把自然语言翻译成合法、命中意图、尽量平衡的 DSL 变更。
**永不产出可执行代码。** 输出空间被 Runtime 的 DSL Schema 死死框住。

> 说明:本文描述的 AI 生成能力属于在线服务(后端 `ai` 模块及其 `/ai/*` API,CLI 与 MCP 服务可以调用),已实现并有测试,属于可选组件;当前的主机风格启动器完全在本地运行,没有接入它,启动器里没有 AI 创作入口。产品定位见 [01-vision](./01-vision.md),决策见 [ADR-016](./decisions.md)。

## 调用契约

后端 `POST /ai/mod`(见 [09-api-design](./09-api-design.md)):

```
入:{ runtime: "shooter@1.2.0", current_dsl: {...}, prompt: "把飞机换成猫,再加个喷火Boss" }
出:{ dsl_patch: {...}, new_dsl: {...}, balance_hint?: "...", model, tokens }
```

## 生成流程(后端 ai 模块)

```
1. 取 runtime 的 JSON Schema + 可用枚举清单(sprite/武器/敌人/Boss skill…)
2. 组装 prompt:系统提示 + schema + 当前 DSL + 用户意图
3. 调模型,structured output / tool input_schema 约束输出为合法的 **RFC 6902 JSON Patch 数组**(约束的是 patch 的**格式**)
4. 后端 apply patch 到 current_dsl 得 new_dsl,再用 **DSL JSON Schema 校验 new_dsl**(语义合法性)
     ├─ 通过 → 返回 { dsl_patch, new_dsl }
     └─ 失败 → 有限次重试(把校验错误回灌给模型)→ 仍失败则返回 DSL_INVALID
5. 记录 ai_calls(模型/token/重试/是否通过/成本)
```

> **关键区分(别捆在一起)**:模型用 structured output 只能保证产出的 **patch 格式合法**(是个合规的 6902 数组)。它**不能**保证「apply 之后的 DSL 合法」——因为 DSL JSON Schema 约束的是完整 DSL 文档,不是 patch。所以语义合法性必须靠后端**先 apply 再用 DSL schema 校验 new_dsl**。两步是两件事。

## 系统提示设计要点

- **角色**:你是 Classic Games 的游戏改造助手,只能输出对游戏配置(DSL)的修改。
- **硬约束**:
  - 只能用提供的枚举值(列出 sprite/武器/敌人/Boss skill 等可用 key);用户说的东西若没有对应枚举,选最接近的并在 `balance_hint` 说明,**不得编造 key**。
  - 数值必须在 schema 范围内。
  - 输出 **JSON Patch**(只描述「改哪里」),不要整份重写——省 token、降改错率、便于 apply 到补丁链。
  - 绝不输出代码、脚本、自然语言解释(解释放 `balance_hint` 字段)。
- **意图映射示例**(few-shot):喂几个「自然语言 → JSON Patch」的例子,覆盖换素材、加敌人、调难度、加 Boss 等典型操作。

## 为什么用 JSON Patch 精确定位

大 DSL 里改一处,两种做法:

| 做法 | token | 改错率 | 对 Fork 链 |
|---|---|---|---|
| 整份重写 DSL | 高(整份进出) | 高(易动到不该动的) | 难 diff |
| **JSON Patch(只描述变更)** | 低 | 低 | 天然就是补丁,便于复用入库 |

选 JSON Patch(RFC 6902,见 [ADR-013](./decisions.md))。它同时解决了成本和准确率。
**但 AI 返回的 `dsl_patch` ≠ 入库的 `mods.patch`**:前者相对本轮 `current_dsl`(可能是草稿的当前全量),后者相对**父 mod 的生效 DSL**。多轮 AI 改同一草稿时,每轮各自返回相对当时全量的 `dsl_patch`;只有 publish 那一刻,才把最终 `new_dsl` 与父 mod 生效 DSL 做一次 diff,得到单条入库 `mods.patch`([10-data-model](./10-data-model.md))。
(待 spike 验证模型产出 6902 patch 的稳定性;若不稳,退回「整份重写 + 后端 diff」,见 ADR-006。)

## 枚举不命中怎么办

用户说「换成皮卡丘」,但资源库没有 pikachu sprite:

- **不编造**。从现有枚举选最接近的(如 `cat` 或某黄色小动物),并在 `balance_hint` 告知「资源库暂无皮卡丘,已用 X 代替」。
- 收集这类未命中意图 → 反哺 [11-runtime-content](./11-runtime-content.md) 的内容扩充优先级(用户最想要什么素材,数据会告诉你)。

## 平衡性提示

- Schema 范围挡极端值是第一道防线。
- 模型可在生成后附 `balance_hint`(非阻断):如「玩家 hp 拉满 + 敌人极少,会很无聊」。
- Phase 3 的「AI 自动平衡」从这个提示升级为自动调参,Phase 1 不做。

## 评测集(必须早建)

把「AI 改 DSL」的质量量化,否则换模型/调 prompt 全凭感觉:

- **构造 50+ 条真实意图**(覆盖换素材、调数值、加敌人、加 Boss、组合指令、刁钻表述)。
- 每条标注「期望命中的字段/枚举」。
- 指标:**合法率**(输出过 schema 校验)、**意图命中率**(改对了地方)、**平均 token**、**平均重试次数**。
- 作为回归基准:换模型、改 prompt、升级 schema 后跑一遍,防退化。
- 这也是 [06-challenges](./06-challenges.md) §F「AI 输出可靠性」的落地抓手。

## 模型路由与成本

- 简单改动(换 sprite、调一个数值)用便宜/快模型;复杂组合指令用强模型。
- `LLMProvider` 抽象屏蔽供应商([04-architecture](./04-architecture.md));Phase 1 先直连 Claude 跑通,稳定后接统一网关。
- 限流 + 配额在 [08-deployment](./08-deployment.md) / [14-security-compliance](./14-security-compliance.md)。

## 安全边界

- AI 输出只进 DSL 校验管线,**绝不进 eval / 代码执行**。
- prompt 注入防护:用户 prompt 当数据,不当指令;系统提示不可被用户覆盖;输出只接受 schema 内的 JSON Patch,任何 schema 外内容一律丢弃。
- 生成内容(尤其文字类,如 AI 起的游戏名)进内容审核([14](./14-security-compliance.md))。
