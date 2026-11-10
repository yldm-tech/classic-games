# Classic Games website

The official Classic Games site: a bilingual landing page and the documentation site. It is a static site built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build), with no UI framework, no analytics and no third-party fonts or CDNs.

- Default locale: Simplified Chinese (`zh-CN`), served from `/`.
- Second locale: English (`en`), served from `/en/`.

## Requirements

- Node.js 22.23.4 or newer (the floor set by Astro 7).
- pnpm 12. The repository root pins `packageManager` to `pnpm@12.3.4`.

The pnpm workspace is rooted at the repository root (`pnpm-workspace.yaml` lists `apps/web`), so install from there.

## Commands

Run these from the repository root:

| Command | What it does |
|---|---|
| `pnpm install` | Installs dependencies for the workspace |
| `pnpm web:dev` | Starts the dev server on `http://localhost:4321` |
| `pnpm web:check` | Runs `astro check` (TypeScript strict, `.astro` files included) |
| `pnpm web:build` | Builds the static site into `apps/web/dist/` |
| `pnpm web:preview` | Serves `apps/web/dist/` locally |

The same scripts exist in this package as `dev`, `check`, `build` and `preview`, for use with `pnpm --filter @classic-games/web <script>`.

The root `Makefile` wraps the gate that CI runs: `make web-install` (`pnpm install --frozen-lockfile`), `make web-check`, `make web-build`, or `make ci-web` for all three in order.

Search (Pagefind) only works in a production build, so use `web:build` followed by `web:preview` to try it.

Astro starts `dev` and `preview` as a background process when it detects that an AI coding agent launched it. In that case the command returns immediately; stop the server with `pnpm --filter @classic-games/web exec astro dev stop` or `... astro preview stop`.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `SITE_URL` | `http://localhost:4321` | Origin used for canonical URLs, `hreflang` links and the sitemap. Set it to the public origin when building for deployment |

Site-wide constants live in `src/config/site.ts`. The repository URL (`REPO_URL`) is defined there once, and every link to the repository is built from it with `repoFile`, `repoDir` or `repoEdit`. Do not write the URL anywhere else; MDX pages import the helpers instead.

## Layout

```
apps/web/
├── astro.config.ts            Astro + Starlight configuration, sidebar, locales
├── public/                    Files served as-is (favicon)
└── src/
    ├── config/site.ts         Repository URL and other constants
    ├── integrations/
    │   ├── docs-sync.ts       Copies <repo>/docs into the docs collection (see below)
    │   ├── check-built-links.ts  Fails the build on broken internal links in the built HTML
    │   └── check-built-pages.ts  Fails the build on UI strings in the wrong language and on a 404 page that poses as the landing page
    ├── content/
    │   ├── docs/developers/   Developer pages, Chinese (getting started, CLI, MCP, Go SDK)
    │   ├── docs/en/developers/  The same pages in English
    │   ├── docs/docs/         Generated from <repo>/docs, git-ignored
    │   ├── docs/legal/        Generated from <repo>/docs/legal, git-ignored
    │   └── i18n/              Overrides for Starlight's UI strings
    ├── i18n/landing.ts        All landing page copy, both locales, one typed interface
    ├── data/                  Build-time data read from repository fixtures
    ├── components/            Landing page sections, header, footer, wordmark
    ├── layouts/               HTML shell of the landing pages
    ├── pages/                 `/`, `/en/` and the 404 page
    ├── styles/                Design tokens, landing styles, Starlight theme mapping
    └── assets/covers/         Cover art copied from apps/client/assets/covers
```

## How the docs are sourced

The public Markdown in the repository's `docs/` directory is the single source of truth. It is not duplicated in git. `src/integrations/docs-sync.ts` is an Astro integration that copies it into the Starlight content collection in its `astro:config:setup` hook, which runs before content is loaded for `dev`, `build` and `check`. In dev it also watches `docs/` and syncs again on every change.

A sync step was chosen over a custom content loader because Starlight 0.42 still assumes its content lives in `src/content/docs/`: its Markdown plugins derive a page's locale from the file path below that directory, and edit links and sidebar generation are keyed to the same layout. Writing real files there keeps every Starlight feature working without depending on its internals.

For each `docs/**/*.md` file the sync step:

1. Takes the first level-1 heading as the page `title` and removes it from the body, because Starlight renders the title itself. The source files need no frontmatter.
2. Maps the file to a route. `docs/NAME.md` becomes `/docs/NAME/`, `docs/README.md` becomes `/docs/`, and `docs/legal/NAME.md` becomes `/legal/NAME/` so the legal texts get their own sidebar group.
3. Rewrites relative links. A link to another synced doc becomes a link to that doc's page, written relative to the linking page (`../decisions/#adr-013`, the `#fragment` is kept). It is relative on purpose: the same generated Markdown is served under `/docs/...` and, through Starlight's fallback, under `/en/docs/...`, and a relative link stays inside whichever locale the reader is in. A link to anything else in the repository, such as `../packages/schemas/...` or `../README.md`, becomes a GitHub URL built from `REPO_URL`. A relative image keeps pointing at the original file so Astro's asset pipeline processes it. Links inside inline code and fenced code blocks are left alone.
4. Sets `editUrl` to the source file on GitHub, so "Edit page" opens `docs/NAME.md` and not the generated copy.
5. Sets the sidebar order from the numeric file prefix, so the sidebar follows the docs' own numbering.

The build stops with a list of problems if a doc has no level-1 heading, or if a relative link points to a path that does not exist in the repository, leaves the repository, or points into `docs-internal/`. `docs-internal/` is never read: the sync step only walks `docs/`.

The generated files are written only when their content changes, and files whose source disappeared are deleted. Never edit `src/content/docs/docs/` or `src/content/docs/legal/` by hand.

The docs are written in Chinese only. They are served under the default locale, and Starlight's fallback serves the same content under `/en/` with a notice that the page is not translated.

## Link checking

Two checks run during `pnpm web:build`, and either one fails the build:

- [`starlight-links-validator`](https://starlight-links-validator.vercel.app) validates root-absolute internal links written in Markdown and MDX content. It cannot resolve relative links, so `errorOnRelativeLinks` is turned off for the links the sync step writes between synced docs.
- `src/integrations/check-built-links.ts` then checks every internal `href` and `src` in the built HTML, relative links and `#fragment` targets included. It covers what the validator cannot see: the synced docs' relative links, the hand-written landing pages, the header and the footer. It also fails when a page under `/en/` links to a page outside `/en/` although the same page exists under `/en/`; a language switcher is exempt and marks itself with `hreflang`. In hand-written English pages, link to `/en/...`.

A third check, `src/integrations/check-built-pages.ts`, looks at what the built pages say. The default locale is Chinese, and Starlight falls back to the default locale for any UI string a locale does not define, so a missing override shows up as Chinese UI on an English page or English UI on a Chinese one. The check fails when English content carries the Chinese code block strings (`src/content/i18n/en.json` supplies the English ones), when the search dialog of a Chinese page is missing a Pagefind string (`src/content/i18n/zh-CN.json` supplies them), and when `404.html` is indexable or reuses the landing page's title, canonical URL, `hreflang` alternates or `og:url`.

Links to GitHub are external and are not checked. The developer pages link to `apps/cli/README.md`, `apps/mcp/README.md` and `packages/sdk/README.md` in the repository; keep those files in place.

## Landing page content

All landing page copy is in `src/i18n/landing.ts`, as two objects that implement one interface, so a string cannot exist in one language only. A `|` in a heading marks a phrase boundary where the line may wrap.

Facts that can be read from the repository are read at build time instead of being typed in:

- `src/data/dsl-example.ts` imports the Shooter baseline and the golden file from `apps/client/runtime/shooter/` and applies the fork patch in `src/data/fork-patch.json`. If the result no longer equals the golden file, the build fails. The patch itself is a copy of the one used in `packages/dsl/patch_test.go`, `apps/server/internal/ai/service_test.go` and `apps/client/spike_test.gd`.
- `src/data/runtimes.ts` imports the three runtime schemas and baselines and derives each runtime's id and top-level DSL sections from them. It also lists the schema fields that are not an enum, a ranged number or a boolean, and fails the build when a schema gains or loses one, because the landing copy names those exceptions.

The site should not claim anything the repository cannot back up: no download links, store badges, usage numbers or screenshots of features that do not exist.

## Design

`src/styles/tokens.css` mirrors the client's design tokens in `apps/client/shell/design_system/theme/tokens.gd` (ember and volt ramps, warm neutrals, radii, motion durations), for a dark and a light theme. Where a client token does not reach WCAG AA contrast for running text on the web, the site uses the nearest value that does, and the token file says so next to the value. `src/styles/starlight.css` maps the same tokens onto Starlight's custom properties, so docs and landing share one palette.

The landing header's theme toggle uses the same `localStorage` key as Starlight's theme picker, so a choice made on either side applies to both.

Fonts are system font stacks only.

## Deployment

`pnpm web:build` produces a fully static site in `apps/web/dist/`. Any static host can serve it.

```bash
SITE_URL=https://example.org pnpm web:build
```

Things the host needs to get right:

- Serve the site from the root of its origin. A sub-path deployment (an Astro `base`) is not supported yet: the landing pages, the header, the footer and the hand-written developer pages use root-relative links.
- Serve `404.html` for unknown paths. Most static hosts do this by default.
- URLs end with a trailing slash (`trailingSlash: 'always'`) and map to `index.html` files in directories.

The build writes `sitemap-index.xml` and the Pagefind search index into `dist/` as well.
