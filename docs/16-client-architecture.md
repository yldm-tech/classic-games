# 客户端架构（Godot）

更新时间：2026-08-08
状态：七个 feature 切片与单一组合根已完成

## 1. 目录与依赖方向

```text
apps/client/
├── main.gd                         # 创建 AppRoot
├── app/
│   ├── app_root.gd                 # composition root，只装配
│   ├── screen_registry.gd          # screen 生命周期/查找
│   └── chrome/chrome_controller.gd # 全局 chrome
├── core/http/
│   ├── api_result.gd               # 统一结果类型
│   └── http_client.gd              # transport-only
├── features/
│   ├── identity/                   # 认证与 session
│   ├── catalog/                    # 发现、搜索、详情、资料
│   ├── creation/                   # AI、mod、草稿、发布
│   ├── community/                  # 评论、收藏、关系、消息
│   ├── engagement/                 # 下载、历史、房间、回放
│   ├── commerce/                   # 积分、会员、活动、支付
│   └── operations/                 # 账号、偏好、举报、反馈
├── shell/                          # 设计 token、路由、全局/创作会话工具
├── runtime/                        # 独立游戏运行时
├── platform/                       # 原生能力端口
└── ui/                             # 无业务 components 与 patterns
```

允许的依赖方向：

```text
main → app → features → core
              │
              ├── ui
              ├── platform ports
              └── GameSession
```

`core` 不依赖 feature；feature 的 endpoint 只属于本域 `*_api.gd`；feature 不能 import 另一 feature 的 screen。`scripts/check-client-boundaries.sh` 与 `scripts/check-architecture.sh` 在本地和 CI 中检查这些规则。

## 2. Feature 标准形态

每个 feature 由四种角色组成：

- `*_screen.gd`：渲染 store，发出用户意图；不知道 URL、token 和原始 HTTP 字典。
- `*_coordinator.gd`：执行用例、并发保护、错误策略和跨端口编排。
- `*_store.gd`：持有页面/领域状态，以 signal 通知 UI；不执行 I/O。
- `*_api.gd`：拥有 endpoint、请求/响应 DTO 映射，返回 `ApiResult`。

一次操作只有一个方向：

```text
screen intent → coordinator → gateway → ApiResult → store → screen
```

七个现有切片共同构成参考实现。新增 feature 应复制角色边界，不复制业务代码，也不能借用相邻域的 store、screen 或 gateway。

## 3. HTTP 与错误

`HttpClient` 是唯一 transport 实现，负责：

- bearer token 注入；
- JSON 编解码与公共响应信封；
- offline、unauthorized、validation、conflict、rate-limited、unexpected 分类；
- 返回 `ApiResult`，不操作 store 或 UI。

Feature API 提供业务方法并拥有 URL。Coordinator 根据 `ApiResult.kind` 决定重试、登录跳转、页面错误或 toast。Screen 只显示已经归一化的状态。

## 4. 应用根与导航

`AppRoot` 只做依赖构造、全局信号接线和 feature 生命周期管理。`ScreenRegistry` 负责注册/创建 screen；`ChromeController` 管理顶栏、底栏、toast 与全局遮罩。业务查询、提交和 DTO 组装不得回流到这三个对象。

`AppRoot` 是唯一应用组合根，构造 feature API/store/coordinator/screen，连接稳定的意图与状态信号，并持有 account-scoped transport 图。注销或换号时先推进 session epoch 和阻断旧提交，再取消旧请求；节点图延迟到当前 signal/coroutine 栈退出后销毁和重建，避免释放正在执行的按钮、screen 或 coordinator。

## 5. 状态所有权

- 跨 feature 只共享认证会话、locale、theme、全局未读等真正全局状态。
- 列表、详情、草稿、订单等数据归各自 feature store。
- 跨 feature 传稳定 ID 或不可变快照，不共享具体 screen 节点和可变 Dictionary 引用。
- Coordinator 负责重复提交抑制和取消/过期响应处理；不得用任意 timeout 修复竞态。

## 6. 公共 UI

公共 UI 分三层：

| 层 | 内容 | 禁止内容 |
|---|---|---|
| theme | color/type/spacing/radius token、Theme | 业务状态 |
| components | Button、Card、Input、VirtualList | game/order/user 语义 |
| patterns | AsyncContent、EmptyState、PagedList、ConfirmSheet | endpoint 与用例 |

组件只有在至少两个 feature 中真实复用后提取。页面专用控件先留在 feature 内，避免预先抽象。

## 7. Runtime 边界

Shell 与 Runtime 只通过 `runtime/game_session.gd` 通信。Shell 传 runtime ref 与完整有效 DSL；Runtime 发 `game_ended`/`game_error`。双方禁止读取对方内部节点、状态或文件。

Runtime 目录同时是仓库里其他部分的数据来源：`runtime/<name>/baseline.dsl.json` 是后端注册的基线，`runtime/shooter/testdata/fork_expected.dsl.json` 是客户端 `runtime/json_patch.gd` 与 Go 模块 `packages/dsl` 共用的 golden。两份补丁实现、两份迁移实现（`runtime/dsl_migrations.gd` 与 `packages/dsl/migrate.go`）必须同语义，改其中一侧时另一侧、两边的测试和共用的夹具要在同一个 PR 里一起改。对应的 schema 在 `packages/schemas`。

## 8. 完成态不变量

- Godot 4.6.3 精确版本门禁和 fail-closed test runner；
- transport-only `HttpClient` 与统一 `ApiResult`；
- 七域 API/store/coordinator/screen 所有权；
- `AppRoot`、`ScreenRegistry`、`ChromeController` 单一装配与导航路径；
- account session epoch、旧请求取消、全域 cache 清理和延迟依赖图重建；
- AsyncContent、EmptyState、PagedList、ConfirmSheet 等无业务共享 pattern；
- 仓库级 fixture checker 拒绝旧入口、endpoint/transport 越界和跨 feature screen import。
