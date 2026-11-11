import type { ImageMetadata } from 'astro';
import catalogSource from '../../../client/launcher/launcher_catalog.gd?raw';
import guideSource from '../../../client/launcher/launcher_game_guide.gd?raw';
import shooterArt from '../assets/key-art/shooter.jpg';
import survivorArt from '../assets/key-art/survivor.jpg';
import towerDefenseArt from '../assets/key-art/tower-defense.jpg';
import shooterShot from '../assets/launcher/game-shooter.png';
import survivorShot from '../assets/launcher/game-survivor.png';
import towerDefenseShot from '../assets/launcher/game-tower-defense.png';
import type { RuntimeKey } from './runtimes.ts';

// The games the landing page lists. Names, genres and taglines are the launcher's own catalog entries (apps/client/launcher/launcher_catalog.gd) and the "how it plays" paragraphs are the launcher's own guide texts (apps/client/launcher/launcher_game_guide.gd). GDScript cannot be imported as data, so the strings are copied here and every one of them is checked against the source file at build time: if the launcher's text changes, the build fails until this copy is updated.

interface Bilingual {
	zh: string;
	en: string;
}

export interface GameInfo {
	/** Catalog id, which is also the runtime name. */
	key: RuntimeKey;
	name: Bilingual;
	genre: Bilingual;
	tagline: Bilingual;
	how: Bilingual;
	/** Number of achievements the catalog defines for the game. */
	achievements: number;
	/** Key art shown by the launcher, copied from apps/client/launcher/art. */
	art: ImageMetadata;
	/** A capture of the game running inside the launcher. */
	shot: ImageMetadata;
}

export const games: GameInfo[] = [
	{
		key: 'shooter',
		name: { zh: '星环巡航', en: 'ORBIT PATROL' },
		genre: { zh: '飞行射击', en: 'ARENA SHOOTER' },
		tagline: { zh: '清空这片星域，再击落守在尽头的机甲。', en: 'Clear the sector, then bring down the mech that guards it.' },
		how: {
			zh: '武器自动开火，你只管走位。击落全部敌机和首领即通关；生命归零或倒计时结束，本局结束。按住加速时移动更快，击落得分翻倍。护盾抵消下一次伤害，用过后需要冷却。',
			en: 'The weapon fires by itself; you fly. Destroy every enemy and the boss to clear. The run ends when your HP reaches zero or the countdown runs out. Holding boost makes you faster and doubles the score of each kill. The shield absorbs the next hit and then needs to recharge.',
		},
		achievements: 3,
		art: shooterArt,
		shot: shooterShot,
	},
	{
		key: 'survivor',
		name: { zh: '长夜草原', en: 'MEADOW VIGIL' },
		genre: { zh: '生存动作', en: 'SURVIVAL ACTION' },
		tagline: { zh: '只管走位，武器自己开火。撑过三分钟。', en: 'You move, the weapon fires itself. Last three minutes.' },
		how: {
			zh: '武器自动攻击，你只管走位。拾取敌人掉落的经验球升级，每次升级依次强化伤害、攻速、弹数和移速。撑到倒计时结束即通关；生命归零则失败。',
			en: 'The weapon attacks by itself; you move. Collect the orbs enemies drop to level up, and each level strengthens damage, attack speed, projectile count and movement speed in turn. Survive until the countdown ends to clear; you lose when your HP reaches zero.',
		},
		achievements: 4,
		art: survivorArt,
		shot: survivorShot,
	},
	{
		key: 'tower_defense',
		name: { zh: '隘口守卫', en: 'GATEWATCH' },
		genre: { zh: '塔防', en: 'TOWER DEFENSE' },
		tagline: { zh: '沿路布下箭塔与炮台，别让一个敌人走到终点。', en: 'Line the road with towers and let nothing reach the end.' },
		how: {
			zh: '敌人沿道路走向终点，每漏过一个，基地就掉血。用金币在任意位置放塔，击倒敌人可以拿回金币。挡下全部波次即通关；基地生命归零则失败。',
			en: "Enemies walk the road to its end, and each one that gets through damages the base. Spend gold to place towers anywhere; defeating enemies earns gold back. Stop every wave to clear; you lose when the base's HP reaches zero.",
		},
		achievements: 4,
		art: towerDefenseArt,
		shot: towerDefenseShot,
	},
];

/** The text of one catalog entry: from its `"id": "<key>"` line up to the next entry or the end of the list. */
function catalogEntry(key: string): string {
	const start = catalogSource.indexOf(`"id": "${key}"`);
	if (start === -1) throw new Error(`apps/client/launcher/launcher_catalog.gd has no game with id "${key}". Update src/data/games.ts.`);
	const next = catalogSource.indexOf('"runtime":', catalogSource.indexOf('"runtime":', start) + 1);
	return catalogSource.slice(start, next === -1 ? undefined : next);
}

function assertQuoted(source: string, text: string, file: string, what: string): void {
	if (!source.includes(JSON.stringify(text))) throw new Error(`${file} no longer contains the ${what} ${JSON.stringify(text)}. Update src/data/games.ts to match the launcher.`);
}

const catalogIds = [...catalogSource.matchAll(/"id": "([a-z_]+)", *\n\s*"runtime":/g)].map((match) => match[1]);
if (catalogIds.join(',') !== games.map((game) => game.key).join(',')) {
	throw new Error(`The launcher catalog lists the games [${catalogIds.join(', ')}] but src/data/games.ts lists [${games.map((game) => game.key).join(', ')}]. Update src/data/games.ts and the landing copy.`);
}

for (const game of games) {
	const entry = catalogEntry(game.key);
	for (const field of [game.name, game.genre, game.tagline]) {
		assertQuoted(entry, field.zh, 'apps/client/launcher/launcher_catalog.gd', `"${game.key}" text`);
		assertQuoted(entry, field.en, 'apps/client/launcher/launcher_catalog.gd', `"${game.key}" text`);
	}
	assertQuoted(guideSource, game.how.zh, 'apps/client/launcher/launcher_game_guide.gd', `"${game.key}" guide text`);
	assertQuoted(guideSource, game.how.en, 'apps/client/launcher/launcher_game_guide.gd', `"${game.key}" guide text`);
	const achievementIds = entry.match(/\{"id": "[a-z_]+", "icon":/g) ?? [];
	if (achievementIds.length !== game.achievements) {
		throw new Error(`The launcher catalog defines ${achievementIds.length} achievements for "${game.key}" but src/data/games.ts says ${game.achievements}. Update src/data/games.ts.`);
	}
}

/** Total number of achievements across the catalog, as the launcher's achievements screen counts them. */
export const achievementTotal = games.reduce((sum, game) => sum + game.achievements, 0);
