# 技术调研

记录关键技术选型的调研过程与依据,便于日后回看「当初为什么这么选」。
最终架构见 [04-architecture](./04-architecture.md);这里是得出结论的推导。

## 1. 客户端:为什么是「全 Godot」

### 约束前提

- 必须支持 **5 端**:iOS、Android、macOS、Windows(+ Web 作为「点链接即玩」的第二落点)。
- 客户端有两类截然不同的职责:**社区 App 壳**(发现/Fork/私聊/编辑器/个人中心)和 **游戏 Runtime**(实时跑动作游戏)。
- 游戏必须在 5 端原生流畅运行。

### 候选方案对比

| 方案 | 游戏视图嵌入 | 5 端覆盖 | 风险性质 |
|---|---|---|---|
| **全 Godot** | 无需嵌入(壳和游戏同引擎) | 原生导出全 5 端,Godot 核心强项 | 坑已知、可估工:IME、虚拟列表、原生集成 |
| Flutter 壳 + 嵌 Godot | platform view,Flutter 最弱环;桌面端嵌入无先例 | Flutter 是唯一全 5 端成熟的跨平台框架 | **桌面嵌入是未知雷,可能掀翻架构** |
| React Native 壳 + 嵌 Godot | 原生视图一等公民,嵌入最顺 | **桌面端(rn-windows/macos)是二等公民,落后核心 RN** | 桌面端持续摩擦 |
| 原生(SwiftUI+Compose+WinUI) | 各端最佳 | 3~4 套 UI 代码 | 小团队维护成本爆炸 |
| 全 Web / PWA 套壳 | webview 跑 WASM | 全覆盖 | 动作游戏移动端性能/发热差 |

### 推导

1. **游戏必须 5 端原生跑 → Godot 被钉死**(它能原生导出全 5 端,是这个能力的唯一一致解)。
2. 一旦 Windows/macOS 是硬要求,**RN 出局**——其桌面端是微软维护的二等项目,长期补窟窿。
3. 剩下「全 Godot」vs「Flutter+嵌入」之争,差别在风险**性质**:
   - 全 Godot 的风险是「重建 App UI 基础设施」——重,但**可估工、不会突然推倒重来**。
   - Flutter+嵌入的风险是「在 5 个宿主上缝合引擎」——其中**桌面端嵌 Godot 没先例,是未知的、会炸的雷**。
4. 平台数越多,「Flutter+嵌入」每端多一处要验证的嵌入,「全 Godot」每端只多一个导出目标。**5 端量级下,全 Godot 的边际成本远低、确定性远高。**

结论:**全 Godot**。唯一能推翻它的变量是中文 IME 输入质量,用 spike 验证(见下与 [07-roadmap](./07-roadmap.md))。

### 关于「全文本项目」这条理由的澄清

原始技术选型里把「Godot 全文本、AI 可操作性强」列为选 Godot 的理由。需要澄清:

- 「全文本」(`.tscn`/`.gd`/`.tres` 都是文本,相对 Unity 的二进制 prefab 更易 diff/merge)是**真实优势**,但它作用在**平台/Runtime 开发层**(官方团队维护 Runtime、Fork Tree 存储、版本管理),不是终端用户创作层。
- 终端用户的 AI 创作流程里,**AI 只产出 DSL(JSON),根本不打开 `.gd`**。所以「全文本」不影响用户侧的 AI 可操作性。
- 正确的表述:选 Godot 的理由是 **5 端原生导出 + 运行时解释 DSL + 开源可控**;「全文本」是 Fork 生态和 Runtime 可维护性的加分,不是「用户靠 AI 创作」那条卖点的支撑。
- 实践推论:用户能创造的边界 = Runtime 里预埋的机制/素材枚举数量,**与 Godot 是否文本无关**。别高估 AI 在用户侧的自由度。

## 2. Godot 做 App UI 的可行性调研

「全 Godot」最大疑虑是「Godot 能不能做内容社交 App 的 UI」。调研结论:能,但有明确的痛点区,需提前知道并预算。详见 [06-challenges](./06-challenges.md),这里给调研要点:

- **CJK 文字渲染**:Godot 用 HarfBuzz,中日文**显示没问题**。
- **中日文 IME 输入**:Godot 4.x 有改善但仍弱于原生,移动端尤甚。这是全 Godot 的真·命门,**必须 spike 实测**。
- **长列表**:`ScrollContainer` 默认不回收节点,长 feed 会内存/性能爆,需自研虚拟化列表(节点复用)。一次性投入。
- **无障碍**:Godot 4.5(2025-09)才完整集成 AccessKit(4.4 起有早期铺垫),当前仍处早期/覆盖不全,落后原生。
- **原生集成**(推送/支付/分享/第三方登录):Godot 无内置,需逐平台写 GDExtension 插件。量大但躲不掉(任何方案都要装支付等插件)。
- **主题/动效/i18n**:Godot 的 `Theme`/`Tween`/内置翻译表都够用,顺。

## 3. AI 层:多模型网关

- 需求:支持 Claude / GPT / Gemini / 本地模型,可切换、可灰度、可按成本路由。原始选型提到 **LibreFang** 作为网关。
- 调研态度:**抽象掉具体模型供应商是对的做法**(别把某家 API 写死)。但具体网关组件的成熟度需评估——若 LibreFang 尚未验证,Phase 1 先**直连一家(建议 Claude)** 把 DSL 生成跑通,网关抽象作为一个内部 `LLMProvider` 接口先占位,稳定后再引入统一网关。**不要在验证核心假设的阶段引入不成熟中间件。**
- 关键约束:AI 输出必须约束为合法 DSL(JSON Schema 校验 + 失败重试),且**永不产出可执行代码**。模型侧用 structured output / function calling 强制 schema。详见 [05-dsl-design](./05-dsl-design.md) 与 [06-challenges](./06-challenges.md)。

## 4. 后端 / 数据 / 存储

- **后端 NestJS**:成熟、模块化、TypeScript,适合用户/社区/Fork/排行榜这类标准业务。无异议。

  > **决策变更(2026-06-12,见 [ADR-011](./decisions.md)):后端改用 Go(gin + GORM)，并由 `internal/app` 显式 installer 装配。** 原选 NestJS 的理由仍成立(模块化、标准业务匹配),推翻是因为团队主力 Go 栈、自有运维沉淀可复用,且 Go 单二进制 + 并发模型更契合 AI 网关的高并发转发。PostgreSQL / S3 / MinIO 不变。

- **PostgreSQL**:关系型 + JSONB(存 DSL 补丁很合适),Fork Tree 可用邻接表 / 闭包表 / `ltree`。无异议。
- **S3 / MinIO**:图片、游戏资源、Mod 资源。标准。
- 这一层没有争议项,详见 [04-architecture](./04-architecture.md) 与 [08-deployment](./08-deployment.md)。

## 5. 仍需深入调研的开放项

- **Godot 运行时加载 DSL 并动态换素材/逻辑** 的具体机制(`ResourceLoader`、远程资源、热加载边界)——决定 DSL 能改到多深。
- **Godot 内嵌一个轻量 DSL 编辑器 UI** 的体验上限(参数滑杆、实时预览)。
- **iOS/Android 上 Godot 导出包体与启动时间**,影响「点链接即玩」的体验。
- **AI 输出 DSL 的合法率与平衡性**,需要早期用真实 prompt 集做评测(见 [06-challenges](./06-challenges.md))。
