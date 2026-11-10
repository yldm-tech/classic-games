# 部署与运维

## 总览

本文描述的是目标部署形态,其中一部分还没有实现。当前代码的实际状态:

- **数据库只支持 SQLite。** 后端只链接了 `github.com/ncruces/go-sqlite3/gormlite` 一个驱动,`FORGEPLAY_DB` 的值是 SQLite 文件路径(不设时用工作目录下的 `forgeplay.db`;`FORGEPLAY_ENV=production` 时必须显式设置)。填 PostgreSQL DSN 会在启动时打开数据库失败。SQLite 是单文件数据库,所以下文的「无状态、可水平扩展」要等 PostgreSQL 驱动接入后才成立。
- **没有对象存储。** 后端没有 S3/MinIO 相关代码,也没有对应的环境变量;封面等素材目前随客户端工程分发。
- **模型 provider 只有一个。** `apps/server/internal/ai` 里只有 `ClaudeProvider` 和无 API key 时使用的 `StubProvider`([ADR-008](./decisions.md))。

| 组件 | 目标部署形态 | 当前状态 |
|---|---|---|
| 后端 Go | 单二进制容器化,跑在云服务器 / K8s,水平扩展 | 单二进制可构建;镜像与部署流水线未建 |
| 数据库 | PostgreSQL:托管实例(云 RDS)或自建主从,定期备份 | 尚未实现,只支持 SQLite 文件 |
| 对象存储 | 生产用云 S3;开发/自建用 MinIO(同一 S3 API) | 尚未实现 |
| AI | 后端经 LLMProvider 调外部模型 API;key 仅在后端 | 已实现,只接了 Claude |
| 客户端 | Godot 一套工程,导出 5 端,各走对应分发渠道 | 五个导出预设已配置,真机验证见 [07-roadmap](./07-roadmap.md) |

## 后端部署

- **容器化**:Go 编译成单二进制,打多阶段 Docker 镜像(scratch/distroless),无状态,可水平扩。
- **配置**:全部走环境变量,不硬编码、不进仓库;现有变量的完整清单见 [`.env.example`](../.env.example)(数据库文件路径 `FORGEPLAY_DB`、服务端密钥 `FORGEPLAY_SECRET`、模型 API key、短信 / 第三方登录 / 内容审核网关等)。对象存储的变量要等对象存储实现后才会有。
- **数据库迁移**:`apps/server/internal/app/migrations.go` 持有唯一有序 migration registry；应用在注册路由前集中执行 GORM `AutoMigrate`，仓储和业务 package 禁止自行迁移。跨版本变更以稳定 migration ID 追加，不在旧项上原地改写。
- **环境**:dev / staging / prod 三套,staging 与 prod 同构。
- **关键中间件**:
  - **限流 + 配额**:AI 接口必须限流(防滥用、控成本),按用户配额(免费额度 + 充值/广告补充)。
  - **审核队列**:AI 生成内容 + 用户发布的 Mod 进异步审核队列(`moderation`)。

## CI/CD

当前仓库里的自动化只有门禁,没有发布流水线:`.github/workflows/ci.yml` 在 push / PR 到 main 时跑四个 job——后端(`apps/server` 的 vet + test)、Go 模块(`packages/dsl`、`packages/sdk`、`apps/cli`、`apps/mcp` 的格式、tidy、vet、test 与编译,workspace 和 `GOWORK=off` 各一遍)、官网(`apps/web` 的类型检查、构建与断链检查)、Godot headless。镜像构建、部署、客户端导出签名、CLI/MCP 二进制发布和官网托管都还没有对应的 workflow;下面是目标形态。

- **后端**:push → CI 跑 lint + 测试 + 构建镜像 → 部署 staging → 验收 → 上 prod。后端镜像的构建上下文需要同时包含 `apps/server` 与 `packages/dsl`(后端经相对路径 `replace` 引用它),运行时还要带上 `packages/schemas` 和 `apps/client/runtime` 下的 baseline,并用 `FORGEPLAY_SCHEMA_DIR`、`FORGEPLAY_RUNTIME_DIR`、`FORGEPLAY_BASELINE` 等环境变量指向它们(默认值是相对 `apps/server` 的开发路径)。
- **CLI 与 MCP 服务**:`make cli-build` / `make mcp-build` 产出单个二进制。它们离线校验时需要磁盘上的 schema 目录,脱离仓库检出分发时要一并带上 `packages/schemas` 并设置 `FORGEPLAY_SCHEMA_DIR`。
- **官网**:`make web-build` 产出纯静态站点(`apps/web/dist`),可放任意静态托管;站点地址用 `SITE_URL` 配置,目前只支持部署在域名根路径。
- **客户端(Godot)**:
  - 用 Godot 的**命令行 headless 导出**,在 CI 里一键导出 5 端产物。
  - 各端签名/打包:iOS(证书 + provisioning)、Android(keystore)、macOS(公证 notarization)、Windows(代码签名)、Web(静态托管)。
  - **关键约定**:不要多 worktree / 多任务同时本地编译导出,易争抢资源超时;导出走 CI。

## 客户端分发(5 端)

| 平台 | 渠道 | 注意 |
|---|---|---|
| iOS | App Store | 审核严;游戏引擎包体大、启动慢需优化;产品明确不提供手机端支付/内购 |
| Android | Google Play + 国内各应用商店 | 国内多渠道打包;产品明确不提供手机端支付/内购 |
| macOS | App Store / 官网 DMG | 需公证(notarization) |
| Windows | 官网安装包 / Steam(可选) | 代码签名避免 SmartScreen 拦截 |
| Web | 静态托管 + CDN | 「点链接即玩」第二落点;WASM 包体与首屏加载要优化 |

### Runtime 与资源的下发

- **Runtime 包**和 **Mod DSL** 都**发版化**(见 [05-dsl-design](./05-dsl-design.md)):客户端按 `runtime: "shooter@1.2.0"` 拉对应 Runtime 资源 + DSL。
- 资源(sprite/音效/封面)走 S3 + CDN,客户端按稳定 key 拉取、本地缓存(目标形态;对象存储尚未实现,见总览)。
- 这样**新增 Runtime 内容、调整 DSL,无需重新过商店审核**(数据下发,非客户端二进制变更)——这是「Runtime 数据驱动」架构的运维红利。客户端二进制只在引擎/Shell 本身变更时才发版。

## 监控与可观测性

- **后端**:日志聚合 + APM(请求延迟、错误率)、DB 慢查询、队列积压。
- **AI 专项**:每次调用记录模型、token 数、耗时、校验是否通过、重试次数、单次成本 → 用于成本核算和模型路由决策。
- **DSL 健康度**:AI 输出**合法率**、校验失败率、平衡性提示分布,作为 [06-challenges](./06-challenges.md) §F 的回归基准。
- **产品指标**:Fork 转化率、AI 改完发布率、二级 Fork 深度(见 [01-vision](./01-vision.md)),进数据看板。
- **客户端**:崩溃上报(各端)、性能(尤其虚拟列表 FPS、游戏帧率)、关键漏斗埋点。

## 安全与合规要点

- 模型 API key、S3 凭证、DB 密码只在后端,绝不进客户端或仓库。
- 用户内容(Mod、评论、上传素材)双重审核:AI 预审 + 人工/规则兜底。
- 实名、青少年模式(时长/宵禁/内容过滤)作为一等功能落地,非事后补丁。
- 数据备份:DB 定期快照 + 异地;S3 版本化。

## 环境与成本控制清单

- AI 调用:限流 + 配额 + 按复杂度路由模型(简单改动用便宜模型)+ 精确定位修改省 token。
- 对象存储:CDN 缓存热门资源,降回源。
- 数据库:Fork Tree 查询若成热点,加缓存或升级存储结构(闭包表/ltree)。
- 客户端包体:Godot 导出做资源裁剪,控制启动时间(影响「即点即玩」)。
