# 设计系统

客户端的界面是主机风格启动器(结构见 [16-client-architecture](./16-client-architecture.md) 第 3 节):固定 1920×1080 的 16:9 画布,深色,以每款游戏的主视觉为背景,文字和控件叠在主视觉与一层压暗渐变之上。本文说明它的设计 token、控件,以及改动界面时的做法。数值以代码为准,这里不抄一遍。

## 来源

| 文件 | 内容 |
|---|---|
| `apps/client/launcher/launcher_tokens.gd` | `LauncherTokens`:颜色、前景透明度档位、间距与尺寸、动效时长、字号、系统字体的选择 |
| `apps/client/launcher/pc_tokens.gd` | `LauncherPcTokens`:PC 模式在此之上独有的扁平配色与标题条、侧栏、网格、菜单的尺寸 |
| `apps/client/games/<游戏 id>/game.json` | 每款游戏自己的颜色:`colors`(标题字、投影、辉光)与 `art`(程序化主视觉的配色与图案) |
| `apps/client/games/<游戏 id>/` 里由清单 `art.image` 指向的图片 | 每款游戏的 16:9 主视觉,来源与许可见该目录的 `ASSETS.md` |

所有屏幕和控件只引用 token,不写散落的颜色、字号和透明度。要调整视觉,改 token;某处需要一个现有 token 表达不了的值,先加一个有名字的 token。

## Token

- **画布**:`CANVAS` 为 1920×1080。`project.godot` 用 `canvas_items` 拉伸、`aspect=keep`,所以所有位置和尺寸都直接按画布像素写,不读窗口大小;其他比例的窗口留黑边,不重排。
- **颜色**:背景 `BG`、前景 `FG`、压暗渐变的底色 `DEEP`、面板 / 卡片 / 对话框 / toast 的底色,以及收藏和危险操作共用的红色。启动器没有品牌主色:强调色来自当前游戏的 `colors`,所以换一款游戏,标题和辉光随之变化。
- **前景透明度档位**:文字层级不靠换颜色,而靠同一个前景色的固定透明度档位(`A_STRONG`、`A_BODY`、`A_MUTED`、`A_FAINT`,分隔线用 `A_RULE`、`A_HAIRLINE`,未聚焦的行用 `A_ROW_IDLE`、`A_SUB_IDLE`)。用 `LauncherTokens.fg(alpha)` 取色,不写临时的透明度,这样每一屏的层级一致。
- **间距与尺寸**:页面左右边距 `MARGIN`,顶部导航和页脚提示的位置与高度,行高、卡片与封面的尺寸、对话框宽度等。圆角只有一档 `RADIUS`。
- **动效**:切屏、背景交叉淡入、行高亮、卡片缩放、封面淡入各有一个时长常量,toast 的停留时间也在这里。
- **字号**:按文字角色命名(`SIZE_HERO`、`SIZE_PANEL_TITLE`、`SIZE_ROW`、`SIZE_BODY`、`SIZE_SMALL` 等),不按数值命名。
- **字体**:仓库不带字体文件。`LauncherTokens.font(weight, spacing, latin)` 从系统里解析中文与拉丁两套字体并缓存,`label_settings` 把字体、字号、颜色打包;字重按 CSS 的 100 至 900,字距按画布像素。细节见 [18-i18n](./18-i18n.md)。

## 控件

| 文件 | 内容 |
|---|---|
| `launcher_widgets.gd` | 小工厂:`text`、`hbox` / `vbox`、`rule`、`section_header`、`place`、`fill` |
| `launcher_controls.gd` | 主机屏幕的可交互控件:`FocusRow`、`Tab`、`Glyph`、`GlyphHint`、`ArtCard`、`Tile`,以及 `Icon`(成就图标的唯一实现)和 `GradientRect` |
| `launcher_scroll_grid.gd` | `LauncherScrollGrid`:按整行滚动的等大单元格网格,游戏库封面与成就列表共用 |
| `launcher_game_widgets.gd` | 游戏菜单、局内与暂停三屏共用:`KeyCap`、`Tag`、`Meter`、`HudChip`、`SliderRow`、`ConfirmDialog`、`GameTitle`、`AchievementRow` 等 |
| `settings_controls.gd` | 设置屏:`SettingRow`、`Switch`、`Segments`、`OutlineButton`、`RowList`、`KeyCapture` |
| `pc_controls.gd` | PC 模式:`Clickable` 及其派生(`Pill`、`IconButton`、`SideRow`、`LibraryCard`、`ListRow` 等)、`Menu`、`SearchField`、`Flow` |
| `launcher_key_art.gd` | `LauncherKeyArt`:一款游戏的主视觉。清单的 `art.image` 指向图片时用图片,否则按清单的 `art` 配色画程序化占位 |

控件遵守同一套约定:

- **只管外观。** 控件不持有游戏数据、不读存档,只通过 `hovered`(指针进入)和 `activated`(左键点击)报告意图。哪个控件有焦点由屏幕决定,再用 `set_focused` / `set_selected` 告诉控件怎么画。
- **不用 Godot 自带的键盘焦点。** 例外只有 PC 模式的搜索框,因为输入文字需要它。
- **焦点可见。** 聚焦的行有左侧的焦点条和向右淡出的底色,选中的卡片与封面有外环并放大,未选中的封面压暗。
- **页脚按键提示。** 每一屏在页脚用 `GlyphHint` 列出当前可用的按键,提示本身也可以点击,效果与按下那个键相同。
- **三种输入都完整。** 键盘、手柄、鼠标都能完成全部操作;屏幕不读原始输入事件,只处理外壳翻译好的动作名。

## 版式要点

- 主视觉铺满画布,文字与它之间隔着一层以 `DEEP` 为底色的渐变。
- 游戏标题用该游戏 `colors` 里的标题色、投影和辉光(`GameTitle`),其余文字一律用前景色的透明度档位。
- 数字、分数和短标签单行显示;拉丁文字可以用拉丁字体(`latin = true`)。
- 关于玩家的一切(时长、最高分、成就)没有记录时显示空状态,不放示例数据。
- PC 模式是同一份数据的另一种布局:更密、扁平、用容器搭建并随宽度重排;它的专用值放在 `LauncherPcTokens`,共用的仍取自 `LauncherTokens`。

## 查看效果

`make launcher-shot SCREEN=<屏幕 id> STATE=<played|fresh>` 把启动器的某一屏渲染成 1920×1080 的 PNG,默认写到 `~/screenshots/classic-games/console-launcher`。`played` 从一份带若干游玩记录的临时存档开始,`fresh` 从空存档开始,都不碰玩家的真实存档。语言、先派发的动作、PC 模式、游戏库里的条目数量等由环境变量控制,清单在 `apps/client/launcher/launcher_shot.gd` 开头。它需要真实的渲染器,不在 `make ci` 里。

## 设计评审

功能验收不等于设计评审。「能操作、不报错、文字没截断」只是功能验收;「这个图标的语义对不对、这个控件放在这里合不合理、层级是否清楚、有没有重复入口」是另一种检查。每轮较大的界面改动两种都要做,并且中文和英文各看一遍([13-testing](./13-testing.md))。
