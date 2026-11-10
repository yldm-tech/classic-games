import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';

// starlight-links-validator checks links written in Markdown content. It cannot see links in hand-written Astro pages such as the landing page, or in the site header and footer, and it does not resolve the relative links docs-sync.ts writes between synced docs. This integration closes that gap by checking every internal href and src in the built HTML against the files that were actually emitted, including #fragment targets. It also fails when a page under a locale prefix links out of that locale although the target exists inside it.

const ATTRIBUTE = /\s(?:href|src)="([^"]*)"/g;
const ID_ATTRIBUTE = /\sid="([^"]*)"/g;
const HAS_SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

/** URL prefix of every locale that is not served from the site root. Keep in step with `locales` in astro.config.ts. */
const LOCALE_PREFIXES = ['/en/'];

export function listHtml(dir: string): string[] {
	const found: string[] = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) found.push(...listHtml(full));
		else if (entry.name.endsWith('.html')) found.push(full);
	}
	return found;
}

export function decodeEntities(value: string): string {
	return value.replaceAll('&amp;', '&').replaceAll('&#38;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
}

function safeDecode(value: string): string {
	try {
		return decodeURIComponent(value);
	} catch {
		return value;
	}
}

/** Return the opening tag of every <a> element in a page. Attribute values are skipped as quoted strings, so a ">" inside one does not end the tag. */
function anchorTags(html: string): string[] {
	const tags: string[] = [];
	let from = 0;
	for (;;) {
		const start = html.indexOf('<a', from);
		if (start === -1) return tags;
		const after = html[start + 2] ?? '';
		if (after !== ' ' && after !== '\n' && after !== '\t' && after !== '\r') {
			from = start + 2;
			continue;
		}
		let index = start + 2;
		let quote: string | undefined;
		while (index < html.length) {
			const char = html[index];
			if (quote) {
				if (char === quote) quote = undefined;
			} else if (char === '"' || char === "'") quote = char;
			else if (char === '>') break;
			index++;
		}
		tags.push(html.slice(start, index + 1));
		from = index + 1;
	}
}

/** Resolve a URL pathname to the file the static host would serve for it. */
function resolveBuiltFile(outDir: string, pathname: string): string | undefined {
	const target = path.join(outDir, safeDecode(pathname));
	if (existsSync(target) && statSync(target).isFile()) return target;
	for (const candidate of [path.join(target, 'index.html'), `${target}.html`]) {
		if (existsSync(candidate)) return candidate;
	}
	return undefined;
}

export interface BuiltLinksReport {
	problems: string[];
	checked: number;
	pages: number;
}

/** Check every page below `outDir`. Exported so the checks can be run against an existing build without building again. */
export function findBuiltLinkProblems(outDir: string, base = '/'): BuiltLinksReport {
	const idCache = new Map<string, Set<string>>();
	const idsOf = (file: string): Set<string> => {
		let ids = idCache.get(file);
		if (!ids) {
			ids = new Set(Array.from(readFileSync(file, 'utf8').matchAll(ID_ATTRIBUTE), (match) => decodeEntities(match[1] ?? '')));
			idCache.set(file, ids);
		}
		return ids;
	};

	const problems: string[] = [];
	const pages = listHtml(outDir);
	let checked = 0;
	for (const page of pages) {
		const pagePath = `/${path.relative(outDir, page).split(path.sep).join('/')}`;
		const pageUrl = new URL(pagePath.replace(/index\.html$/, ''), 'http://site.invalid');
		const html = readFileSync(page, 'utf8');

		// A page under a locale prefix must keep the reader in that locale: a link to "/docs/x/" from "/en/..." switches the UI language, the sidebar and the search index. Language switchers are the exception and say so with hreflang.
		const localePrefix = LOCALE_PREFIXES.find((prefix) => pagePath.startsWith(prefix));
		if (localePrefix) {
			for (const tag of anchorTags(html)) {
				if (/\shreflang=/.test(tag)) continue;
				const raw = decodeEntities(/\shref="([^"]*)"/.exec(tag)?.[1] ?? '');
				if (raw === '' || raw.startsWith('#') || HAS_SCHEME.test(raw) || raw.startsWith('//')) continue;
				let pathname = new URL(raw, pageUrl).pathname;
				if (base !== '/' && pathname.startsWith(base)) pathname = `/${pathname.slice(base.length)}`;
				if (pathname.startsWith(localePrefix)) continue;
				const counterpart = resolveBuiltFile(outDir, `${localePrefix.slice(0, -1)}${pathname}`);
				if (counterpart?.endsWith('.html')) problems.push(`${pagePath}: "${raw}" leaves ${localePrefix} although ${localePrefix.slice(0, -1)}${pathname} exists`);
			}
		}

		for (const match of html.matchAll(ATTRIBUTE)) {
			const raw = decodeEntities(match[1] ?? '');
			if (raw === '' || HAS_SCHEME.test(raw) || raw.startsWith('//')) continue;
			checked++;
			const url = new URL(raw, pageUrl);
			let pathname = url.pathname;
			if (base !== '/' && pathname.startsWith(base)) pathname = `/${pathname.slice(base.length)}`;
			const file = raw.startsWith('#') ? page : resolveBuiltFile(outDir, pathname);
			if (!file) {
				problems.push(`${pagePath}: "${raw}" does not match any built file`);
				continue;
			}
			const fragment = safeDecode(url.hash.slice(1));
			if (fragment && file.endsWith('.html') && !idsOf(file).has(fragment)) {
				problems.push(`${pagePath}: "${raw}" points to a missing #${fragment} anchor`);
			}
		}
	}

	return { problems: Array.from(new Set(problems)), checked, pages: pages.length };
}

export function checkBuiltLinks(): AstroIntegration {
	let base = '/';
	return {
		name: 'forgeplay-check-built-links',
		hooks: {
			'astro:config:done': ({ config }) => {
				base = config.base.endsWith('/') ? config.base : `${config.base}/`;
			},
			'astro:build:done': ({ dir, logger }) => {
				const report = findBuiltLinkProblems(fileURLToPath(dir), base);
				if (report.problems.length > 0) {
					throw new Error(`Found ${report.problems.length} internal link problem(s) in the built site:\n${report.problems.map((problem) => `  - ${problem}`).join('\n')}`);
				}
				logger.info(`checked ${report.checked} internal links across ${report.pages} pages, all resolve`);
			},
		},
	};
}
