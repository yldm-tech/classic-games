# 数据模型

本文按生产目标 PostgreSQL 描述核心表的字段级设计;[04-architecture](./04-architecture.md) 有概览。当前后端只能打开 SQLite(`gormlite`),表由 GORM `AutoMigrate` 建出,下文的 PostgreSQL 专有类型与 `ltree` 等能力要等 PostgreSQL 驱动接入后才适用。

> 说明:本文描述的是在线服务(账号、Mod 与 Fork、游戏作品、社交、审核、AI 调用审计)的数据模型。在线服务已实现并有测试,属于可选组件;当前的主机风格启动器完全在本地运行,没有接入它,启动器的全部进度保存在本地存档 `user://launcher.json`,不在这些表里。产品定位见 [01-vision](./01-vision.md),决策见 [ADR-016](./decisions.md)。

原则:**DSL 存补丁不存快照**、**Mod 绑 Runtime 版本**、**Fork 用邻接表起步**。

## 实体关系

```
users ──< games >── runtimes
  │         │
  │         └──< mods(补丁链, parent_id 自引用) 
  │                 └── fork: parent_id 指向被 Fork 的 mod
  ├──< comments >── games
  ├──< likes >── games
  ├──< favorites >── games
  └──< follows(关注关系, 自引用 users)
```

「Fork」不是独立表,而是 `mods.parent_id` 这条自引用关系 + `games.forked_from`。
原始设计里的 `forks` 概念在物理上由这两个外键承载。

## 表设计

### users

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid PK | |
| phone | text unique null | 手机号(验证码登录) |
| nickname | text | |
| avatar_url | text | |
| bio | text | |
| region | text | |
| level | int | 创作者等级 |
| credits | bigint | 创作点 |
| realname_status | enum | none/pending/verified(合规) |
| is_minor | bool | 青少年模式 |
| created_at / updated_at | timestamptz | |

### runtimes

早期设想的官方 Runtime 版本登记表,**从未落地**:实际实现是文件式的——schema 取自
[`packages/schemas`](../packages/schemas)(`internal/runtimes`),基线 DSL 由 `internal/mods.MapBaselines`
在启动时从内嵌基线文件灌入(`internal/mods/baselines.go`)。以下字段设计仅作历史参考,
不对应任何 DB 表。

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid PK | |
| name | text | shooter / survivor / td / roguelike |
| version | text | 语义化版本,如 1.2.0 |
| schema | jsonb | 该版本的 DSL JSON Schema |
| baseline_dsl | jsonb | 基线 DSL |
| status | enum | active / deprecated |
| migration_from | text null | 可从哪个旧版本迁移 |
| created_at | timestamptz | |

唯一约束 `(name, version)`。

### mods

创作的核心。每条是相对父级的 DSL 补丁。

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid PK | |
| author_id | uuid FK→users | |
| runtime_name | text | |
| runtime_version | text | **pin 的 Runtime 版本**(版本治理) |
| parent_id | uuid FK→mods null | 父 Mod(Fork 来源);null = 直接基于基线 |
| patch | jsonb | **相对父 mod 生效 DSL 的 RFC 6902 JSON Patch**(见 [ADR-013](./decisions.md));注意与 AI 接口返回的 `dsl_patch`(相对 current_dsl 全量)不是同一个,publish 时由 new_dsl 与父 mod 生效 DSL 做 diff 得入库 patch |
| effective_dsl | jsonb null | 可选:apply 后的生效 DSL 缓存(加速读取,可重算) |
| created_at | timestamptz | |

- 生效 DSL = baseline + 沿 parent 链逐层 apply 6902 patch。`enemies`/`drops` 是 id-keyed map,故路径稳定([05](./05-dsl-design.md))。
- `effective_dsl` 是性能缓存,真相是 `patch` 链。
- **入库 patch ≠ AI 单次 patch**:AI 多轮改同一草稿,调用方拿到的是每轮相对当时全量的 `dsl_patch`;只有 publish 时才把最终 `new_dsl` 与父 mod 生效 DSL 做一次 diff,得到入库的 `mods.patch`(单条、相对父级)。

### games

发布出来的、可被玩/被 Fork 的作品。指向某个定稿 Mod。

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid PK | |
| mod_id | uuid FK→mods | 这个游戏对应的生效 Mod |
| author_id | uuid FK→users | |
| forked_from | uuid FK→games null | Fork 自哪个游戏(Fork Tree 用) |
| title | text | |
| summary | text | 一句话简介 |
| cover_key | text | S3 封面 key |
| tags | text[] | ≤3 |
| price | int | 创作点定价,0=免费 |
| status | enum | draft / reviewing / published / rejected / delisted |
| ai_generated | bool | 是否 AI 参与(合规标识) |
| play_count / fork_count / like_count | bigint | 冗余计数(异步更新) |
| created_at / published_at | timestamptz | |

### Fork Tree 查询

- 起步:`games.forked_from` 邻接表,递归 CTE 查祖先/子树。
- 若成热点:升级 **闭包表** 或 Postgres **`ltree`** 存路径,O(1) 取整条创作链。
- `mods.parent_id` 与 `games.forked_from` 平行存在:前者是 DSL 补丁谱系,后者是发布作品谱系,通常一致但解耦更清晰。

### 社交表

- **comments**: id, game_id, author_id, parent_id(楼中楼 null), content, created_at
- **likes**: (user_id, game_id) 联合唯一, created_at
- **favorites**: (user_id, game_id) 联合唯一, created_at
- **follows**: (follower_id, followee_id) 联合唯一, created_at
- **messages**: id, conversation_id, sender_id, content, created_at;**conversations**: id, participant_ids, last_message_at

### 运营/合规表

- **reports**: id, reporter_id, target_type(game/comment/user), target_id, reason, status
- **blocks**: (user_id, blocked_user_id)
- **moderation_jobs**: id, target_type, target_id, ai_verdict, human_verdict, status, created_at
- **ai_calls**(审计/成本): id, user_id, model, prompt_tokens, completion_tokens, valid, retries, cost, created_at

## 索引要点

- `games(status, runtime_name, published_at)`、榜单相关排序键
- `mods(parent_id)`、`games(forked_from)`(Fork Tree 递归)
- `comments(game_id, created_at)`、`likes(game_id)`
- 计数字段异步更新,避免热点行写争用(用事件/队列累加)

## DSL 存储决策记录

> **决策**:`mods.patch` 存相对父级的 diff,而非整份 DSL 快照。
> **理由**:Fork 链才廉价、Fork Tree 才能深;符合 GitHub fork 心智。
> **代价**:读生效 DSL 要 apply 整条链 → 用 `effective_dsl` 缓存兜底。
> **风险**:补丁合并语义必须确定(固定 RFC 7386 或 6902),否则深链 apply 出歧义。
