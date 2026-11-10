# API 设计

后端(Go)对客户端暴露的 HTTP 契约。契约与栈无关,栈选型见 [ADR-011](./decisions.md)。
草案,随实现细化;原则是「客户端只发自然语言 + 当前 DSL,业务和 AI 都在后端」。

> **在线 Swagger / OpenAPI**:服务已集成 swaggo,实现处当前用注解生成 47 个 operation；规范覆盖仍在补齐，未注解路由以本设计文档和实现为准。
> 起服务后:Swagger UI 在 `GET /swagger/index.html`,机器可读规范在 `GET /swagger/doc.json`。
> 注解改动后用 `cd apps/server && swag init -g cmd/server/main.go -o docs --parseDependency --parseInternal` 重新生成(产物 `apps/server/docs/`)。本 markdown 仍是设计层叙述,Swagger 是实现层契约,二者并存。

## 约定

- 基址:`/api/v1`
- 认证:除登录类外均需 `Authorization: Bearer <token>`
- 编码:JSON,UTF-8;时间用 ISO 8601;ID 用字符串
- 错误:统一信封 `{ "error": { "code": "...", "message": "...", "details": {} } }`,HTTP 状态码语义化
- 分页:游标式 `?cursor=...&limit=20`,返回 `{ items, next_cursor }`(适配虚拟列表)
- 幂等:写接口支持 `Idempotency-Key` 头(发布、支付等)

## 认证 `auth`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/sms/send` | 发送手机验证码(限流) |
| POST | `/auth/sms/verify` | 验证码登录,未注册自动建号,返回 token |
| POST | `/auth/oauth/:provider` | 第三方登录(wechat/apple/google…) |
| POST | `/auth/refresh` | 刷新 token |
| POST | `/auth/logout` | 退出 |
| POST | `/auth/realname` | 实名认证(合规) |

## 用户 `users`

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/users/me` | 当前用户资料 + 创作点 + 等级 |
| PATCH | `/users/me` | 编辑资料(昵称/简介/头像/地区) |
| GET | `/users/:id` | 公开主页 |
| GET | `/users/:id/games` | 某用户的作品 |
| POST | `/users/:id/follow` / DELETE | 关注 / 取关 |
| GET | `/users/:id/followers` `/following` | 粉丝 / 关注列表 |

## 游戏与 Mod `games` / `mods`

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/games` | 列表,支持 `?q=&sort=hot\|rising\|new&runtime=shooter&cat/category=&ai=true\|false` 组合筛选与游标分页 |
| GET | `/games/:id` | 详情:元数据 + 生效 DSL 引用 + 统计 + 创作链 |
| GET | `/games/:id/dsl` | 取某游戏的**生效 DSL**(基线 + 补丁链 apply 后的结果) |
| POST | `/games` | 发布:用某 Mod(生效 DSL)创建一个游戏作品,进审核 |
| GET | `/runtimes/:name/:version/schema` | 取 Runtime 的 DSL JSON Schema(客户端校验、AI 约束用) |
| GET | `/runtimes/:name/:version/baseline` | 取 Runtime 基线 DSL |

## Fork `forks`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/games/:id/fork` | Fork:以目标生效 DSL 为起点创建草稿,返回新草稿 id |
| GET | `/games/:id/fork-tree` | Fork Tree(祖先链 + 直接子节点) |
| GET | `/games/:id/lineage` | 创作链(根→当前的路径) |

> **已实现的底层(mod 级)**:Fork 模型先在 mod 层落地(`apps/server/internal/mods`),games 层是其包装:
> - `POST /api/v1/mods`(`{runtime, parent_id?, patch}`)— 建根 / 子 mod
> - `POST /api/v1/mods/:id/fork` — Fork 出空补丁草稿
> - `GET /api/v1/mods/:id/dsl` — 生效 DSL(基线 + 补丁链)
>
> games 级端点(发布、fork-tree、lineage)在 games 域接入后包装这些。

## AI 创作 `ai`(核心)

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/ai/mod` | **核心接口**。入参 `{ runtime, current_dsl, prompt }`,出参 `{ dsl_patch, new_dsl, balance_hint?, model, tokens }`。后端调模型 → schema 约束 → 校验 → 返回 |
| POST | `/ai/balance` | 自动平衡。入参 `{ runtime, current_dsl, target_difficulty:1..5 }`，返回多参数 `dsl_patch`、`new_dsl` 与前后压力指标 |
| POST | `/ai/structure` | 结构生成。入参 `{ runtime, current_dsl, prompt, count:1..8, difficulty:1..5 }`，向 enemies/waves map 追加稳定且不覆盖的结构节点 |
| POST | `/ai/validate` | 仅校验一份 DSL 是否合法(供客户端预检) |

`POST /ai/mod` 行为细节见 [12-ai-prompt](./12-ai-prompt.md):structured output 强制 schema、失败有限重试、用 JSON Patch 精确定位修改以省 token。

## 草稿与发布

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/drafts` | 我的草稿(未发布的 Mod) |
| PUT | `/drafts/:id` | 以当前草稿为父保存不可变新版本（body 为 RFC 6902 `patch`） |
| POST | `/drafts/:id/publish` | 提交发布(封面/名称/简介/标签/定价)→ 审核队列 |

## 社交 `social`

| 方法 | 路径 | 说明 |
|---|---|---|
| GET/POST | `/games/:id/comments` | 评论列表 / 发评论 |
| POST | `/games/:id/like` / DELETE | 点赞 / 取消 |
| POST | `/games/:id/favorite` / DELETE | 收藏 / 取消 |
| GET | `/messages/conversations` | 私信会话列表 |
| GET/POST | `/messages/:conversationId` | 拉取 / 发送私信 |

## 排行榜 `ranking`

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/ranking?type=hot\|rising\|new&runtime=...` | 榜单,带名次与排名变化 |

## 审核与举报 `moderation`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/report` | 举报游戏/评论/用户(带理由) |
| POST | `/block/:userId` / DELETE | 屏蔽 / 取消 |
| GET | `/blocks` | 我的黑名单(已屏蔽用户列表) |
| POST | `/games/:id/decision` (admin) | 审核裁决:reviewing → published/rejected(当前实现按 game id,在 games 域)|
| GET | `/moderation/queue` (admin) | 审核队列，仅返回 `reviewing` 作品，游标分页；复用 games 审核状态机 |

## 错误码约定(节选)

| code | 含义 |
|---|---|
| `AUTH_REQUIRED` / `AUTH_INVALID` | 未登录 / token 失效 |
| `RATE_LIMITED` | 触发限流(短信、AI) |
| `QUOTA_EXCEEDED` | AI 配额用尽 |
| `DSL_INVALID` | DSL 校验失败 |
| `GAME_HAS_NO_MOD` | 作品存在但背后没有 mod(开发环境预置的展示作品),`/games/:id/dsl`、`/lineage`、`/fork-tree`、`/fork` 对它返回此码;HTTP 状态是 404 |
| `RUNTIME_VERSION_MISMATCH` | Mod 的 runtime 版本与请求不兼容 |
| `MODERATION_PENDING` / `REJECTED` | 内容审核中 / 被拒 |
