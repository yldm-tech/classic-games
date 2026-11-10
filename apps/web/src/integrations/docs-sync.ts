import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { repoDir, repoEdit, repoFile } from '../config/site.ts';

// The public Markdown in <repo>/docs is the single source of truth. This module copies it into the Starlight content collection at build and dev time, adding the frontmatter Starlight requires and rewriting links so they resolve on the site. The output directories are git-ignored and fully regenerated, so nothing here is ever edited by hand.

/** Directory under the repository root that holds the public docs. */
const SOURCE_DIR = 'docs';

/** Directory under the repository root that must never be published or linked to. */
const INTERNAL_DIR = 'docs-internal';

/** Top-level folders inside src/content/docs that this module owns and regenerates. */
export const GENERATED_DIRS = ['docs', 'legal'] as const;

export interface DocsSyncPaths {
	/** Absolute path of the repository root. */
	repoRoot: string;
	/** Absolute path of the Starlight docs collection (src/content/docs). */
	contentDir: string;
}

export interface DocsSyncResult {
	written: number;
	unchanged: number;
	removed: number;
	total: number;
}

interface PlannedDoc {
	/** Repository-relative POSIX path of the source file, for example "docs/legal/terms.md". */
	source: string;
	/** Collection-relative POSIX path of the generated file, for example "legal/terms.md". */
	output: string;
	/** Site route of the generated page, for example "/legal/terms/". */
	route: string;
}

/** Map a source file under docs/ to its place in the collection and its route. */
function planDoc(relativeToDocs: string): PlannedDoc {
	const segments = relativeToDocs.split('/');
	const fileName = segments.pop() ?? '';
	const stem = fileName.replace(/\.md$/i, '').toLowerCase();
	const dirs = segments.map((segment) => segment.toLowerCase());
	// docs/legal/* gets its own top-level section so it can have its own sidebar group.
	const base = dirs[0] === 'legal' ? dirs : ['docs', ...dirs];
	const isIndex = stem === 'readme' || stem === 'index';
	const outputStem = isIndex ? 'index' : stem;
	const routeSegments = isIndex ? base : [...base, stem];
	return {
		source: `${SOURCE_DIR}/${relativeToDocs}`,
		output: [...base, `${outputStem}.md`].join('/'),
		route: `/${routeSegments.join('/')}/`,
	};
}

/** Link from one generated page to another, relative to the linking page. Starlight's fallback serves every synced page under each locale prefix as well ("/docs/x/" and "/en/docs/x/"), and both trees have the same shape, so a relative link keeps the reader in the locale they are in where a root-absolute route would always land in the default one. Routes end in "/" and the site is built with trailingSlash "always", so the page's own route is the base the browser resolves against. */
function relativeRoute(from: string, to: string): string {
	const relative = path.posix.relative(from, to);
	return relative === '' ? './' : `${relative}/`;
}

/** List every Markdown file below a directory as POSIX paths relative to it, sorted for stable output. */
function listMarkdown(dir: string, prefix = ''): string[] {
	const found: string[] = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name.startsWith('.')) continue;
		const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
		if (entry.isDirectory()) found.push(...listMarkdown(path.join(dir, entry.name), relative));
		else if (entry.isFile() && /\.md$/i.test(entry.name)) found.push(relative);
	}
	return found.sort();
}

/** Return [start, end) ranges of inline code spans in a line, so links inside code are left untouched. */
function codeSpanRanges(line: string): Array<[number, number]> {
	const ranges: Array<[number, number]> = [];
	let index = 0;
	while (index < line.length) {
		if (line[index] !== '`') {
			index++;
			continue;
		}
		let runEnd = index;
		while (runEnd < line.length && line[runEnd] === '`') runEnd++;
		const fence = line.slice(index, runEnd);
		let close = line.indexOf(fence, runEnd);
		// A closing run must be exactly as long as the opening run.
		while (close !== -1 && (line[close + fence.length] === '`' || line[close - 1] === '`')) {
			close = line.indexOf(fence, close + 1);
		}
		if (close === -1) {
			index = runEnd;
			continue;
		}
		ranges.push([index, close + fence.length]);
		index = close + fence.length;
	}
	return ranges;
}

function inRanges(position: number, ranges: Array<[number, number]>): boolean {
	return ranges.some(([start, end]) => position >= start && position < end);
}

/** Tell whether the link whose text ends at `closeBracket` is an image, by walking back to its opening bracket. */
function isImageLink(line: string, closeBracket: number, ranges: Array<[number, number]>): boolean {
	let depth = 0;
	for (let index = closeBracket; index >= 0; index--) {
		if (inRanges(index, ranges)) continue;
		const char = line[index];
		if (char === ']') depth++;
		else if (char === '[') {
			depth--;
			if (depth === 0) return index > 0 && line[index - 1] === '!';
		}
	}
	return false;
}

const INLINE_LINK_TAIL = /\]\(([^()\s]+)(\s+"[^"]*")?\)/g;
const REFERENCE_DEFINITION = /^( {0,3}\[[^\]]+\]:\s+)(\S+)(.*)$/;
const FENCE_OPEN = /^ {0,3}(`{3,}|~{3,})/;
const HAS_SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

type RewriteTarget = (target: string, isImage: boolean) => string;

/** Rewrite every Markdown link target in a line that is not inside inline code. */
function rewriteLine(line: string, rewrite: RewriteTarget): string {
	const definition = REFERENCE_DEFINITION.exec(line);
	if (definition) {
		const [, head = '', target = '', tail = ''] = definition;
		return `${head}${rewrite(target, false)}${tail}`;
	}
	const ranges = codeSpanRanges(line);
	return line.replace(INLINE_LINK_TAIL, (match: string, target: string, title: string | undefined, offset: number) => {
		if (inRanges(offset, ranges)) return match;
		const image = isImageLink(line, offset, ranges);
		return `](${rewrite(target, image)}${title ?? ''})`;
	});
}

interface TransformedDoc {
	title: string;
	body: string;
}

/** Pull the first H1 out as the page title and rewrite links, leaving fenced code blocks untouched. */
function transformMarkdown(text: string, rewrite: RewriteTarget): TransformedDoc | undefined {
	const lines = text.replace(/\r\n/g, '\n').split('\n');
	const output: string[] = [];
	let title: string | undefined;
	let fence: string | undefined;
	for (const line of lines) {
		const fenceMatch = FENCE_OPEN.exec(line);
		if (fence) {
			output.push(line);
			const marker = fenceMatch?.[1];
			if (marker && marker[0] === fence[0] && marker.length >= fence.length && line.trim() === marker) fence = undefined;
			continue;
		}
		if (fenceMatch) {
			fence = fenceMatch[1];
			output.push(line);
			continue;
		}
		if (title === undefined && line.startsWith('# ')) {
			title = line.slice(2).replaceAll('`', '').replaceAll('**', '').trim();
			continue;
		}
		output.push(rewriteLine(line, rewrite));
	}
	if (!title) return undefined;
	while (output.length > 0 && output[0]?.trim() === '') output.shift();
	return { title, body: output.join('\n') };
}

/** Sidebar position: the index first, numbered docs by their number, everything else after them in name order. */
function sidebarOrder(doc: PlannedDoc, unnumberedRank: number): number {
	const stem = path.posix.basename(doc.output, '.md');
	if (stem === 'index') return 0;
	const numbered = /^(\d+)-/.exec(stem);
	if (numbered?.[1]) return Number.parseInt(numbered[1], 10);
	return 900 + unnumberedRank;
}

function sidebarLabel(doc: PlannedDoc, title: string): string {
	const numbered = /^(\d+)-/.exec(path.posix.basename(doc.output, '.md'));
	if (!numbered?.[1] || /^\d/.test(title)) return title;
	return `${numbered[1]} · ${title}`;
}

/** Regenerate the synced docs. Throws when a doc has no H1 or links to something that does not exist, so a broken link fails the build. */
export function syncDocs({ repoRoot, contentDir }: DocsSyncPaths): DocsSyncResult {
	const sourceRoot = path.join(repoRoot, SOURCE_DIR);
	if (!existsSync(sourceRoot)) throw new Error(`docs-sync: source directory not found: ${sourceRoot}`);

	const docs = listMarkdown(sourceRoot).map(planDoc);
	const bySource = new Map(docs.map((doc) => [doc.source, doc]));
	const problems: string[] = [];
	const expected = new Set<string>();
	const result: DocsSyncResult = { written: 0, unchanged: 0, removed: 0, total: docs.length };
	const unnumbered = docs.filter((doc) => !/^(\d+-|index\.md$)/.test(path.posix.basename(doc.output))).map((doc) => doc.output);

	for (const doc of docs) {
		const outputPath = path.join(contentDir, doc.output);

		const rewrite: RewriteTarget = (target, isImage) => {
			if (HAS_SCHEME.test(target) || target.startsWith('#') || target.startsWith('/')) return target;
			const hashIndex = target.indexOf('#');
			const rawPath = hashIndex === -1 ? target : target.slice(0, hashIndex);
			const hash = hashIndex === -1 ? '' : target.slice(hashIndex);
			let decoded: string;
			try {
				decoded = decodeURIComponent(rawPath);
			} catch {
				decoded = rawPath;
			}
			const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(doc.source), decoded));
			const trimmed = resolved.endsWith('/') ? resolved.slice(0, -1) : resolved;
			if (trimmed === '..' || trimmed.startsWith('../')) {
				problems.push(`${doc.source}: link "${target}" points outside the repository`);
				return target;
			}
			if (trimmed === INTERNAL_DIR || trimmed.startsWith(`${INTERNAL_DIR}/`)) {
				problems.push(`${doc.source}: link "${target}" points into ${INTERNAL_DIR}/, which is not published`);
				return target;
			}
			const absolute = path.join(repoRoot, trimmed);
			if (!existsSync(absolute)) {
				problems.push(`${doc.source}: link "${target}" does not resolve to a file or directory in the repository`);
				return target;
			}
			// Images keep a relative path to the original file so Astro's asset pipeline picks them up without a copy.
			if (isImage) return path.relative(path.dirname(outputPath), absolute).split(path.sep).join('/');
			const linked = bySource.get(trimmed);
			if (linked) return `${relativeRoute(doc.route, linked.route)}${hash}`;
			return `${statSync(absolute).isDirectory() ? repoDir(trimmed) : repoFile(trimmed)}${hash}`;
		};

		const transformed = transformMarkdown(readFileSync(path.join(repoRoot, doc.source), 'utf8'), rewrite);
		if (!transformed) {
			problems.push(`${doc.source}: no level-1 heading found to use as the page title`);
			continue;
		}

		const frontmatter = [
			'---',
			`# Synced from ${doc.source} by src/integrations/docs-sync.ts. Edit the source file, not this copy.`,
			`title: ${JSON.stringify(transformed.title)}`,
			`editUrl: ${JSON.stringify(repoEdit(doc.source))}`,
		];
		if (doc.output.startsWith('docs/')) {
			frontmatter.push('sidebar:', `  order: ${sidebarOrder(doc, unnumbered.indexOf(doc.output))}`, `  label: ${JSON.stringify(sidebarLabel(doc, transformed.title))}`);
		}
		frontmatter.push('---', '');
		const content = `${frontmatter.join('\n')}\n${transformed.body}`;

		expected.add(outputPath);
		if (existsSync(outputPath) && readFileSync(outputPath, 'utf8') === content) {
			result.unchanged++;
			continue;
		}
		mkdirSync(path.dirname(outputPath), { recursive: true });
		writeFileSync(outputPath, content);
		result.written++;
	}

	if (problems.length > 0) {
		throw new Error(`docs-sync found ${problems.length} problem(s) in ${SOURCE_DIR}/:\n${problems.map((problem) => `  - ${problem}`).join('\n')}`);
	}

	// Drop generated files whose source was renamed or deleted.
	for (const generatedDir of GENERATED_DIRS) {
		const absoluteDir = path.join(contentDir, generatedDir);
		if (!existsSync(absoluteDir)) continue;
		for (const relative of listMarkdown(absoluteDir)) {
			const filePath = path.join(absoluteDir, relative);
			if (expected.has(filePath)) continue;
			rmSync(filePath);
			result.removed++;
		}
	}
	return result;
}

/** Astro integration that runs the sync before content is loaded and again whenever a file under docs/ changes in dev. */
export function docsSync(): AstroIntegration {
	let paths: DocsSyncPaths | undefined;
	return {
		name: 'forgeplay-docs-sync',
		hooks: {
			'astro:config:setup': ({ config, logger }) => {
				const webRoot = fileURLToPath(config.root);
				paths = {
					repoRoot: path.resolve(webRoot, '..', '..'),
					contentDir: path.join(fileURLToPath(config.srcDir), 'content', 'docs'),
				};
				const result = syncDocs(paths);
				logger.info(`synced ${result.total} files from ${SOURCE_DIR}/ (${result.written} written, ${result.unchanged} unchanged, ${result.removed} removed)`);
			},
			'astro:server:setup': ({ server, logger }) => {
				const current = paths;
				if (!current) return;
				const sourceRoot = path.join(current.repoRoot, SOURCE_DIR);
				server.watcher.add(sourceRoot);
				server.watcher.on('all', (_event, changedPath) => {
					if (!changedPath.startsWith(sourceRoot + path.sep) || !/\.md$/i.test(changedPath)) return;
					try {
						syncDocs(current);
					} catch (error) {
						logger.error(error instanceof Error ? error.message : String(error));
					}
				});
			},
		},
	};
}
