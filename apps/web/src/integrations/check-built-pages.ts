import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { decodeEntities, listHtml } from './check-built-links.ts';

// Checks on the built HTML that are about what a page says, not where its links go. Each rule pins a defect that neither `astro check` nor the link checks can see, and that only shows up because the site's default locale is not English.

const HAN = /\p{Script=Han}/u;

/** Starlight's Chinese strings for the code block UI (copy button tooltip, copied message, title of an untitled terminal frame). Starlight's built-in English dictionary has no expressiveCode.* keys, so without the overrides in src/content/i18n/en.json English pages fall back to the default locale and show these. */
const ZH_CODE_BLOCK_UI = ['复制到剪贴板', '复制成功', '终端窗口'];

/** Pagefind UI strings the search dialog shows. Pagefind's own language detection does not run in the bundled build, so every string that is not passed explicitly stays English; src/content/i18n/zh-CN.json supplies them for the Chinese locale. */
const SEARCH_UI_KEYS = ['placeholder', 'clear_search', 'load_more', 'search_label', 'filters_label', 'zero_results', 'many_results', 'one_result', 'alt_search', 'search_suggestion', 'searching'];

function attribute(tag: string | undefined, name: string): string | undefined {
	if (!tag) return undefined;
	const match = new RegExp(`\\s${name}="([^"]*)"`).exec(tag);
	return match ? decodeEntities(match[1] ?? '') : undefined;
}

function firstTag(html: string, name: string): string | undefined {
	return new RegExp(`<${name}[\\s>][^>]*`).exec(html)?.[0];
}

function titleOf(html: string): string | undefined {
	return /<title>([^<]*)<\/title>/.exec(html)?.[1];
}

/** Check every page below `outDir`. Exported so the checks can be run against an existing build without building again. */
export function findBuiltPageProblems(outDir: string): string[] {
	const problems: string[] = [];

	for (const page of listHtml(outDir)) {
		const pagePath = `/${path.relative(outDir, page).split(path.sep).join('/')}`;
		const html = readFileSync(page, 'utf8');
		const uiLang = attribute(firstTag(html, 'html'), 'lang');
		// Starlight serves an untranslated page under the other locale with the content element marked in the content's own language, so Chinese code block UI inside such a fallback page is consistent. Only content that is itself English is held to English UI strings.
		const contentLang = attribute(firstTag(html, 'main'), 'lang') ?? uiLang;

		if (contentLang === 'en') {
			for (const text of ZH_CODE_BLOCK_UI) {
				if (html.includes(text)) problems.push(`${pagePath}: English content shows the Chinese code block string "${text}"`);
			}
		}

		const rawTranslations = attribute(firstTag(html, 'site-search'), 'data-translations');
		if (rawTranslations !== undefined) {
			const translations = JSON.parse(rawTranslations) as Record<string, string>;
			if (uiLang === 'en') {
				for (const [key, value] of Object.entries(translations)) {
					if (HAN.test(value)) problems.push(`${pagePath}: English search UI string "${key}" is Chinese: "${value}"`);
				}
			} else {
				for (const key of SEARCH_UI_KEYS) {
					const value = translations[key];
					if (value === undefined) problems.push(`${pagePath}: search UI string "${key}" is not translated for lang="${uiLang}", so the dialog shows it in English`);
					else if (!HAN.test(value)) problems.push(`${pagePath}: search UI string "${key}" for lang="${uiLang}" is not Chinese: "${value}"`);
				}
			}
		}
	}

	// A static host serves 404.html for every unknown path, some of them with status 200. The page must not present itself as the landing page to a crawler.
	const notFoundPath = path.join(outDir, '404.html');
	const indexPath = path.join(outDir, 'index.html');
	if (!existsSync(notFoundPath)) {
		problems.push('/404.html: not built');
	} else {
		const notFound = readFileSync(notFoundPath, 'utf8');
		if (!/<meta name="robots" content="[^"]*noindex/.test(notFound)) problems.push('/404.html: no <meta name="robots" content="noindex">');
		if (/<link rel="canonical"/.test(notFound)) problems.push('/404.html: declares a canonical URL');
		if (/<link rel="alternate"[^>]*\shreflang=/.test(notFound)) problems.push('/404.html: declares hreflang alternates');
		if (/<meta property="og:url"/.test(notFound)) problems.push('/404.html: declares og:url');
		const notFoundTitle = titleOf(notFound);
		if (!notFoundTitle) problems.push('/404.html: no <title>');
		else if (existsSync(indexPath) && notFoundTitle === titleOf(readFileSync(indexPath, 'utf8'))) problems.push(`/404.html: reuses the landing page's <title> "${notFoundTitle}"`);
	}

	return problems;
}

export function checkBuiltPages(): AstroIntegration {
	return {
		name: 'classic-games-check-built-pages',
		hooks: {
			'astro:build:done': ({ dir, logger }) => {
				const problems = findBuiltPageProblems(fileURLToPath(dir));
				if (problems.length > 0) {
					throw new Error(`Found ${problems.length} problem(s) in the built pages:\n${problems.map((problem) => `  - ${problem}`).join('\n')}`);
				}
				logger.info('built pages: code block and search UI strings match each page language, 404 page is noindex');
			},
		},
	};
}
