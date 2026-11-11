# Contributing to Classic Games

Thank you for considering a contribution. Classic Games is a console-style launcher with a collection of original games; this guide covers the repository layout, the tools you need, the checks a change must pass, the rule that game content must be original, and the architecture rules that reviewers enforce.

设计文档以中文撰写，入口是 [docs/README.md](./docs/README.md)。Issue、PR 与提交信息请使用英文；用中文提问也没问题，维护者会回复。

By participating you agree to follow the [Code of Conduct](./CODE_OF_CONDUCT.md). Report suspected vulnerabilities privately as described in [SECURITY.md](./SECURITY.md), never in a public issue.

## Repository layout

| Path | Contents |
|---|---|
| `apps/client` | Godot 4.6 project: the console-style launcher (`launcher/`) and the game runtimes (`runtime/`) |
| `apps/server` | Go backend of the optional online service, module `github.com/yldm-tech/classic-games/apps/server` |
| `apps/web` | Website and documentation site (Astro and Starlight), managed with pnpm |
| `apps/cli` | Go CLI, module `github.com/yldm-tech/classic-games/apps/cli`, binary `classic-games` |
| `apps/mcp` | Go MCP server, module `github.com/yldm-tech/classic-games/apps/mcp`, binary `classic-games-mcp` |
| `packages/schemas` | Mod DSL JSON Schemas, one file per runtime and version |
| `packages/dsl` | Go module `github.com/yldm-tech/classic-games/packages/dsl`: RFC 6902 patch, DSL migration and schema validation, shared by server, CLI and MCP server |
| `packages/sdk` | Go module `github.com/yldm-tech/classic-games/packages/sdk`: typed HTTP client for the backend API, shared by CLI and MCP server |
| `docs` | Technical documentation, in Chinese |
| `scripts` | Repository gates and helper scripts |

Dependencies point from `apps` to `packages`, never the other way, and the CLI and the MCP server do not import the backend module; they reach the backend over HTTP through `github.com/yldm-tech/classic-games/packages/sdk`. The five Go modules form a workspace ([`go.work`](./go.work)) and also reference each other with `require classic-games/<name> v0.0.0` and a relative `replace` directive, so each module builds on its own with `GOWORK=off`. The launcher does not use the backend, the CLI, the MCP server or the SDK: they are an optional online service, and a change to the launcher or to a game needs none of them running. A `replace` is not inherited: a module that depends on another local module needs its own `replace` for that module's local dependencies.

## Prerequisites

- **Godot 4.6.3, exactly.** The version is pinned in [`apps/client/.godot-version`](./apps/client/.godot-version) and the test runner refuses any other version. Use the standard build, not the .NET build. Pass the binary with `GODOT=/path/to/godot` when it is not on your `PATH`. This is all you need to work on the launcher and the games.
- **Go 1.26** for the backend, the CLI, the MCP server and the shared Go packages. Every `go.mod` declares `go 1.26`; an older local Go downloads the matching toolchain automatically.
- **Node.js and pnpm 12** for `apps/web` only. The accepted versions are declared in the `engines` and `packageManager` fields of the root [`package.json`](./package.json).
- **GNU Make, Bash and curl.** The gates are Bash scripts driven by the root `Makefile`.

## Running the project

```bash
make help                           # list every target
make import GODOT=/path/to/godot    # import client resources once
/path/to/godot --path apps/client   # run the launcher, or open apps/client in the Godot editor
make dev                            # optional: run the backend on :8080 (override with PORT=...)
pnpm install                        # install the website dependencies
pnpm web:dev                        # run the website locally
```

The launcher stores everything in one local save file and makes no network requests, so it needs no backend. The backend reads its configuration from environment variables; [`.env.example`](./.env.example) lists all of them. With no variables set it starts in development mode with a SQLite database and a deterministic stub AI provider, so no API key is needed to work on it.

## Checks

Run the checks for the area you changed before opening a pull request. All of them are `make` targets at the repository root.

| Area | Targets |
|---|---|
| Every Go module | `make fmt-check`, `make tidy-check`, `make vet`, `make go-test` (workspace), `make go-standalone` (`GOWORK=off`) |
| Backend | `make test` |
| Shared Go packages | `make dsl-test`, `make sdk-test` |
| CLI | `make cli-build`, `make cli-test` |
| MCP server | `make mcp-build`, `make mcp-test` |
| Website | `make web-install`, `make web-check`, `make web-build`, or `make ci-web` for all three |
| Client boundaries and repository architecture | `make boundary-test`, `make architecture-test` |
| Test runner and publication gate contracts | `make script-test` |
| Launcher and games, headless Godot | `make launcher-test`, `make settings-test`, `make library-test`, `make launch-test`, `make pc-mode-test`, `make game-flow-test` |

To reproduce the full gate locally, which takes several minutes:

```bash
make ci GODOT=/path/to/godot        # every Go and Godot gate
make ci-web                         # website gate; needs Node.js and pnpm
```

`make ci-all` runs `ci` and `ci-web` together. `make tidy-check` runs `go mod tidy` in every module and fails when that changes a `go.mod` or `go.sum`, so commit or stash other edits to those files first.

`make publish-check` is not part of `make ci`. It fails when the history of any ref contains the internal notes that were removed from the public tree, so it only passes on a repository whose history never held them; maintainers run it before a repository is made public, and CI runs it once the repository is public.

Do not skip, delete or comment out a failing test to get a green run. Find the cause; if the test itself is wrong, fix it in the same pull request and explain why.

## Commits, branches and pull requests

- Work on a branch created from `main`, in your fork. Do not commit to `main`.
- Write commit messages as [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, with an optional scope such as `feat(client): ...` or `fix(dsl): ...`.
- Keep one topic per pull request and link the issue it resolves with `Fixes #123`. Unrelated fixes belong in their own pull requests.
- Fill in the pull request template: what changed and why, how you tested it, and before and after screenshots for any change that is visible in the client or on the website.
- Do not mix refactoring or formatting of untouched code into a functional change.
- A pull request is merged once CI passes and a maintainer has approved it. CI runs on GitHub-hosted runners for every pull request, including those opened from a fork. Run the gates above locally first and say in the pull request what you ran.

For a larger change, such as a new game, a new runtime, a schema version or a change that touches more than one of client, server and schemas, open an issue first so the design can be agreed before you invest in the implementation.

## Game content must be original

Classic Games ships original games in classic genres. A genre is free to use; another game's expression of it is not. Every game, and every change to one, must follow these rules:

- Names, characters, stories, art, music, sound and level layouts are made for this project. Do not recreate, trace, port or lightly rename those of an existing commercial game, and do not use its trademarks in names, text or file names.
- Do not add assets extracted from other games, or assets whose origin and licence you cannot state. Every image, sound and font needs a source and a licence recorded in [docs/legal/licenses.md](./docs/legal/licenses.md) in the same pull request, including images generated with a model.
- Describe a game by its genre and its rules, not by naming the game that inspired it.

A pull request that does not meet these rules is not merged, whatever its quality. If you are unsure whether something is too close to an existing game, open an issue and ask first. The decision is recorded as ADR-016 in [docs/decisions.md](./docs/decisions.md).

## Architecture rules

These rules are part of the design, and several are enforced by `make boundary-test` and `make architecture-test`. The reasoning behind each is recorded in [docs/decisions.md](./docs/decisions.md).

### The launcher is local

The launcher signs nobody in and makes no network requests; everything it shows about the player comes from one local save file. Do not add an HTTP client, a socket or a URL to `apps/client/launcher`; `make boundary-test` rejects them. Connecting the launcher to the online service would be a product decision, so open an issue before writing any code for it.

### Launcher and runtime talk only through `runtime/game_session.gd`

In the client, the launcher and the game runtimes communicate through [`apps/client/runtime/game_session.gd`](./apps/client/runtime/game_session.gd) and nothing else. The launcher passes a runtime reference and a complete effective DSL document; the runtime reports back through the session's signals, such as `game_ended` and `game_error`. Neither side reads the other's nodes, state or files, and a runtime never depends on the launcher.

Inside the launcher, screens do not read input events: the root translates each press into a named action and hands it to the current screen, and each screen owns its own focus state. Games are started only through `launcher_game_host.gd`. See [section 8 of docs/16-client-architecture.md](./docs/16-client-architecture.md).

### The AI emits DSL only

This rule concerns the online service. A model never produces executable code. Its only output is an RFC 6902 patch against a Mod DSL document; the server applies the patch and validates the resulting document against the runtime's JSON Schema before it is stored or returned. Do not add a path where model output is evaluated, interpolated into code, or stored without validation. AI calls are made by the backend only.

### The two RFC 6902 implementations stay in lockstep

There are two JSON Patch implementations: Go in [`packages/dsl`](./packages/dsl) and GDScript in [`apps/client/runtime/json_patch.gd`](./apps/client/runtime/json_patch.gd). Applying the same patch chain to the same baseline must produce the same effective DSL on both sides, otherwise a document means one thing to the client and another to the backend, the CLI and the MCP server.

Both test suites read the same fixtures: the baseline [`apps/client/runtime/shooter/baseline.dsl.json`](./apps/client/runtime/shooter/baseline.dsl.json) and the golden output [`apps/client/runtime/shooter/testdata/fork_expected.dsl.json`](./apps/client/runtime/shooter/testdata/fork_expected.dsl.json). A change to patch semantics must update both implementations, both test suites and the shared fixtures in the same pull request. The same applies to DSL migration, which exists in Go (`packages/dsl`) and in GDScript ([`apps/client/runtime/dsl_migrations.gd`](./apps/client/runtime/dsl_migrations.gd)).

### A schema change is a contract change

Each file in [`packages/schemas`](./packages/schemas) is one contract with three consumers: the client runtime loads documents that conform to it, the backend, the CLI and the MCP server validate against it, and it constrains what the backend's AI generation may output. A schema change therefore always includes the matching runtime implementation in `apps/client/runtime`, the baseline DSL, the tests on both sides and the documentation in [docs/05-dsl-design.md](./docs/05-dsl-design.md) and [docs/11-runtime-content.md](./docs/11-runtime-content.md).

### Backend structure

`apps/server/cmd/server/main.go` only manages the process lifecycle and calls `app.New`. Domains live in `apps/server/internal/<domain>` and are wired together in `internal/app`. Outside `internal/app`, domain code does not start listeners, handle signals, exit the process or run schema migrations.

## Extending the DSL

The background for this section is [docs/05-dsl-design.md](./docs/05-dsl-design.md) and [docs/11-runtime-content.md](./docs/11-runtime-content.md). Apart from the bookkeeping fields under `meta`, a DSL field is one of three kinds: an enum chosen from content that the runtime already implements, a number with a range, or a boolean switch. The existing exceptions are few: a field that references another entry of the same document by id (`placements.<id>.tower` in Tower Defense), length-capped lists (`path.points` in Tower Defense, `progression.upgrades` in Survivor), and `stage.bgm` in Shooter, a free-form string that the runtime only uses as the seed for a synthesised tune. A new field should be one of the three kinds. Collections whose elements are added and removed, such as `enemies` and `drops`, are maps keyed by a stable id, never arrays, so that patch paths stay valid deep in a fork chain.

### Adding content to an existing runtime

Adding an enum value (a new weapon, enemy or background) or a new optional field is a backward-compatible change:

1. Implement it in the runtime under `apps/client/runtime/<runtime>`. Every enum value must have a real, playable implementation.
2. Add it to the schema with `additionalProperties: false` kept on every object, and release it as a new minor version of the schema.
3. Update the content tables in `docs/11-runtime-content.md` and the examples in `docs/05-dsl-design.md`.
4. Add valid and invalid documents to the schema validation tests, and a runtime test that loads the new content.

### Adding a schema version

Schema files are named `<runtime>-<version>.schema.json`, and the validator picks the file that matches a document's runtime and version. Published mods are pinned to the `runtime_version` they were created with, so do not change the meaning of a schema file that has been released; add a new version instead.

- **Patch or minor version:** backward compatible. Every document that was valid before must still load. The client treats versions with the same major number as compatible.
- **Major version:** may break compatibility, and must ship with a DSL migration from the previous major version, implemented identically in `packages/dsl` and `apps/client/runtime/dsl_migrations.gd` and covered by tests on both sides. A document with no migration path is rejected with `RUNTIME_VERSION_MISMATCH`; it must never crash the runtime or load partially.

A new version also needs the built-in version in `apps/client/runtime/runtime_loader.gd`, the `meta.runtime_version` of the baseline DSL and the runtime references registered in `apps/server/internal/app` updated together.

### Adding a game or a runtime

1. Open an issue describing the game, its content list and its DSL shape. The game must be original; see "Game content must be original" above.
2. Add `packages/schemas/<runtime>-1.0.0.schema.json`.
3. Add `apps/client/runtime/<runtime>/` with the implementation and a `baseline.dsl.json` that validates against the schema, and register the runtime in `apps/client/runtime/runtime_loader.gd`.
4. Add the game to the launcher: one entry in `apps/client/launcher/launcher_catalog.gd` (name, genre, tagline, achievements) and one in `apps/client/launcher/launcher_game_guide.gd` (how it plays, controls, HUD fields). List only controls and start options the runtime really implements.
5. Register the baseline on the server, so that the online service knows the runtime: the configuration in `apps/server/internal/app/config.go` and the runtime list in `internal/app`.
6. Add tests on both sides and a content document under `docs/`.

## Code style

- **Go:** format with `gofmt` (`make fmt`); `make fmt-check` and `go vet` must pass.
- **GDScript:** tabs for indentation, as the Godot editor writes them. Commit the `.uid` and `.import` files that Godot generates next to new scripts and assets.
- **Placeholders:** do not leave `TODO` or `FIXME` comments or stub implementations; open an issue instead.
- **Generated files:** `apps/server/docs` is generated. After changing API annotations, regenerate it from `apps/server` with `go run github.com/swaggo/swag/cmd/swag@v1.16.6 init -g cmd/server/main.go -o docs --parseDependency --parseInternal` and commit the result. swag resolves the types named in an annotation through the imports of the file that carries it, which is why some transport files import `pkg/httpx` with a blank identifier.
- **Documentation:** files under `docs/` are written in Chinese and describe the current state of the code. `make architecture-test` rejects wording that describes a migration as still in progress.
- **Assets and dependencies:** only add third-party code, images, audio or fonts whose licence is compatible with Apache-2.0, and record the source and licence in [docs/legal/licenses.md](./docs/legal/licenses.md) in the same pull request. GPL, AGPL and assets of unknown origin are not accepted.

## Licence of contributions

Classic Games is licensed under the [Apache License, Version 2.0](./LICENSE). As stated in section 5 of the licence, any contribution you intentionally submit for inclusion in the project is licensed under the same terms, with no additional terms or conditions. You keep the copyright to your work, and you confirm that you have the right to submit it under this licence.
