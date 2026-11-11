import type { ImageMetadata } from 'astro';

// The games the landing page lists, read at build time from the game manifests (apps/client/games/<id>/game.json), the same files the launcher reads at startup. Nothing is copied into apps/web: a game that is added to apps/client/games appears here on the next build, with its key art (`art.image`) and, when its manifest names one, its in-game capture (`site.screenshot`), both taken from the game's own directory. A game without either picture is still listed; Games.astro draws a panel in the game's colours instead.
//
// The launcher's own check (make games-check) is what decides whether a manifest is valid. This module only verifies the handful of fields the page prints, so that a mistake fails the build with a message that names the file instead of rendering "undefined".

interface Bilingual {
	zh: string;
	en: string;
}

export interface GameInfo {
	/** Manifest id, which is the game's directory name. */
	key: string;
	name: Bilingual;
	genre: Bilingual;
	tagline: Bilingual;
	how: Bilingual;
	/** Local players the game supports. */
	players: { min: number; max: number };
	/** Number of achievements the manifest defines. */
	achievements: number;
	/** The palette the launcher draws the game's placeholder art with, as CSS colours. */
	colors: { top: string; bottom: string; title: string };
	/** Key art shown by the launcher, when the game ships a picture. */
	art?: ImageMetadata;
	artAlt?: Bilingual;
	/** A capture of the game running inside the launcher, when the game ships one for the site. */
	shot?: ImageMetadata;
	shotAlt?: Bilingual;
}

type Json = Record<string, unknown>;

const manifests = import.meta.glob<Json>('../../../client/games/*/game.json', { eager: true, import: 'default' });
// Pictures are loaded on demand, so only the two a manifest names are pulled into the build, not every sprite of every game. The glob reaches into sub-directories because a manifest may keep its key art in one (art.image is any path inside the game's directory).
const pictures = import.meta.glob<ImageMetadata>('../../../client/games/*/**/*.{png,jpg,jpeg,webp}', { import: 'default' });

function fail(file: string, message: string): never {
	throw new Error(`${file}: ${message}. The site lists games from their manifests; fix the manifest (make games-check reports every problem).`);
}

function record(file: string, value: unknown, field: string): Json {
	if (typeof value !== 'object' || value === null || Array.isArray(value)) fail(file, `"${field}" must be an object`);
	return value as Json;
}

function bilingual(file: string, value: unknown, field: string): Bilingual {
	const text = record(file, value, field);
	if (typeof text.zh !== 'string' || text.zh.trim() === '' || typeof text.en !== 'string' || text.en.trim() === '') fail(file, `"${field}" must be { "zh": text, "en": text }`);
	return { zh: text.zh, en: text.en };
}

function color(file: string, value: unknown, field: string): string {
	if (typeof value !== 'string' || !/^[0-9a-fA-F]{6}$/.test(value)) fail(file, `"${field}" must be a colour as RRGGBB`);
	return `#${value}`;
}

async function picture(file: string, directory: string, name: unknown, field: string): Promise<ImageMetadata> {
	if (typeof name !== 'string' || name === '' || name.startsWith('/') || name.includes('..') || name.includes('\\')) fail(file, `"${field}" must be a picture file inside the game's own directory`);
	const load = pictures[`${directory}/${name}`];
	if (load === undefined) fail(file, `"${field}" names ${name}, which is not a .png, .jpg, .jpeg or .webp file (lowercase extension) inside the game's directory`);
	return load();
}

async function read(path: string, manifest: Json): Promise<GameInfo> {
	const directory = path.slice(0, path.lastIndexOf('/'));
	const folder = directory.slice(directory.lastIndexOf('/') + 1);
	const file = `apps/client/games/${folder}/game.json`;
	if (manifest.id !== folder) fail(file, `"id" must be the directory name "${folder}"`);
	const players = record(file, manifest.players, 'players');
	if (typeof players.min !== 'number' || typeof players.max !== 'number' || players.min < 1 || players.max < players.min) fail(file, '"players" must be { "min": n, "max": n }');
	if (!Array.isArray(manifest.achievements)) fail(file, '"achievements" must be a list');
	const art = record(file, manifest.art, 'art');
	const titles = record(file, manifest.colors, 'colors');
	const site = manifest.site === undefined ? {} : record(file, manifest.site, 'site');
	const game: GameInfo = {
		key: folder,
		name: bilingual(file, manifest.name, 'name'),
		genre: bilingual(file, manifest.genre, 'genre'),
		tagline: bilingual(file, manifest.tagline, 'tagline'),
		how: bilingual(file, manifest.how, 'how'),
		players: { min: players.min, max: players.max },
		achievements: manifest.achievements.length,
		colors: { top: color(file, art.top, 'art.top'), bottom: color(file, art.bottom, 'art.bottom'), title: color(file, titles.title, 'colors.title') },
	};
	if (art.image !== undefined) {
		game.art = await picture(file, directory, art.image, 'art.image');
		if (site.art_alt !== undefined) game.artAlt = bilingual(file, site.art_alt, 'site.art_alt');
	}
	if (site.screenshot !== undefined) {
		game.shot = await picture(file, directory, site.screenshot, 'site.screenshot');
		if (site.screenshot_alt !== undefined) game.shotAlt = bilingual(file, site.screenshot_alt, 'site.screenshot_alt');
	}
	return game;
}

// Sorted by id, the order the launcher's catalog uses.
const paths = Object.keys(manifests).sort();
if (paths.length === 0) throw new Error('No game manifest found under apps/client/games/*/game.json. The site lists games from those files.');

export const games: GameInfo[] = await Promise.all(paths.map((path) => read(path, manifests[path] as Json)));

/** Total number of achievements across the catalog, as the launcher's achievements screen counts them. */
export const achievementTotal = games.reduce((sum, game) => sum + game.achievements, 0);
