import { defineCollection } from 'astro:content';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
	// Holds the hand-written developer pages plus the Markdown that src/integrations/docs-sync.ts copies in from the repository's docs/ directory.
	docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
	// Overrides for Starlight's built-in UI strings.
	i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
