import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';
import { DEFAULT_SITE_URL, REPO_URL, SITE_NAME, repoEdit } from './src/config/site.ts';
import { checkBuiltLinks } from './src/integrations/check-built-links.ts';
import { checkBuiltPages } from './src/integrations/check-built-pages.ts';
import { docsSync } from './src/integrations/docs-sync.ts';

export default defineConfig({
	site: process.env.SITE_URL ?? DEFAULT_SITE_URL,
	trailingSlash: 'always',
	integrations: [
		// Must come before Starlight so the synced Markdown exists when the docs collection is loaded.
		docsSync(),
		starlight({
			title: SITE_NAME,
			description: '经典厅（Classic Games）：开源的主机风格游戏启动器，自带一组经典类型的原创游戏，用手柄或键盘游玩。',
			defaultLocale: 'root',
			locales: {
				root: { label: '简体中文', lang: 'zh-CN' },
				en: { label: 'English', lang: 'en' },
			},
			// The 404 page is src/pages/404.astro, in the landing page's layout.
			disable404Route: true,
			social: [{ icon: 'github', label: 'GitHub', href: REPO_URL }],
			editLink: { baseUrl: repoEdit('apps/web') },
			customCss: ['./src/styles/tokens.css', './src/styles/starlight.css'],
			components: {
				SiteTitle: './src/components/starlight/SiteTitle.astro',
			},
			sidebar: [
				{
					label: '开发者',
					translations: { en: 'Developers' },
					items: [{ autogenerate: { directory: 'developers' } }],
				},
				{
					label: '项目文档',
					translations: { en: 'Project docs (Chinese)' },
					items: [{ autogenerate: { directory: 'docs' } }],
				},
				{
					label: '法律文本',
					translations: { en: 'Legal (Chinese)' },
					items: [{ autogenerate: { directory: 'legal' } }],
				},
			],
			plugins: [
				starlightLinksValidator({
					// The project docs exist in Chinese only, so English pages legitimately link to fallback pages.
					errorOnFallbackPages: false,
					// docs-sync.ts writes links between synced docs relative to the page, so the same Markdown stays inside the current locale under both "/" and "/en/". The validator cannot resolve relative links and rejects them by default; check-built-links.ts resolves every href in the built HTML, anchors included, so they are still verified.
					errorOnRelativeLinks: false,
				}),
			],
		}),
		checkBuiltLinks(),
		checkBuiltPages(),
	],
});
