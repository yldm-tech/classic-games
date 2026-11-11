// Copy for the landing page in both locales. Every claim here is backed by a file in the repository; when the repository changes, change the copy with it. The two objects share one interface so a string cannot exist in one language only. Game names, genres, taglines and guide texts are not here: they come from src/data/games.ts, which checks them against the launcher's own source.

export const LOCALES = ['zh-CN', 'en'] as const;
export type Locale = (typeof LOCALES)[number];

/** Prefix a root-relative site path with the locale segment. Chinese is the root locale and has no prefix. */
export function localizePath(locale: Locale, path: string): string {
	return locale === 'en' ? `/en${path}` : path;
}

interface Titled {
	title: string;
	body: string;
}

interface SectionHead {
	eyebrow: string;
	/** Section heading. A "|" marks a phrase boundary where the line may break; see Phrases.astro. */
	title: string;
	lead: string;
}

interface Shot {
	/** Short name of the screen, shown in front of the caption. */
	name: string;
	caption: string;
	/** Text alternative: what the capture shows. */
	alt: string;
}

interface CommandLine {
	kind: 'comment' | 'command' | 'blank';
	text: string;
}

interface ControlRow {
	action: string;
	/** Keyboard keys, as key cap labels. */
	keys: string[];
	/** Gamepad buttons, as key cap labels. */
	pad: string[];
	/** Optional words after the gamepad buttons, for what a cap cannot say. */
	padNote?: string;
}

export interface LandingStrings {
	meta: { title: string; description: string };
	nav: {
		skip: string;
		primaryLabel: string;
		docs: string;
		developers: string;
		github: string;
		themeToggle: string;
		switchLanguage: string;
		otherLanguageName: string;
		otherLanguageShort: string;
		home: string;
	};
	hero: {
		status: string;
		/** Page heading, with "|" phrase boundaries like the section headings. */
		title: string;
		lead: string;
		primaryCta: string;
		secondaryCta: string;
		note: string;
		shotAlt: string;
		shotCaption: string;
	};
	games: SectionHead & {
		players: string;
		artLabel: string;
		artAlt: { shooter: string; survivor: string; tower_defense: string };
		shotLabel: string;
		shotAlt: { shooter: string; survivor: string; tower_defense: string };
		achievements: (count: number) => string;
		artCredit: string;
		artCreditLink: string;
	};
	launcher: SectionHead & {
		shots: { library: Shot; achievements: Shot; settings: Shot; menu: Shot; pause: Shot; result: Shot };
	};
	pc: SectionHead & {
		shots: { library: Shot; detail: Shot };
	};
	controls: SectionHead & {
		tableCaption: string;
		columns: { action: string; keyboard: string; gamepad: string };
		rows: ControlRow[];
		notes: [string, string];
	};
	local: SectionHead & { facts: [Titled, Titled, Titled] };
	planned: SectionHead & { genres: string[]; note: string };
	developers: SectionHead & {
		runtimesTitle: string;
		runtimesLead: string;
		sectionsLabel: string;
		schemaLink: string;
		baselineLink: string;
		patchTitle: string;
		patchLead: string;
		tableCaption: string;
		columns: { op: string; path: string; before: string; after: string };
		absent: string;
		removed: string;
		total: (before: number, after: number) => string;
		serviceTitle: string;
		serviceLead: string;
		optionalTag: string;
		server: Titled & { link: string };
		cli: Titled & { link: string };
		mcp: Titled & { link: string };
		sdk: Titled & { link: string };
		readMore: string;
	};
	start: SectionHead & {
		codeLabel: string;
		lines: CommandLine[];
		guideLink: string;
		repoLink: string;
	};
	notFound: { title: string; body: string; home: string; docs: string };
	footer: {
		tagline: string;
		docsHeading: string;
		docsIndex: string;
		clientArchitecture: string;
		dsl: string;
		decisions: string;
		developersHeading: string;
		gettingStarted: string;
		cli: string;
		mcp: string;
		sdk: string;
		projectHeading: string;
		terms: string;
		privacy: string;
		licenses: string;
		license: string;
		artNote: string;
		privacyNote: string;
	};
}

const CLONE_PLACEHOLDER = '{{clone}}';

/** Marker replaced with the real clone command by the page, so the repository URL stays in one place. */
export const CLONE_COMMAND_PLACEHOLDER = CLONE_PLACEHOLDER;

const zh: LandingStrings = {
	meta: {
		title: '经典厅 Classic Games — 开源的主机风格游戏启动器',
		description: '经典厅（Classic Games）是一个开源的主机风格游戏启动器，自带一组经典类型的原创游戏，用手柄或键盘游玩，另有面向键盘鼠标的 PC 模式。进度只保存在本机。',
	},
	nav: {
		skip: '跳到正文',
		primaryLabel: '主导航',
		docs: '文档',
		developers: '开发者',
		github: 'GitHub 仓库',
		themeToggle: '切换深色 / 浅色主题',
		switchLanguage: 'Switch to English',
		otherLanguageName: 'English',
		otherLanguageShort: 'EN',
		home: '经典厅 Classic Games 首页',
	},
	hero: {
		status: '开源 · 预发布 · 目前只能从源码运行',
		title: '主机风格的启动器，|一组经典类型的|原创游戏',
		lead: '经典厅（Classic Games）是一个开源的游戏启动器，自带三款原创游戏。用手柄或键盘就能完成全部操作，按 F11 切换到面向键盘鼠标的 PC 模式。进度只保存在本机，启动器不发任何网络请求。',
		primaryCta: '从源码运行',
		secondaryCta: '在 GitHub 上查看源码',
		note: '还没有公开的构建，也没有上架任何商店。运行需要 Godot 4.6.3。',
		shotAlt: '启动器首页：左侧是《星环巡航》的标题、「开始游戏」「游戏菜单」「成就」三行，下方是最近游玩的三款游戏，背景是这款游戏的主视觉。',
		shotCaption: '启动器首页的真实截图（1920×1080）。画面里的游玩时间和分数来自一份本地存档。',
	},
	games: {
		eyebrow: '01 · 游戏',
		title: '现在有三款游戏，|都是原创',
		lead: '每款游戏放两张图：左边是启动器里用的主视觉，是一张插画；右边是真实的局内画面。局内目前用的是纯几何图形，还没有贴图美术，主视觉不代表实际画面。',
		players: '1 人',
		artLabel: '主视觉（插画）',
		artAlt: {
			shooter: '《星环巡航》主视觉：一架战机拖着橙色尾焰飞向星云中的巨型机甲。',
			survivor: '《长夜草原》主视觉：月夜的草原上，一个披斗篷的人举着发光的法杖，四周是发绿光的生物。',
			tower_defense: '《隘口守卫》主视觉：黄昏的草坡上，一座放电的塔守着一条有队伍行进的道路。',
		},
		shotLabel: '局内画面（几何图形）',
		shotAlt: {
			shooter: '《星环巡航》局内截图：蓝色三角形是玩家，向右发射一排黄色子弹；橙色方块是敌机，红色菱形和粉色箭头是敌方弹幕；上方有得分、生命条、倒计时和首领血条。',
			survivor: '《长夜草原》局内截图：绿色场地中央的蓝色多边形是玩家，旁边有几个黄色圆点；上方有得分、生命条、倒计时、等级和击倒数。',
			tower_defense: '《隘口守卫》局内截图：一条灰色折线道路，路上有三个粉色六边形敌人，路边有一座蓝色六边形的塔；中间是准星和射程圆圈，左下角是五种塔的选择栏。',
		},
		achievements: (count) => `${count} 个成就`,
		artCredit: '三张主视觉由本项目用图像生成模型生成，是原创构图，不取材于任何现有游戏的角色或美术。来源记录在',
		artCreditLink: '开源许可说明',
	},
	launcher: {
		eyebrow: '02 · 启动器',
		title: '首页之外的|几个界面',
		lead: '启动器是固定 1920×1080 的画布，随窗口整体缩放。界面上关于玩家的数字都读自本地存档，没有记录时显示空状态。',
		shots: {
			library: { name: '游戏库', caption: '按全部、最近游玩、收藏和类型分类，可以排序，可以按拼音首字母或英文名搜索。', alt: '游戏库界面：顶部是分类标签，中间是三张游戏封面，底部是选中游戏的类型、人数、游玩时长、上次游玩、最高分和成就。' },
			achievements: { name: '成就', caption: '只列出游戏目录里定义的成就和真实的解锁时间，没有稀有度，也没有排行榜。', alt: '成就界面：左侧按游戏列出解锁进度，中间是成就卡片，右侧是选中成就的说明和解锁时间。' },
			settings: { name: '设置', caption: '语言（中文 / English）、窗口模式、垂直同步、帧率上限、音量、键盘改键，以及存档的导出、导入和清除。', alt: '设置界面的「常规」页：语言、24 小时制和启动默认模式三项，左侧还有画面、声音、控制、存档、关于几页。' },
			menu: { name: '游戏菜单', caption: '每款游戏有自己的菜单：开始游戏、玩法与操作、游玩记录、成就、收藏。', alt: '《隘口守卫》的游戏菜单：左侧是菜单项，右侧是概览，显示最高分、游玩时长和成就进度，背景是主视觉。' },
			pause: { name: '暂停', caption: '继续、重新开始、主音量、退出到游戏菜单，右边是这款游戏的操作表。窗口失去焦点时自动暂停。', alt: '暂停界面：左侧是继续游戏、重新开始、主音量、退出到游戏菜单，右侧列出移动、加速、护盾等操作对应的键盘按键和手柄按键。' },
			result: { name: '结算', caption: '一局结束后显示得分、最高分和本局数据，可以再来一局，或返回游戏菜单、返回首页。', alt: '《隘口守卫》的结算界面：显示「失败」、本局得分、最高分、用时、波次、金币和击倒数，下面是再来一局、返回游戏菜单、返回首页。' },
		},
	},
	pc: {
		eyebrow: '03 · PC 模式',
		title: '按 F11，|换成键盘鼠标的布局',
		lead: 'PC 模式是同一份数据的另一种布局：侧栏、搜索框、网格或列表、类型筛选。单击选中，双击开始，右键打开这款游戏的菜单。键盘按 F11、手柄长按 View 键在两种模式之间切换；一局游戏进行期间不能切换。',
		shots: {
			library: { name: '游戏库', caption: '侧栏列出分类和全部游戏，主区可以在网格和列表之间切换，按类型筛选、排序。', alt: 'PC 模式的游戏库：左侧是搜索框、分类和游戏列表，右侧是三张游戏封面的网格和类型筛选按钮。' },
			detail: { name: '游戏页', caption: '单个游戏的页面：开始游戏、游戏菜单、收藏，以及游玩记录和最近解锁的成就。', alt: 'PC 模式的游戏页：上方是《星环巡航》的主视觉、标题和「开始游戏」按钮，下方是最高分、游玩次数、通关次数、游玩时长等记录。' },
		},
	},
	controls: {
		eyebrow: '04 · 操作',
		title: '手柄或键盘，|都能走完全程',
		lead: '下面是启动器界面的默认按键，取自工程的输入映射。手柄按键的图标是 A / B / X / Y 布局。',
		tableCaption: '启动器的默认键盘按键和手柄按键',
		columns: { action: '操作', keyboard: '键盘', gamepad: '手柄' },
		rows: [
			{ action: '移动焦点', keys: ['↑', '↓', '←', '→'], pad: [], padNote: '十字键 / 左摇杆' },
			{ action: '确认', keys: ['Enter', 'Space'], pad: ['A'] },
			{ action: '返回', keys: ['Esc', 'Backspace'], pad: ['B'] },
			{ action: '当前界面的附加操作（如搜索、收藏）', keys: ['X', 'Y'], pad: ['X', 'Y'] },
			{ action: '切换页内标签', keys: ['Q', 'E'], pad: ['LB', 'RB'] },
			{ action: '切换顶层标签', keys: ['PageUp', 'PageDown'], pad: ['LT', 'RT'] },
			{ action: '选项 / 游戏菜单', keys: ['M'], pad: ['Menu'] },
			{ action: '切换主机模式 / PC 模式', keys: ['F11'], pad: ['View'], padNote: '长按' },
		],
		notes: ['键盘按键可以在「设置 → 控制」里修改；手柄按键是固定的。', '局内的操作每款游戏不同，列在游戏菜单的「玩法与操作」和暂停界面里。'],
	},
	local: {
		eyebrow: '05 · 本地',
		title: '进度只在你的机器上',
		lead: '启动器没有账号，也没有联网功能。',
		facts: [
			{ title: '一份本地存档', body: '游玩时长、最高分、收藏、最近游玩、成就、设置和改键都保存在同一个本地文件里。' },
			{ title: '不发网络请求', body: '启动器不登录，不请求任何服务器。仓库的门禁脚本会拒绝启动器目录里出现 HTTP 客户端或网址。' },
			{ title: '可以导出和导入', body: '存档可以导出成一个 JSON 文件，也可以从导出的文件导入进度；清除进度前需要确认。' },
		],
	},
	planned: {
		eyebrow: '06 · 计划',
		title: '计划中的类型',
		lead: '下面这些类型的游戏在计划中，没有日期。',
		genres: ['基地防御坦克', '横版平台跳跃', '合作平台跳跃', '迷宫炸弹', '合作清版街机', '跑动射击'],
		note: '每一款都会使用原创的名称、角色、美术和关卡，不复刻任何现有商业游戏。',
	},
	developers: {
		eyebrow: '07 · 开发者',
		title: '数据驱动的游戏，|和一套可选的在线服务',
		lead: '每款游戏都是 apps/client/runtime 下的一个运行时，由一份 Mod DSL 文档描述。启动器运行的是每个运行时自带的基线文档。',
		runtimesTitle: '三个运行时，各有一份 Schema 和一份基线',
		runtimesLead: '运行时的标识、版本和 DSL 顶层分区在构建本站时直接从 Schema 和基线文件里读出。',
		sectionsLabel: 'DSL 顶层分区',
		schemaLink: 'Schema',
		baselineLink: '基线 DSL',
		patchTitle: '对 DSL 的修改是 RFC 6902 补丁',
		patchLead: '下面四个操作把《星环巡航》的基线 DSL 变成仓库里的 golden 文件。补丁有 Go 和 GDScript 两份实现，用同一份基线和 golden 文件做测试。「之前」和「之后」两列在构建本站时从这两个文件里读出。',
		tableCaption: '补丁的四个操作，以及每个路径在基线和 golden 文件里的值',
		columns: { op: '操作', path: '路径', before: '之前', after: '之后' },
		absent: '不存在',
		removed: '已删除',
		total: (before, after) => `敌人总数从 ${before} 变为 ${after}。`,
		serviceTitle: '在线服务：能运行，有测试，可选',
		serviceLead: 'Go 后端、命令行、MCP 服务和 Go SDK 实现了 Mod DSL 的校验与补丁，以及一套在线服务的 API（账号、目录、Mod、社区、商业化）。启动器目前没有接入其中任何一个，不运行它们也能玩全部游戏。',
		optionalTag: '可选 · 启动器未接入',
		server: { title: 'apps/server', body: 'Go 后端（gin + GORM），开发模式下用 SQLite 文件，不需要任何密钥就能启动。', link: 'API 设计' },
		cli: { title: 'classic-games', body: '命令行工具。可以离线校验 DSL、应用补丁、做迁移，也可以访问后端。', link: 'CLI 文档' },
		mcp: { title: 'classic-games-mcp', body: 'MCP 服务。把 Schema、校验、补丁和后端 API 作为工具提供给支持 MCP 的 AI 助手。', link: 'MCP 文档' },
		sdk: { title: 'packages/sdk', body: '后端 HTTP API 的类型化 Go 客户端。CLI 和 MCP 服务都构建在它之上。', link: 'Go SDK 文档' },
		readMore: '阅读 Mod DSL 设计',
	},
	start: {
		eyebrow: '08 · 运行',
		title: '从源码运行',
		lead: '需要 Godot 4.6.3（版本必须精确，用标准版，不要用 .NET 版）和 GNU Make。只运行启动器和游戏不需要 Go，也不需要 Node.js。',
		codeLabel: '终端命令',
		lines: [
			{ kind: 'command', text: CLONE_PLACEHOLDER },
			{ kind: 'command', text: 'cd classic-games' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 导入工程资源，只需要做一次' },
			{ kind: 'command', text: 'make import GODOT=/path/to/godot' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 启动启动器' },
			{ kind: 'command', text: '/path/to/godot --path apps/client' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 启动器与游戏流程的无头测试' },
			{ kind: 'command', text: 'make launcher-test game-flow-test GODOT=/path/to/godot' },
		],
		guideLink: '完整步骤见快速开始',
		repoLink: '在 GitHub 上查看源码',
	},
	notFound: { title: '页面不存在', body: '这个地址下没有内容。', home: '回到首页', docs: '文档索引' },
	footer: {
		tagline: '开源的主机风格游戏启动器，自带一组经典类型的原创游戏。',
		docsHeading: '文档',
		docsIndex: '文档索引',
		clientArchitecture: '客户端架构',
		dsl: 'Mod DSL 设计',
		decisions: '决策记录',
		developersHeading: '开发者',
		gettingStarted: '快速开始',
		cli: 'CLI',
		mcp: 'MCP 服务',
		sdk: 'Go SDK',
		projectHeading: '项目',
		terms: '用户协议',
		privacy: '隐私政策',
		licenses: '开源许可说明',
		license: 'Classic Games 以 Apache-2.0 许可开源。',
		artNote: '游戏主视觉由图像生成模型生成，为原创构图。',
		privacyNote: '本站不使用分析或追踪脚本，也不加载第三方字体。',
	},
};

const en: LandingStrings = {
	meta: {
		title: 'Classic Games — an open-source console-style game launcher',
		description: 'Classic Games (经典厅) is an open-source console-style launcher with a collection of original games in classic genres, playable with a gamepad or a keyboard, with a PC desktop mode. Progress is stored locally.',
	},
	nav: {
		skip: 'Skip to content',
		primaryLabel: 'Primary',
		docs: 'Docs',
		developers: 'Developers',
		github: 'GitHub repository',
		themeToggle: 'Toggle dark / light theme',
		switchLanguage: '切换到简体中文',
		otherLanguageName: '简体中文',
		otherLanguageShort: '中文',
		home: 'Classic Games home',
	},
	hero: {
		status: 'Open source · pre-release · runs from source only',
		title: 'A console-style launcher |with original games |in classic genres',
		lead: 'Classic Games (经典厅) is an open-source game launcher that comes with three original games. Everything can be done with a gamepad or a keyboard, and F11 switches to a PC mode laid out for keyboard and mouse. Progress is stored on your machine only; the launcher makes no network requests.',
		primaryCta: 'Run from source',
		secondaryCta: 'View the source on GitHub',
		note: 'There are no public builds and no store releases yet. Running it needs Godot 4.6.3.',
		shotAlt: 'The launcher home screen: the title of Orbit Patrol on the left with the rows Start, Game menu and Achievements, a shelf of the three recently played games below, and the game key art as the backdrop.',
		shotCaption: 'An unedited capture of the launcher home screen (1920×1080), with the interface set to Chinese. The play times and scores in it come from a local save file.',
	},
	games: {
		eyebrow: '01 · Games',
		title: 'Three games today, |all original',
		lead: 'Each game is shown with two images: on the left the key art the launcher uses, which is an illustration, and on the right a capture of the game being played. In-game graphics are plain geometric shapes for now, with no sprite art yet; the key art does not represent how the game looks.',
		players: '1 player',
		artLabel: 'Key art (illustration)',
		artAlt: {
			shooter: 'Orbit Patrol key art: a fighter with orange engine trails flies toward a giant mech in a nebula.',
			survivor: 'Meadow Vigil key art: a cloaked figure holding a glowing staff on a moonlit meadow, surrounded by creatures that glow green.',
			tower_defense: 'Gatewatch key art: a tower crackling with electricity guards a road with a marching column, on a grassy slope at dusk.',
		},
		shotLabel: 'In game (geometric shapes)',
		shotAlt: {
			shooter: 'Orbit Patrol in game: the blue triangle is the player, firing a row of yellow bullets to the right; orange squares are enemies, red diamonds and pink arrows are enemy fire; the score, the HP bar, the countdown and the boss HP bar are along the top.',
			survivor: 'Meadow Vigil in game: the blue polygon in the middle of a green field is the player, with a few yellow dots nearby; the score, the HP bar, the countdown, the level and the kill count are along the top.',
			tower_defense: 'Gatewatch in game: a grey road with three pink hexagonal enemies on it and a blue hexagonal tower beside it; a cursor with a range circle in the middle, and a bar with the five tower types at the bottom left.',
		},
		achievements: (count) => `${count} achievements`,
		artCredit: 'The three key art images were generated by this project with an image model. They are original compositions and are not based on the characters or art of any existing game. Their provenance is recorded in the',
		artCreditLink: 'third-party licence notes (Chinese)',
	},
	launcher: {
		eyebrow: '02 · Launcher',
		title: 'The screens |beyond Home',
		lead: 'The launcher is a fixed 1920×1080 canvas that scales with the window. Every number about the player is read from the local save file, and a screen with no records shows an empty state. The captures below were taken with the interface set to Chinese; English is the other built-in language.',
		shots: {
			library: { name: 'Library', caption: 'Categories for all games, recently played, favourites and each genre; sorting; search by pinyin initials or by English name.', alt: 'The library screen: category tabs along the top, three game covers in the middle, and the selected game\'s genre, player count, play time, last played time, best score and achievements at the bottom.' },
			achievements: { name: 'Achievements', caption: 'Only the achievements the game catalog defines, with their real unlock times. No rarity figures and no leaderboards.', alt: 'The achievements screen: unlock progress per game on the left, achievement cards in the middle, and the selected achievement\'s description and unlock time on the right.' },
			settings: { name: 'Settings', caption: 'Language (Chinese or English), window mode, vertical sync, frame rate cap, volume, keyboard rebinding, and exporting, importing or clearing the save.', alt: 'The General page of the settings screen with three rows: language, 24-hour clock and default mode at startup. The other pages are Display, Sound, Controls, Save data and About.' },
			menu: { name: 'Game menu', caption: 'Each game has its own menu: start, how to play and controls, play records, achievements, favourite.', alt: 'The game menu of Gatewatch: menu rows on the left, an overview with best score, play time and achievement progress on the right, over the game key art.' },
			pause: { name: 'Pause', caption: 'Resume, restart, master volume, quit to the game menu, and the controls of the running game on the right. The game pauses by itself when the window loses focus.', alt: 'The pause screen: resume, restart, master volume and quit to the game menu on the left; on the right a table of the keyboard keys and gamepad buttons for move, boost, shield and the other controls.' },
			result: { name: 'Result', caption: 'After a run: the score, the best score and the figures of the run, with the choice to play again or go back to the game menu or to Home.', alt: 'The result screen of Gatewatch: the word for "defeat", the score of the run, the best score, time, waves, gold and kills, and the rows play again, back to the game menu and back to Home.' },
		},
	},
	pc: {
		eyebrow: '03 · PC mode',
		title: 'Press F11 |for a keyboard and mouse layout',
		lead: 'PC mode is a second layout over the same data: a sidebar, a search field, a grid or a list, and genre filters. Click to select, double-click to start, right-click for the game\'s menu. F11 on the keyboard or holding the View button on a gamepad switches between the two modes; the switch is refused while a run is in progress.',
		shots: {
			library: { name: 'Library', caption: 'The sidebar lists the categories and every game; the main area switches between a grid and a list, with genre filters and sorting.', alt: 'The PC mode library: a search field, categories and the list of games on the left; a grid of three game covers and genre filter buttons on the right.' },
			detail: { name: 'Game page', caption: 'The page of one game: start, game menu, favourite, the play records and the most recently unlocked achievements.', alt: 'The PC mode game page: the key art, title and start button of Orbit Patrol at the top; best score, runs played, clears, play time and other records below.' },
		},
	},
	controls: {
		eyebrow: '04 · Controls',
		title: 'A gamepad or a keyboard |is enough',
		lead: 'These are the default bindings of the launcher interface, taken from the project\'s input map. Gamepad glyphs use the A / B / X / Y layout.',
		tableCaption: 'Default keyboard keys and gamepad buttons of the launcher',
		columns: { action: 'Action', keyboard: 'Keyboard', gamepad: 'Gamepad' },
		rows: [
			{ action: 'Move the focus', keys: ['↑', '↓', '←', '→'], pad: [], padNote: 'D-pad / left stick' },
			{ action: 'Confirm', keys: ['Enter', 'Space'], pad: ['A'] },
			{ action: 'Back', keys: ['Esc', 'Backspace'], pad: ['B'] },
			{ action: 'Extra actions of the current screen (search, favourite)', keys: ['X', 'Y'], pad: ['X', 'Y'] },
			{ action: 'Switch tabs inside a screen', keys: ['Q', 'E'], pad: ['LB', 'RB'] },
			{ action: 'Switch top-level tabs', keys: ['PageUp', 'PageDown'], pad: ['LT', 'RT'] },
			{ action: 'Options / game menu', keys: ['M'], pad: ['Menu'] },
			{ action: 'Switch console mode / PC mode', keys: ['F11'], pad: ['View'], padNote: 'hold' },
		],
		notes: ['Keyboard keys can be changed under Settings → Controls. Gamepad buttons are fixed.', 'In-game controls differ per game and are listed in the game menu and on the pause screen.'],
	},
	local: {
		eyebrow: '05 · Local',
		title: 'Progress stays on your machine',
		lead: 'The launcher has no accounts and no online features.',
		facts: [
			{ title: 'One local save file', body: 'Play time, best scores, favourites, recently played games, achievements, settings and key bindings are kept in a single local file.' },
			{ title: 'No network requests', body: 'The launcher does not sign in and does not contact any server. A repository gate rejects any HTTP client or URL in the launcher directory.' },
			{ title: 'Export and import', body: 'The save can be exported to a JSON file, and progress can be imported from an exported file. Clearing progress asks for confirmation first.' },
		],
	},
	planned: {
		eyebrow: '06 · Planned',
		title: 'Planned genres',
		lead: 'Games in the following genres are planned. There are no dates.',
		genres: ['Base-defence tank action', 'Side-scrolling platformer', 'Co-op platformer', 'Maze bomb game', 'Co-op clear-the-screen arcade', 'Run-and-gun'],
		note: 'Each will have original names, characters, art and levels, and will not recreate any existing commercial game.',
	},
	developers: {
		eyebrow: '07 · Developers',
		title: 'Data-driven games |and an optional online service',
		lead: 'Each game is a runtime under apps/client/runtime, described by a Mod DSL document. The launcher runs the baseline document that ships with each runtime.',
		runtimesTitle: 'Three runtimes, each with a schema and a baseline',
		runtimesLead: 'Runtime identifiers, versions and top-level DSL sections are read from the schema and baseline files when this site is built.',
		sectionsLabel: 'Top-level DSL sections',
		schemaLink: 'Schema',
		baselineLink: 'Baseline DSL',
		patchTitle: 'A change to the DSL is an RFC 6902 patch',
		patchLead: 'The four operations below turn the baseline DSL of Orbit Patrol into the golden file in the repository. The patch semantics are implemented twice, in Go and in GDScript, and both are tested against the same baseline and golden file. The "before" and "after" columns are read from those two files when this site is built.',
		tableCaption: 'The four operations of the patch, with the value at each path in the baseline and in the golden file',
		columns: { op: 'Op', path: 'Path', before: 'Before', after: 'After' },
		absent: 'absent',
		removed: 'removed',
		total: (before, after) => `The enemy total goes from ${before} to ${after}.`,
		serviceTitle: 'The online service: working, tested, optional',
		serviceLead: 'The Go backend, the command line, the MCP server and the Go SDK implement Mod DSL validation and patching, and the API of an online service (accounts, catalog, mods, community, commerce). The launcher is not wired to any of them today, and every game can be played without running them.',
		optionalTag: 'Optional · not used by the launcher',
		server: { title: 'apps/server', body: 'The Go backend (gin and GORM). In development mode it runs on a SQLite file and starts without any keys.', link: 'API design (Chinese)' },
		cli: { title: 'classic-games', body: 'The command-line tool. It validates, patches and migrates DSL documents offline, and can talk to the backend.', link: 'CLI docs' },
		mcp: { title: 'classic-games-mcp', body: 'The MCP server. It offers the schemas, validation, patching and the backend API as tools to MCP-capable AI assistants.', link: 'MCP docs' },
		sdk: { title: 'packages/sdk', body: 'A typed Go client for the backend HTTP API. The CLI and the MCP server are both built on it.', link: 'Go SDK docs' },
		readMore: 'Read the Mod DSL design (Chinese)',
	},
	start: {
		eyebrow: '08 · Run',
		title: 'Run it from source',
		lead: 'You need Godot 4.6.3 (exactly that version, the standard build and not the .NET build) and GNU Make. Running the launcher and the games needs neither Go nor Node.js.',
		codeLabel: 'Terminal commands',
		lines: [
			{ kind: 'command', text: CLONE_PLACEHOLDER },
			{ kind: 'command', text: 'cd classic-games' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Import the project resources, once' },
			{ kind: 'command', text: 'make import GODOT=/path/to/godot' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Start the launcher' },
			{ kind: 'command', text: '/path/to/godot --path apps/client' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Headless tests of the launcher and the game flow' },
			{ kind: 'command', text: 'make launcher-test game-flow-test GODOT=/path/to/godot' },
		],
		guideLink: 'Full steps in Getting started',
		repoLink: 'View the source on GitHub',
	},
	notFound: { title: 'Page not found', body: 'There is nothing at this address.', home: 'Back to home', docs: 'Docs index' },
	footer: {
		tagline: 'An open-source console-style game launcher with original games in classic genres.',
		docsHeading: 'Docs',
		docsIndex: 'Docs index (Chinese)',
		clientArchitecture: 'Client architecture (Chinese)',
		dsl: 'Mod DSL design (Chinese)',
		decisions: 'Decision log (Chinese)',
		developersHeading: 'Developers',
		gettingStarted: 'Getting started',
		cli: 'CLI',
		mcp: 'MCP server',
		sdk: 'Go SDK',
		projectHeading: 'Project',
		terms: 'Terms of service (Chinese)',
		privacy: 'Privacy policy (Chinese)',
		licenses: 'Third-party licenses (Chinese)',
		license: 'Classic Games is open source under the Apache-2.0 license.',
		artNote: 'Game key art was generated with an image model; the compositions are original.',
		privacyNote: 'This site uses no analytics or trackers and loads no third-party fonts.',
	},
};

export const landing: Record<Locale, LandingStrings> = { 'zh-CN': zh, en };
