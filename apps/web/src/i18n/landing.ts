// Copy for the landing page in both locales. Every claim here is backed by a file in the repository; when the repository changes, change the copy with it. The two objects share one interface so a string cannot exist in one language only.

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

interface CommandLine {
	kind: 'comment' | 'command' | 'blank';
	text: string;
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
	};
	console: {
		ariaLabel: string;
		promptLabel: string;
		prompt: string;
		promptTranslation?: string;
		patchLabel: string;
		checksLabel: string;
		checkSchema: string;
		checkParity: string;
		source: string;
	};
	flow: SectionHead & { steps: [Titled, Titled, Titled, Titled] };
	forkTree: {
		ariaLabel: string;
		rootTag: string;
		forkTag: string;
		caption: string;
		coverAlt: { ember: string; volt: string; foundry: string; ashfall: string };
	};
	bet: SectionHead & {
		pillars: [Titled, Titled, Titled];
		tradeoff: string;
		tradeoffLink: string;
		exampleTitle: string;
		exampleLead: string;
		tableCaption: string;
		columns: { op: string; path: string; before: string; after: string };
		absent: string;
		removed: string;
		total: (before: number, after: number) => string;
		sourcesLabel: string;
		sources: { prompt: string; baseline: string; golden: string; goTest: string; godotTest: string };
		readMore: string;
	};
	architecture: SectionHead & {
		client: { title: string; points: [string, string, string] };
		server: { title: string; points: [string, string, string] };
		link: string;
		contract: { title: string; body: string };
		platformsLabel: string;
		roadmapNote: string;
		roadmapLink: string;
		readMore: string;
	};
	runtimes: SectionHead & {
		descriptions: { shooter: string; survivor: string; tower_defense: string };
		names: { shooter: string; survivor: string; tower_defense: string };
		sectionsLabel: string;
		schemaLink: string;
		baselineLink: string;
		readMore: string;
	};
	developers: SectionHead & {
		cli: Titled & { link: string };
		mcp: Titled & { link: string };
		sdk: Titled & { link: string };
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
		architecture: string;
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
		privacyNote: string;
	};
}

const CLONE_PLACEHOLDER = '{{clone}}';

/** Marker replaced with the real clone command by the page, so the repository URL stays in one place. */
export const CLONE_COMMAND_PLACEHOLDER = CLONE_PLACEHOLDER;

const zh: LandingStrings = {
	meta: {
		title: 'Classic Games — Fork 一个游戏，用一句话改出你的版本',
		description: 'Classic Games 是 AI 驱动的小游戏创作与社区平台。用自然语言描述修改，AI 只生成受 JSON Schema 约束的 Mod DSL 补丁，绝不生成可执行代码。',
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
		home: 'Classic Games 首页',
	},
	hero: {
		status: '预发布 · 目前只能从源码构建',
		title: 'Fork 一个游戏，|说一句话，|改出你的版本',
		lead: 'Classic Games 是 AI 驱动的小游戏创作与社区平台。你用自然语言描述想要的修改，AI 只回一段 Mod DSL 补丁：一份受 JSON Schema 约束的 JSON，不是可执行代码。',
		primaryCta: '从源码开始',
		secondaryCta: '阅读文档',
		note: '还没有公开构建，也没有上架任何应用商店。',
	},
	console: {
		ariaLabel: '示例：一句话如何变成一段 DSL 补丁',
		promptLabel: '一句话',
		prompt: '把飞机换成猫,加只鸟,删掉炮台',
		patchLabel: 'AI 输出 · RFC 6902 补丁',
		checksLabel: '校验',
		checkSchema: '生效 DSL 通过 shooter-1.0.0 Schema 校验',
		checkParity: 'Go 与 GDScript 两端应用后结果一致',
		source: '提示词和补丁取自仓库的测试夹具，不是某次真实模型调用的记录。',
	},
	flow: {
		eyebrow: '01 · 流程',
		title: '从 Fork 到发布，|四步',
		lead: '核心范式不是「从零创建游戏」，而是在一个已经能跑的游戏上做增量修改。AI 擅长的是后者。',
		steps: [
			{ title: 'Fork 一个能跑的游戏', body: '所有创作都从官方维护的 Runtime 出发。Fork 只保存相对父级的补丁，不复制整份游戏。' },
			{ title: '用自然语言描述修改', body: '比如「把飞机换成猫,加只鸟,删掉炮台」。不用学引擎，也不用写代码。' },
			{ title: 'AI 只改 Mod DSL', body: '模型输出一段 RFC 6902 补丁。后端应用补丁、按 JSON Schema 校验生效 DSL；不合法就把错误回灌给模型，在有限次数内重试。' },
			{ title: '发布，让别人接着改', body: '作品发布到社区后可以被游玩、点赞、评论和再次 Fork，一个游戏由此长成一棵 Fork Tree。' },
		],
	},
	forkTree: {
		ariaLabel: 'Fork Tree 示意图',
		rootTag: '官方基线',
		forkTag: 'Fork',
		caption: '作品名沿用愿景文档里的例子。封面取自客户端的种子目录（apps/client/assets/covers），在这里只用来示意 Fork Tree 的形状。',
		coverAlt: {
			ember: '抽象封面：地平线上的橙色落日和一条发光的赛道',
			volt: '抽象封面：透视网格上的一道荧光绿闪电',
			foundry: '抽象封面：等距菱形网格，其中几格亮着橙色和绿色',
			ashfall: '抽象封面：余烬飘落的夜色里，山顶上一座城堡的剪影',
		},
	},
	bet: {
		eyebrow: '02 · 核心赌注',
		title: 'AI 的输出空间，|被一份 Schema 框住',
		lead: 'Mod DSL 是一份描述「在 Runtime 上改了什么」的 JSON。同一份 JSON Schema 同时是 AI 的输出约束、后端的校验依据和 Runtime 的加载契约。',
		pillars: [
			{ title: '枚举、范围、开关', body: '字段几乎都是三类之一：从预埋集合里选的枚举、带范围的数值、布尔开关，模型在这些字段上选不出 Runtime 没有实现的东西。例外只有几处：按 id 引用其他条目的字段、有长度上限的坐标列表与升级列表，以及 Shooter 的 bgm，一个不限内容的字符串，Runtime 只把它当作合成 BGM 的种子。' },
			{ title: 'RFC 6902 补丁链', body: '每个 Mod 只存相对父级的补丁，生效 DSL 等于 Runtime 基线沿父链逐层应用补丁。会增删元素的集合以稳定 id 为 key，所以 /enemies/<id>/count 这样的路径在很深的 Fork 链里也不会错位。' },
			{ title: '绝不生成可执行代码', body: 'AI 只产出 DSL，由 Runtime 解释执行，没有 eval。模型调用全部经过后端，API key、限流、配额和审计都留在服务端。' },
		],
		tradeoff: '代价也写在决策记录里：用户能创造的上限，等于每个 Runtime 预埋的素材和机制数量。',
		tradeoffLink: '查看决策记录',
		exampleTitle: '一条真实的补丁',
		exampleLead: '下面四个操作把 Shooter 的基线 DSL 变成 golden 文件。「之前」和「之后」两列在构建本站时直接从这两个文件里读出。',
		tableCaption: 'Fork 补丁的四个操作，以及每个路径在基线和 golden 文件里的值',
		columns: { op: '操作', path: '路径', before: '之前', after: '之后' },
		absent: '不存在',
		removed: '已删除',
		total: (before, after) => `敌人总数从 ${before} 变为 ${after}，Go 和 GDScript 两端的测试都断言这个数。`,
		sourcesLabel: '出处',
		sources: { prompt: '提示词与补丁', baseline: '基线 DSL', golden: 'golden 文件', goTest: 'Go 测试', godotTest: 'Godot 测试' },
		readMore: '阅读 Mod DSL 设计',
	},
	architecture: {
		eyebrow: '03 · 架构',
		title: '一个 Godot 客户端，|一个 Go 后端，|一份共享契约',
		lead: '当前不拆微服务。业务边界靠目录、接口、装配和自动检查落实，由仓库里的门禁脚本守护。',
		client: {
			title: 'Godot 4.6 客户端',
			points: ['单一工程，带五个导出预设', 'AppRoot 装配七个纵向 feature 切片', 'Shell 与 Runtime 只经 GameSession 交换数据'],
		},
		server: {
			title: 'Go 后端',
			points: ['gin + GORM 模块化单体，七个领域 installer', 'AI 编排：调用模型、应用补丁、按 Schema 校验、有限次重试、记录审计', '开发用免 CGO 的 SQLite，生产目标是 PostgreSQL'],
		},
		link: 'HTTPS · JSON',
		contract: {
			title: '共享契约：Mod DSL 的 JSON Schema',
			body: '客户端的 GDScript 和后端的 Go 各有一份 RFC 6902 实现，同一份基线和 golden 文件把两端的结果钉成一致。Go 侧的补丁、迁移和校验代码在 packages/dsl，后端、CLI 和 MCP 共用。',
		},
		platformsLabel: '导出预设',
		roadmapNote: '五端真机验证还在路线图上。',
		roadmapLink: '查看开发计划',
		readMore: '阅读技术架构',
	},
	runtimes: {
		eyebrow: '04 · Runtime',
		title: '三个 Runtime，|各有一份 Schema |和一份基线',
		lead: 'Runtime 是官方维护的游戏逻辑框架。Mod 不能改 Runtime 本身，只能在它之上做增量修改，所以改完总能得到一个可玩的结果。',
		names: { shooter: 'Shooter', survivor: 'Survivor', tower_defense: 'Tower Defense' },
		descriptions: {
			shooter: '射击。可改玩家与武器、敌人、Boss、掉落物和关卡。',
			survivor: '生存，Vampire Survivors 一路的玩法。可改英雄、武器、敌人波次、成长和关卡。',
			tower_defense: '塔防。可改关卡、路径、防御塔、初始布置和波次。',
		},
		sectionsLabel: 'DSL 顶层分区',
		schemaLink: 'Schema',
		baselineLink: '基线 DSL',
		readMore: '阅读 Shooter 的 Runtime 内容清单',
	},
	developers: {
		eyebrow: '05 · 开发者',
		title: '命令行、|MCP 服务|和 Go SDK',
		lead: '三个入口共用同一套 DSL 代码和同一个后端客户端。',
		cli: { title: 'classic-games', body: '在终端里查看游戏和 Mod、让 AI 生成补丁，也可以离线校验 DSL、应用补丁。', link: 'CLI 文档' },
		mcp: { title: 'classic-games-mcp', body: '把同样的能力作为 MCP 工具交给 AI 助手：离线的 Schema、校验、补丁工具，加上访问后端的游戏与 Mod 工具。默认走 stdio，可以改用 HTTP，也可以只读运行。', link: 'MCP 文档' },
		sdk: { title: 'github.com/yldm-tech/classic-games/packages/sdk', body: '后端 HTTP API 的类型化 Go 客户端。CLI 和 MCP 服务都构建在它之上。', link: 'Go SDK 文档' },
	},
	start: {
		eyebrow: '06 · 从源码开始',
		title: '从源码跑起来',
		lead: '需要 Go 1.26 和 Godot 4.6.3（版本必须精确）。下面的目标都定义在仓库根目录的 Makefile 里。',
		codeLabel: '终端命令',
		lines: [
			{ kind: 'command', text: CLONE_PLACEHOLDER },
			{ kind: 'command', text: 'cd classic-games' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 启动后端，默认监听 :8080。未设置 ANTHROPIC_API_KEY 时使用确定性的本地 provider' },
			{ kind: 'command', text: 'make dev' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 后端测试' },
			{ kind: 'command', text: 'make test' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 导入 Godot 工程的资源' },
			{ kind: 'command', text: 'make import GODOT=/path/to/godot' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# 在本地复现 Go 与 Godot 的全部 CI 门禁' },
			{ kind: 'command', text: 'make ci GODOT=/path/to/godot' },
		],
		guideLink: '完整步骤见快速开始',
		repoLink: '在 GitHub 上查看源码',
	},
	notFound: { title: '页面不存在', body: '这个地址下没有内容。', home: '回到首页', docs: '文档索引' },
	footer: {
		tagline: 'AI 驱动的小游戏创作与社区平台。',
		docsHeading: '文档',
		docsIndex: '文档索引',
		architecture: '技术架构',
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
		privacyNote: '本站不使用分析或追踪脚本，也不加载第三方字体。',
	},
};

const en: LandingStrings = {
	meta: {
		title: 'Classic Games — fork a game and change it in plain language',
		description: 'Classic Games is an AI-driven platform for creating and sharing small games. Describe a change in plain language; the AI only produces a Mod DSL patch constrained by a JSON Schema, never executable code.',
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
		status: 'Pre-release · source builds only',
		title: 'Fork a game. |Describe the change. |Publish your version.',
		lead: 'Classic Games is an AI-driven platform for creating and sharing small games. You describe the change you want in plain language, and the AI answers with a Mod DSL patch: JSON constrained by a JSON Schema, not executable code.',
		primaryCta: 'Start from source',
		secondaryCta: 'Read the docs',
		note: 'There are no public builds and no app store releases yet.',
	},
	console: {
		ariaLabel: 'Example: how one sentence becomes a DSL patch',
		promptLabel: 'Prompt',
		prompt: '把飞机换成猫,加只鸟,删掉炮台',
		promptTranslation: 'Swap the plane for a cat, add a bird, remove the turret',
		patchLabel: 'AI output · RFC 6902 patch',
		checksLabel: 'Checks',
		checkSchema: 'Effective DSL validates against the shooter-1.0.0 schema',
		checkParity: 'Go and GDScript apply it to the same result',
		source: 'The prompt and patch come from the repository’s test fixtures, not from a recorded model call.',
	},
	flow: {
		eyebrow: '01 · Flow',
		title: 'Four steps |from fork to publish',
		lead: 'The model is not “create a game from nothing”. It is an incremental change to a game that already runs, which is the part AI is good at.',
		steps: [
			{ title: 'Fork a game that already runs', body: 'Every creation starts from an officially maintained runtime. A fork stores only a patch against its parent, not a copy of the game.' },
			{ title: 'Describe the change in plain language', body: 'For example: “swap the plane for a cat, add a bird, remove the turret”. No engine to learn and no code to write.' },
			{ title: 'The AI edits the Mod DSL, nothing else', body: 'The model returns an RFC 6902 patch. The backend applies it and validates the effective DSL against the JSON Schema; on failure it feeds the error back to the model for a bounded number of retries.' },
			{ title: 'Publish, and let others build on it', body: 'A published mod can be played, liked, commented on and forked again, so one game grows into a fork tree.' },
		],
	},
	forkTree: {
		ariaLabel: 'Sketch of a fork tree',
		rootTag: 'Official baseline',
		forkTag: 'Fork',
		caption: 'Titles follow the example in the vision doc. The cover art comes from the client’s seed catalogue (apps/client/assets/covers) and is used here only to sketch the shape of a fork tree.',
		coverAlt: {
			ember: 'Abstract cover: an orange sun on the horizon above a glowing track',
			volt: 'Abstract cover: a neon green lightning bolt over a perspective grid',
			foundry: 'Abstract cover: an isometric diamond grid with a few tiles lit orange and green',
			ashfall: 'Abstract cover: the silhouette of a castle on a peak under falling embers',
		},
	},
	bet: {
		eyebrow: '02 · The bet',
		title: 'A schema fences in |what the AI can output',
		lead: 'The Mod DSL is JSON that describes what a mod changes on top of a runtime. One JSON Schema is the constraint on the AI’s output, the basis for backend validation and the contract the runtime loads.',
		pillars: [
			{ title: 'Enums, ranges, switches', body: 'Almost every field is one of three kinds: an enum picked from what the runtime ships, a number with a range, or a boolean. On those fields the model cannot pick something the runtime does not implement. The few exceptions are fields that reference another entry by id, length-capped lists of coordinates and upgrades, and Shooter’s bgm, a free-form string the runtime only uses as the seed for a synthesised tune.' },
			{ title: 'RFC 6902 patch chains', body: 'A mod stores only a patch against its parent; the effective DSL is the runtime baseline with every patch on the chain applied in order. Collections that gain and lose members are maps keyed by stable id, so a path like /enemies/<id>/count stays valid deep in a fork chain.' },
			{ title: 'Never executable code', body: 'The AI only produces DSL, which the runtime interprets; there is no eval. Every model call goes through the backend, which keeps the API keys, rate limits, quotas and audit log.' },
		],
		tradeoff: 'The cost is on record too: what a user can create is bounded by the content and mechanics each runtime ships.',
		tradeoffLink: 'See the decision log (Chinese)',
		exampleTitle: 'A real patch',
		exampleLead: 'These four operations turn the Shooter baseline DSL into the golden file. The “before” and “after” columns are read from those two files when this site is built.',
		tableCaption: 'The four operations of the fork patch, with the value at each path in the baseline and in the golden file',
		columns: { op: 'Op', path: 'Path', before: 'Before', after: 'After' },
		absent: 'absent',
		removed: 'removed',
		total: (before, after) => `Total enemy count goes from ${before} to ${after}, the number both the Go and the GDScript tests assert.`,
		sourcesLabel: 'Sources',
		sources: { prompt: 'Prompt and patch', baseline: 'Baseline DSL', golden: 'Golden file', goTest: 'Go test', godotTest: 'Godot test' },
		readMore: 'Read the Mod DSL design (Chinese)',
	},
	architecture: {
		eyebrow: '03 · Architecture',
		title: 'One Godot client, |one Go backend, |one shared contract',
		lead: 'There are no microservices. Domain boundaries are enforced through directories, interfaces, wiring and automated checks that run as gates in the repository.',
		client: {
			title: 'Godot 4.6 client',
			points: ['A single project with five export presets', 'AppRoot composes seven vertical feature slices', 'Shell and runtime exchange data only through GameSession'],
		},
		server: {
			title: 'Go backend',
			points: ['A gin + GORM modular monolith built from seven domain installers', 'AI orchestration: call the model, apply the patch, validate against the schema, retry a bounded number of times, record the call', 'CGO-free SQLite in development; PostgreSQL is the production target'],
		},
		link: 'HTTPS · JSON',
		contract: {
			title: 'Shared contract: the Mod DSL JSON Schemas',
			body: 'The GDScript client and the Go backend each implement RFC 6902, and a shared baseline and golden file pin both to the same result. The Go patch, migration and validation code lives in packages/dsl and is shared by the backend, the CLI and the MCP server.',
		},
		platformsLabel: 'Export presets',
		roadmapNote: 'Verifying all five exports on real devices is still on the roadmap.',
		roadmapLink: 'See the roadmap (Chinese)',
		readMore: 'Read the architecture doc (Chinese)',
	},
	runtimes: {
		eyebrow: '04 · Runtimes',
		title: 'Three runtimes, |each with a schema and a baseline',
		lead: 'A runtime is an officially maintained game framework. A mod cannot change the runtime itself, only make incremental changes on top of it, which is why the result is always playable.',
		names: { shooter: 'Shooter', survivor: 'Survivor', tower_defense: 'Tower Defense' },
		descriptions: {
			shooter: 'Shooter. Mods change the player and weapon, enemies, the boss, drops and the stage.',
			survivor: 'Survivor, in the Vampire Survivors mould. Mods change the hero, weapon, enemy waves, progression and stage.',
			tower_defense: 'Tower defense. Mods change the stage, path, towers, starting placements and waves.',
		},
		sectionsLabel: 'Top-level DSL sections',
		schemaLink: 'Schema',
		baselineLink: 'Baseline DSL',
		readMore: 'Read the Shooter runtime content list (Chinese)',
	},
	developers: {
		eyebrow: '05 · Developers',
		title: 'A CLI, an MCP server |and a Go SDK',
		lead: 'Three entry points that share the same DSL code and the same backend client.',
		cli: { title: 'classic-games', body: 'Browse games and mods, ask the AI for a patch, and validate or patch DSL offline, all from a terminal.', link: 'CLI docs' },
		mcp: { title: 'classic-games-mcp', body: 'Gives AI assistants the same capabilities as MCP tools: offline schema, validate and patch tools, plus backend tools for games and mods. It runs over stdio by default, can serve HTTP, and has a read-only mode.', link: 'MCP docs' },
		sdk: { title: 'github.com/yldm-tech/classic-games/packages/sdk', body: 'A typed Go client for the backend HTTP API. The CLI and the MCP server are both built on it.', link: 'Go SDK docs' },
	},
	start: {
		eyebrow: '06 · From source',
		title: 'Run it from source',
		lead: 'You need Go 1.26 and Godot 4.6.3 (the exact version). Every target below is defined in the Makefile at the repository root.',
		codeLabel: 'Terminal commands',
		lines: [
			{ kind: 'command', text: CLONE_PLACEHOLDER },
			{ kind: 'command', text: 'cd classic-games' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Start the backend on :8080. Without ANTHROPIC_API_KEY it uses a deterministic local provider' },
			{ kind: 'command', text: 'make dev' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Backend tests' },
			{ kind: 'command', text: 'make test' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Import the Godot project’s resources' },
			{ kind: 'command', text: 'make import GODOT=/path/to/godot' },
			{ kind: 'blank', text: '' },
			{ kind: 'comment', text: '# Reproduce every Go and Godot CI gate locally' },
			{ kind: 'command', text: 'make ci GODOT=/path/to/godot' },
		],
		guideLink: 'Full steps in Getting started',
		repoLink: 'View the source on GitHub',
	},
	notFound: { title: 'Page not found', body: 'Nothing lives at this address.', home: 'Back to home', docs: 'Docs index' },
	footer: {
		tagline: 'An AI-driven platform for creating and sharing small games.',
		docsHeading: 'Docs',
		docsIndex: 'Docs index (Chinese)',
		architecture: 'Architecture (Chinese)',
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
		privacyNote: 'This site uses no analytics or trackers and loads no third-party fonts.',
	},
};

export const landing: Record<Locale, LandingStrings> = { 'zh-CN': zh, en };
