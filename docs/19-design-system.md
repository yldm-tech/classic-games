# 设计系统

已有一套 HTML/CSS 原型(Claude Design 导出)定义了 ForgePlay 的视觉语言:深色为主、橙红(熔炉)主色、设计 token 化。
本文档讲怎么把它**落到 Godot**,以及实现时对照哪些既有产物。

## 来源

原型 bundle 里的设计产物(实现时直接对照,不要凭记忆):

- `_ds/.../tokens/` — colors / fonts / typography / spacing / base 的 CSS 变量
- `app.css` / `ds.css` — 应用层样式
- `covers/` — 9 款游戏封面图(真实素材,非占位)
- 各 `fp-app-*.jsx` — 页面与组件的视觉与交互参照
- 截图 `screenshots/` — 各页面深浅色、各平台的目标效果

**原则**(来自 handoff README):**像素级复刻视觉输出,但不照搬原型的内部结构**。Godot 用自己的方式实现,对齐的是最终效果,不是 React 的组件树。

## Token → Godot 映射

原型的 CSS 变量映射到 Godot `Theme` 资源 + 一个 token 单例:

| CSS token 类 | Godot 承载 |
|---|---|
| colors(`--bg-app` `--text-muted` `--brand` …) | Theme color + token 单例常量;深/浅两套 |
| typography(字号/字重/行高/eyebrow) | Theme font size + 自定义 type scale |
| spacing(间距刻度) | token 单例常量,组件统一引用 |
| radii / shadows / glow | Theme StyleBox(圆角、阴影、发光) |
| motion(ease/时长) | Tween 的缓动常量(如 `ease-snap` cubic-bezier) |

做法:维护**一份 token 来源**(从原型 CSS 变量誊一份成 Godot 常量),颜色/字号/间距全引用它,不散落硬编码——这样深浅主题切换、整体调色才可控。

## 深浅双主题

- 原型两套主题都已适配(深色默认)。Godot 用两份 Theme(或一份 + 运行时换 token),运行时切换即时重渲([16-client-architecture](./16-client-architecture.md))。
- 教训:设置页「外观」必须是真开关。原型曾因为「外观行是死的」被误判成「浅色没适配」——其实是控件没接 onClick。Godot 实现时把主题/语言开关接到全局 state。
- 验证:每个页面深浅色都要真机过([13-testing](./13-testing.md)),别只测深色。

## 组件库

从 `Control` 基元搭一套对照原型的组件([16](./16-client-architecture.md) `shell/design_system/components/`)。对照原型已有的 preview 清单:

- 按钮(主/次/ghost,多尺寸)、徽章/chip、卡片、KPI 卡、表单/输入、表格、终端卡、代码块、导航头、游戏卡、段控(segment)、图标库。
- **游戏封面**:用 `covers/` 真实封面图,不用字母占位(原型修过「ED/CG 字母占位」的坑——所有小卡、HUD 背景、直播/房间头图、回放都要传真实封面)。
- **图标**:真实品牌图标(单色 SVG,跟随主题色),按 locale 切换([18-i18n](./18-i18n.md))。不用占位 emoji/字母。

## 视觉规范要点(从原型提炼)

- **主色**:橙红「熔炉」色(`#FF4D1A` 一带),用于强调/CTA;背景近黑 `#0A0809`,顶部有微弱橙红径向光晕。
- **信息架构**:每个页面只回答一个问题;Tab 平级、子页左上返回、操作半屏弹层、全屏只留游戏和直播([16](./16-client-architecture.md))。
- **数字/徽章不换行**:大数字、短徽章单行显示([18-i18n](./18-i18n.md) 排版细节)。
- **设备框 / 平台 chrome**:原型支持 iOS/Android/iPad/macOS/Windows 的状态栏、notch、标题栏(红绿灯 vs caption 按钮)、导航(tab/rail/sidebar)随平台切换。Godot 客户端按运行平台呈现对应 chrome。

## 设计评审(流程教训)

原型迭代里有一条值得制度化的教训:**功能验收 ≠ 设计评审**。

- 「能点、不报错、文字没截断」只是功能验收;「这个图标/控件放这里合不合理」是另一种检查。
- 原型曾因只做功能验收,漏掉「齿轮画得像灯泡」「编辑资料按钮位置突兀」这类明显设计问题。
- 制度化:每轮大改动跑两种检查——**功能验收 + 设计评审**(以挑剔 UI 设计师视角查图标语义、控件位置、移动端惯例、信息层级、重复入口)。纳入 [13-testing](./13-testing.md) 的跨平台验证清单。

## 落地节奏

- Phase 0/1:先把 token + Theme + 核心组件(按钮/卡片/输入/列表/导航)搭好,够核心闭环页面用。
- Phase 2+:补全组件库与各平台 chrome 细节,全页面深浅色精修。
