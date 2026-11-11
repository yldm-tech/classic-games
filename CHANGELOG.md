# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). No version has been tagged yet; the project will follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from its first release. Mod DSL schemas are versioned separately, per runtime, by the version in each file name under `packages/schemas`.

## [Unreleased]

### Added

- Console-style launcher in `apps/client/launcher`, now the client's main scene: Home, Library, Achievements and Settings screens, a per-game menu, an in-game HUD, pause and result screens, and a PC mode for keyboard and mouse toggled with F11. It is operated with a gamepad or a keyboard, keyboard keys can be rebound, the interface is available in Chinese and English, and all progress is kept in one local save file that can be exported and imported. The launcher makes no network requests.
- Three original games in the launcher, each a data-driven runtime in `apps/client/runtime` that plays its baseline Mod DSL document: 星环巡航 / Orbit Patrol (arena shooter), 长夜草原 / Meadow Vigil (survivor) and 隘口守卫 / Gatewatch (tower defense), with 11 achievements between them and one key art image each.
- Headless Godot suites for the launcher: `make launcher-test`, `make settings-test`, `make library-test`, `make launch-test`, `make pc-mode-test` and `make game-flow-test`, all part of `make ci`.
- Go backend in `apps/server` (gin and GORM): a modular monolith assembled from seven domain installers, with the HTTP API, AI orchestration that applies model-produced RFC 6902 patches and validates the result against the runtime schema, a Claude provider and a deterministic stub provider for offline development, and an OpenAPI description served through Swagger UI.
- Mod DSL JSON Schemas version 1.0.0 for the shooter, survivor and tower defense runtimes in `packages/schemas`.
- `packages/dsl`: a Go module with the RFC 6902 patch implementation, DSL migration and schema validation, shared by the server, the CLI and the MCP server.
- `packages/sdk`: a Go module with a typed HTTP client for the backend API.
- `apps/cli`: the `classic-games` command-line tool, with networked commands (`auth`, `server`, `games`, `mods`, `ai`) and offline DSL commands (`dsl validate`, `dsl patch`, `dsl migrate`).
- `apps/mcp`: the `classic-games-mcp` Model Context Protocol server, with 14 tools, schema resources, stdio and streamable HTTP transports and a read-only mode.
- `apps/web`: the project website and documentation site, built with Astro and Starlight.
- A Go workspace (`go.work`) over the five Go modules, and `make` targets and CI jobs for the shared packages, the CLI, the MCP server and the website.
- `make publish-check` (`scripts/check-public-history.sh`): fails when the history of any ref contains the internal notes, by path or by content. It is the gate to pass before the repository becomes public, and CI runs it once the repository is public.
- Repository gates: `gofmt` and `go mod tidy` checks, Go vet and tests in the workspace and with `GOWORK=off`, headless Godot test suites, client boundary and repository architecture checkers with their own self-tests, and a client-server integration smoke test. The architecture checker now also enforces the module boundaries between `apps` and `packages`.
- High-resolution art and recorded audio for game modules, in `apps/client/games/shared`: `GameAudio` plays music files with clean loops and cross-fades, one-shot stingers that duck or pause the music, and sound effects from files, next to the synthesised sound it already had; `GameSynth` and `GameSfx` are a layered sound-effect synthesiser (ADSR, pitch sweeps, filters, FM and ring modulation, echo and reverb) with 24 ready-made presets; `GameSprites` loads sprite atlases with frame tables and draws them at stage coordinates with animation, flipping, tiling and nine-patch; `GameText` draws smooth text. `scripts/assets` holds the tools that make such media (generation, keying, atlas packing, loop cutting and loudness), `make games-check` enforces a media budget per game, and `make export-test` loads every game's media from inside an exported pack.
- Open-source project files: Apache-2.0 `LICENSE`, `NOTICE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue forms, a pull request template, Dependabot configuration, `.editorconfig` and `.gitattributes`.

### Changed

- **Product direction.** Classic Games is now an open-source console-style launcher with a collection of original games in classic genres, played with a gamepad or a keyboard, with a PC desktop mode. It was previously a portrait phone app for forking games, editing them with AI and publishing them to a community. The decision and its consequences are recorded as ADR-016 in `docs/decisions.md`; game content must be original and must not recreate the names, characters, art or levels of existing commercial games.
- The Go backend, the CLI, the MCP server and the SDK are unchanged and remain in the repository as an optional online service (accounts, catalog, mods, community and commerce APIs, plus Mod DSL validation and patching). The launcher does not use them.
- `README.md`, `README.zh-CN.md`, `CONTRIBUTING.md`, the documents under `docs/` and the website describe the launcher. The website's landing page was redesigned in the launcher's visual language, with launcher screenshots and the three key art images.
- The repository is organised as a monorepo with `apps/` and `packages/`: `client/` moved to `apps/client`, `server/` to `apps/server` (Go module `github.com/yldm-tech/classic-games/apps/server`) and `docs/schemas/` to `packages/schemas`.
- The default of `CLASSIC_GAMES_SCHEMA_DIR` is now `../../packages/schemas`, relative to `apps/server`.
- The RFC 6902 patch, DSL migration and schema validation code moved from `apps/server/internal/ai` to `packages/dsl`.
- `docs/legal/licenses.md` now lists the project licence and the audited licences of bundled third-party code, assets and Go dependencies.
- `README.md` is now in English; the Chinese version is `README.zh-CN.md`.
- The showcase games are seeded only when `CLASSIC_GAMES_ENV` is `development`; a production database starts with an empty catalogue. A showcase game no longer carries a placeholder `mod_id`: its `mod_id` and `runtime` are empty, the DSL, lineage, fork-tree and fork routes of a game without a mod answer `404 GAME_HAS_NO_MOD` instead of `404 NOT_FOUND`.
- The backend's startup log shows `CLASSIC_GAMES_DB` only when it is a SQLite file path, without query parameters; a value that looks like the connection string of another database is not printed.
- CI runs on GitHub-hosted runners, pull requests from forks included, and every action is pinned to a commit.
- `make tidy-check` also fails when a `go.mod` or `go.sum` is not tracked by git. `go.work.sum` is git-ignored.
- The generated OpenAPI description in `apps/server/docs` was regenerated; the patch operation definition is now named `dsl.Op`.

### Removed

- The phone app shell in the client: the feed, the AI creation and editing flow, community, commerce and account screens, together with their feature slices, composition root, shared UI and test suites.
- The website's sections about the phone app, its Fork Tree illustration and the four cover images it used, which had no licence record.
