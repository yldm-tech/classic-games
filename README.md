# ForgePlay

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

English | [简体中文](./README.zh-CN.md)

ForgePlay is a platform for creating and sharing small games with AI. A player does not write code: they take an existing game, describe a change in plain language, and publish the result for others to play and fork. Every game is a JSON document, the **Mod DSL**, interpreted by a fixed game runtime. The AI only ever produces RFC 6902 patches against that document, never executable code. The backend applies each generated patch and validates the result against the runtime's JSON Schema before returning it, and a mod can only be published when its effective DSL validates.

The project is pre-release. There are no published binaries, packages or app store builds; everything below starts from source.

## How it works

1. **Fork.** A game is a chain of patches on top of a runtime baseline. Forking a game creates a draft mod whose parent is the game's mod, so a fork stores a patch, not a copy of the game.
2. **Edit with AI.** The client sends the current effective DSL and the player's request to the backend. The backend asks the model for a JSON Patch, applies it, validates the result against the schema, and feeds validation errors back to the model for a bounded number of retries. The model's output space is the schema; there is no path from model output to code execution.
3. **Publish.** The draft is submitted as a game, goes through moderation, and becomes forkable by everyone else.

The same three steps are available from the Godot client, from the `forgeplay` command line and, for AI agents, from the `forgeplay-mcp` server.

## Repository layout

| Path | What it is |
|---|---|
| [`apps/client`](./apps/client) | The game client and the game runtimes: one Godot 4.6 project exported to iOS, Android, macOS, Windows and Web. See [client architecture](./docs/16-client-architecture.md). |
| [`apps/server`](./apps/server) | Go backend (gin, GORM), module `forgeplay/server`: HTTP API, domain services, AI orchestration. See its [README](./apps/server/README.md). |
| [`apps/cli`](./apps/cli) | `forgeplay`, a Go command-line client (cobra), module `forgeplay/cli`: catalog, mods, AI generation, and offline DSL validation, patching and migration. See its [README](./apps/cli/README.md). |
| [`apps/mcp`](./apps/mcp) | `forgeplay-mcp`, a Model Context Protocol server built on the official Go SDK, module `forgeplay/mcp`: the same capabilities as tools for AI agents. See its [README](./apps/mcp/README.md). |
| [`apps/web`](./apps/web) | The website: landing page and documentation site (Astro and Starlight, pnpm). See its [README](./apps/web/README.md). |
| [`packages/schemas`](./packages/schemas) | The Mod DSL JSON Schemas, one file per runtime and version. |
| [`packages/dsl`](./packages/dsl) | Go module `forgeplay/dsl`: RFC 6902 patch, DSL migration and schema validation, shared by the backend, the CLI and the MCP server. See its [README](./packages/dsl/README.md). |
| [`packages/sdk`](./packages/sdk) | Go module `forgeplay/sdk`: typed HTTP client for the backend API, shared by the CLI and the MCP server. See its [README](./packages/sdk/README.md). |
| [`docs`](./docs) | Technical documentation, in Chinese. Start at [docs/README.md](./docs/README.md). |
| [`scripts`](./scripts) | Repository gates and helper scripts: architecture checks, the Godot test runner, the client-server integration run. |

Dependencies point one way, from `apps` to `packages`. The Go modules are tied together by [`go.work`](./go.work) and also reference each other with `require forgeplay/<name> v0.0.0` plus a relative `replace`, so each module builds on its own with `GOWORK=off`. The module paths are local to this repository and are not published to a module proxy. The reasons for this layout are recorded in [ADR-015](./docs/decisions.md).

## Quick start

Requirements: Go 1.26 (an older Go downloads the toolchain on demand), GNU Make, and Godot 4.6.3 exactly for the client (the version is pinned in [`apps/client/.godot-version`](./apps/client/.godot-version)). The website additionally needs Node.js 22.23.4 or newer and pnpm 12.

```bash
git clone https://github.com/yldm-tech/classic-games.git
cd classic-games
make help        # list every target
```

### Backend

```bash
make dev                              # listens on :8080; PORT=9090 make dev to change it
curl http://localhost:8080/healthz    # {"ok":true}
```

With no environment variables set, the backend runs in development mode on a SQLite file and uses a deterministic stub in place of a model, so the whole request, patch and validation path works without an API key. Setting `ANTHROPIC_API_KEY` switches to the real model. Every variable is listed in [`.env.example`](./.env.example). The API reference is served at `http://localhost:8080/swagger/index.html`.

### Client

```bash
make import GODOT=/path/to/godot      # import resources once
FORGEPLAY_API=http://127.0.0.1:8080 /path/to/godot --path apps/client
```

Or open `apps/client` in the Godot 4.6.3 editor.

### CLI

```bash
make cli-build                        # writes apps/cli/bin/forgeplay
export PATH="$PWD/apps/cli/bin:$PATH"

forgeplay dsl validate apps/client/runtime/shooter/baseline.dsl.json   # offline
forgeplay server health
forgeplay auth login                  # guest session
forgeplay ai generate "turn the player into a cat" --runtime shooter@1.0.0 --save
forgeplay mods list
```

### MCP server

```bash
make mcp-build                        # writes apps/mcp/bin/forgeplay-mcp
export FORGEPLAY_TOKEN="$(forgeplay auth token)"    # optional; without it the server is anonymous
claude mcp add forgeplay --env FORGEPLAY_SERVER_URL=http://localhost:8080 --env FORGEPLAY_TOKEN="$FORGEPLAY_TOKEN" -- "$PWD/apps/mcp/bin/forgeplay-mcp"
```

Configuration for other MCP clients, the tool list and the security notes are in [`apps/mcp/README.md`](./apps/mcp/README.md).

### Website

```bash
pnpm install
pnpm web:dev                          # http://localhost:4321
```

## The Mod DSL contract

The DSL is one contract with three consumers: it constrains what the AI may output, the backend validates against it, and the client runtime loads documents that conform to it. The schemas are in [`packages/schemas`](./packages/schemas); the first one written was [`shooter-1.0.0.schema.json`](./packages/schemas/shooter-1.0.0.schema.json). Three runtimes exist today: `shooter`, `survivor` and `tower_defense`. The design is described in [docs/05-dsl-design.md](./docs/05-dsl-design.md).

Two structural decisions carry most of the weight ([ADR-013](./docs/decisions.md)):

- **Patches are RFC 6902 (JSON Patch), not Merge Patch.** Merge Patch can only replace an array as a whole, so it cannot express "remove this enemy", and a fork chain built on it stops composing.
- **Collections that gain and lose elements are maps keyed by a stable id, not arrays.** `enemies` and `drops` are addressed as `/enemies/<id>/...`, so a path stays valid deep in a fork chain where an array index would shift, and the AI can refer to an element by id.

There are two implementations of the patch semantics: GDScript in [`apps/client/runtime/json_patch.gd`](./apps/client/runtime/json_patch.gd) for the preview in the client, and Go in [`packages/dsl`](./packages/dsl) for the backend, the CLI and the MCP server. Applying the same patch chain to the same baseline must give the same effective DSL on both sides, otherwise what the player previews and what the server validates and stores diverge. Both test suites read the same baseline and the same golden output ([`apps/client/runtime/shooter/testdata/fork_expected.dsl.json`](./apps/client/runtime/shooter/testdata/fork_expected.dsl.json)), which pins the two to one result. The supported operations are `add`, `replace`, `remove` and `test`; `move` and `copy` are rejected everywhere.

Related decisions: mods store patches, not snapshots ([ADR-005](./docs/decisions.md)); AI calls are made by the backend only ([ADR-007](./docs/decisions.md)); the shell and the runtime in the client talk only through `runtime/game_session.gd` ([ADR-003](./docs/decisions.md)); schema validation uses JSON Schema draft 2020-12 ([ADR-014](./docs/decisions.md)).

## Development gates

All gates are `make` targets at the repository root.

```bash
make ci GODOT=/path/to/godot          # every Go and Godot gate
make ci-web                           # website: install, type check, build with link check
make ci-all GODOT=/path/to/godot      # both
GODOT=/path/to/godot scripts/spike-integration.sh    # real client against a real backend, on port 8099
```

`make ci` covers `gofmt`, `go mod tidy`, `go vet` and `go test` for all five Go modules, both in the workspace and with `GOWORK=off`, the CLI and MCP server builds, the architecture checks ([`scripts/check-architecture.sh`](./scripts/check-architecture.sh), [`scripts/check-client-boundaries.sh`](./scripts/check-client-boundaries.sh)) and the headless Godot suites. Narrower targets exist for each area, for example `make dsl-test`, `make sdk-test`, `make cli-test`, `make mcp-test`, `make test` (backend) and `make spike` (runtimes and DSL in Godot); [CONTRIBUTING.md](./CONTRIBUTING.md) lists them by area.

[`.github/workflows/ci.yml`](./.github/workflows/ci.yml) runs the same targets on pushes and pull requests to `main`, in four jobs: backend, shared Go modules with CLI and MCP server, website, and headless Godot.

## Documentation

- [docs/README.md](./docs/README.md) is the index of the technical documentation (Chinese), with a suggested reading order.
- [docs/04-architecture.md](./docs/04-architecture.md) and [docs/16-client-architecture.md](./docs/16-client-architecture.md) describe the running architecture.
- [docs/decisions.md](./docs/decisions.md) is the decision log (ADRs); [docs/glossary.md](./docs/glossary.md) is the glossary.
- [docs/09-api-design.md](./docs/09-api-design.md) describes the HTTP API.
- The website in `apps/web` publishes the same documents next to the developer guides for the CLI, the MCP server and the Go SDK.

## Contributing

Contributions are welcome. [CONTRIBUTING.md](./CONTRIBUTING.md) covers the tools, the checks a change must pass and the architecture rules reviewers enforce. Participation is governed by the [Code of Conduct](./CODE_OF_CONDUCT.md). Notable changes are recorded in [CHANGELOG.md](./CHANGELOG.md).

## Security

Report suspected vulnerabilities privately, as described in [SECURITY.md](./SECURITY.md), not in a public issue.

## Licence

ForgePlay is licensed under the [Apache License, Version 2.0](./LICENSE). Third-party attributions are in [NOTICE](./NOTICE) and [docs/legal/licenses.md](./docs/legal/licenses.md).
