# forgeplay CLI

`forgeplay` is the command-line client for ForgePlay. It talks to a ForgePlay backend (`apps/server`) through the typed Go SDK in `packages/sdk`, and it works with Mod DSL documents offline through `packages/dsl`, the same implementation the backend uses for RFC 6902 patches, migration and schema validation.

## Install from source

Requirements: Go 1.26 or newer (an older Go downloads the toolchain automatically).

```sh
git clone https://github.com/yldm-tech/classic-games.git
cd classic-games/apps/cli
go build -o forgeplay ./cmd/forgeplay
./forgeplay version
```

From the repository root, `make cli-build` does the same with the commit and build date linked in, and writes `apps/cli/bin/forgeplay`.

The module is `forgeplay/cli`. It depends on the sibling modules `forgeplay/sdk` and `forgeplay/dsl` through relative `replace` directives, so it has to be built inside a checkout of this repository; `go install forgeplay/cli/...@latest` does not work.

Version information is injected at link time and defaults to `dev` / `none` / `unknown`:

```sh
go build -ldflags "-X main.version=0.1.0 -X main.commit=$(git rev-parse --short HEAD) -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o forgeplay ./cmd/forgeplay
```

Shell completion scripts come from `forgeplay completion bash|zsh|fish|powershell`.

## Quick start

```sh
# Offline: validate and patch DSL files. Inside a repository checkout the schemas are found automatically.
forgeplay dsl validate apps/client/runtime/shooter/baseline.dsl.json
forgeplay dsl patch apps/client/runtime/shooter/baseline.dsl.json patch.json --validate -o modded.dsl.json

# Online: point the CLI at a backend, log in as a guest and let the AI write a patch.
forgeplay config set server http://localhost:8080
forgeplay server health
forgeplay auth login
forgeplay ai generate "turn the player into a cat" --runtime shooter@1.0.0 --save
forgeplay mods list
forgeplay mods publish <mod-id> --title "Cat Shooter"
```

To start a local backend for this, see [`apps/server/README.md`](../server/README.md). Without `ANTHROPIC_API_KEY` the backend runs its AI in stub mode and answers every prompt with a fixed patch per runtime.

## Global flags

| Flag | Meaning |
| --- | --- |
| `--server <url>` | Backend root URL, such as `http://localhost:8080`. Do not append `/api/v1`. |
| `--output table\|json` | Output format. `table` (default) is for people; `json` is stable and machine-readable. |

Results go to standard output. Errors go to standard error as `Error: <message>` and the exit status is 1; a backend error is rendered as `CODE: message`, for example `Error: NOT_FOUND: The requested resource was not found`. When the answer is not a ForgePlay error (a proxy error page, for example) only its first 512 bytes are shown. An interrupt (Ctrl-C) cancels the request in flight, or the wait for a document or a password on standard input, and exits with status 130.

The CLI prints no colors. Titles, summaries, tags and nicknames are written by other users, so in `table` output every control character in a value (escape sequences included) is replaced with `�` and line breaks with a space; `json` output keeps the exact text, escaped as JSON.

In `json` mode, listings are `{"items": [...]}` (plus `"next_cursor"` for paginated ones), single resources use the field names of the backend API, and empty lists are `[]`, never `null`: a game always has a `tags` array and a mod always has a `patch` array. As in the backend API, a few optional text fields are left out when they are empty: `forked_from` and `ver` of a game, `parent_id` and `author_id` of a mod. Commands that print a DSL or a patch print JSON in both modes.

## Command reference

Run `forgeplay <group> --help` or `forgeplay <group> <command> --help` for every flag.

Pass ids exactly as the CLI prints them. An id that contains `/`, or that is `.` or `..`, is refused without contacting the backend, because the backend would route it to a different endpoint. A word that is an endpoint of its own, such as `mine` in `forgeplay games show mine`, is reported as `NOT_FOUND`.

### version

| Command | Description |
| --- | --- |
| `forgeplay version` | Print version, commit, build date, Go version and SDK version. |

### config

| Command | Description |
| --- | --- |
| `forgeplay config get [key]` | Show the effective value of every setting and where it comes from (`flag`, `env`, `config`, `default`, `repository`, `unset`). With a key, print only that value. |
| `forgeplay config set <key> <value>` | Store a setting in the config file. |
| `forgeplay config unset <key>` | Remove a setting from the config file. |
| `forgeplay config path` | Print the path of the config file. |

Keys: `server` (backend URL), `language` (`zh`, `en` or `ja`; the language of server messages and localized titles), `schema-dir` (directory with the Mod DSL JSON Schemas, stored as an absolute path).

### auth

| Command | Description |
| --- | --- |
| `forgeplay auth login` | Create a guest session. Needs no credentials. |
| `forgeplay auth login --method sms --phone <number>` | Request a login code by SMS and read it from standard input. With `--code <code>` an already received code is verified and no new one is requested. |
| `forgeplay auth login --method password --phone <number> --password-stdin` | Log in with a password read from standard input. |
| `forgeplay auth status` | Check the stored session against the backend. Exit status 1 when there is none or it is rejected. |
| `forgeplay auth refresh` | Trade the stored token for a fresh one. The old one is revoked immediately. |
| `forgeplay auth set-password --password-stdin` | Set the account password (at least 8 characters) read from standard input. |
| `forgeplay auth token` | Print the stored token and nothing else, for handing the session to another program: `export FORGEPLAY_TOKEN="$(forgeplay auth token)"` for `forgeplay-mcp`. |
| `forgeplay auth logout` | Revoke the session on the backend and delete the stored token. `--local` deletes it without contacting the server. |

Notes on sessions:

- Tokens are valid for 30 days and are stored per server URL, so a token is never sent to a server it was not issued by.
- Only `forgeplay auth token` prints the token; no other command does, in either output format. Passwords and codes are read from standard input so they do not appear in the process list or shell history.
- A guest account cannot be recovered once its token is lost. `auth login` therefore refuses to replace a stored session unless `--force` is passed, and `auth logout` keeps the token when the backend cannot be reached.
- `auth login --force` revokes the replaced session on the backend, but only after the new login succeeded and its token is stored, so a failed login leaves the old session intact. If the revocation itself fails, the command prints a warning and still exits with status 0; the old token then stays valid until it expires.
- When the backend rejects the stored token (`AUTH_REQUIRED`), the session is expired or revoked but still stored: run `forgeplay auth login --force` to replace it.
- SMS login needs an SMS gateway on the backend; `forgeplay server info` shows whether one is configured. A local development backend has none, so only guest login works there. OAuth login needs a browser or the app and is not available in the CLI.

### server

| Command | Description |
| --- | --- |
| `forgeplay server health` | Call `GET /healthz`. Exit status 1 when the backend is unreachable or unhealthy. |
| `forgeplay server info` | Show the backend's environment, AI mode (`live` or `stub`), SMS gateway, OAuth providers, payments, admin and moderation setup. |

### games

| Command | Description |
| --- | --- |
| `forgeplay games list` | List published games. Filters: `--query`, `--sort new\|hot\|rising`, `--runtime`, `--category`, `--ai[=false]`. Paging: `--limit`, `--cursor`, or `--all` for every page. |
| `forgeplay games show <game-id>` | Show one game. |
| `forgeplay games dsl <game-id> [-o file]` | Print the effective DSL of a game as JSON. |
| `forgeplay games ranking` | Show a leaderboard. Flags: `--type hot\|new\|rising`, `--limit`, `--runtime`, `--category`. |
| `forgeplay games fork <game-id>` | Fork a game into a draft mod you own. Login required. |
| `forgeplay games mine` | List your own games in every status. Login required. |
| `forgeplay games delist <game-id>` | Take your own published game offline. Login required. |
| `forgeplay games resubmit <game-id>` | Send your own rejected game back to review. Login required. |

A development backend is seeded with showcase games that have no mod behind them. They are listed with an empty runtime, so `--runtime` filters them out, and `games dsl` and `games fork` fail for them with `GAME_HAS_NO_MOD`. Only a game that was published from a real mod can be read or forked; to start without one, create a draft on a runtime baseline with `forgeplay mods create --runtime shooter@1.0.0`.

### mods

A mod is a JSON Patch relative to its parent mod, or to the runtime baseline for a root mod. Mods are immutable: saving a draft creates a new draft whose parent is the old one.

| Command | Description |
| --- | --- |
| `forgeplay mods list` | List your draft mods, newest first. Login required. |
| `forgeplay mods create --runtime <ref> [--patch file]` | Create a root mod on a runtime baseline, such as `shooter@1.0.0`. Login required. |
| `forgeplay mods create --parent <mod-id> [--patch file]` | Create a child of an existing mod. `--draft=false` creates a final mod; `--provenance` marks it as AI-generated. Login required. |
| `forgeplay mods fork <mod-id>` | Fork a mod into a draft with an empty patch. Login required. |
| `forgeplay mods save <draft-id> --patch file` | Save a new version of a draft. Prints the new draft id. Login required. |
| `forgeplay mods show <mod-id>` | Show one mod and its patch. |
| `forgeplay mods dsl <mod-id> [-o file]` | Print the effective DSL of a mod as JSON. |
| `forgeplay mods lineage <mod-id>` | List the chain of mods from the root down to a mod. |
| `forgeplay mods publish <mod-id> --title <title>` | Submit a mod as a game. Flags: `--summary`, `--tag` (repeatable, at most 3), `--category`, `--forked-from`, `--ai-generated`. Login required. |

A patch file is a JSON array of RFC 6902 operations; `-` reads it from standard input. Only `add`, `replace`, `remove` and `test` are accepted: a file with a `move` or `copy` operation is refused before anything is sent, because no mod holding one could ever be read. The backend stores a patch without applying it, so a patch that does not apply only shows up as `DSL_INVALID` when the effective DSL is read. Check it first with `forgeplay dsl patch --validate`, or afterwards with `forgeplay mods dsl <id>`.

A published game starts in status `reviewing` and becomes public once a moderator approves it. Moderation is not part of the CLI.

### ai

| Command | Description |
| --- | --- |
| `forgeplay ai generate <prompt> --runtime <ref>` | Generate a patch against the runtime baseline. |
| `forgeplay ai generate <prompt> --game <id>` | Generate a patch against the effective DSL of a game. |
| `forgeplay ai generate <prompt> --mod <id>` | Generate a patch against the effective DSL of a mod. |
| `forgeplay ai generate <prompt> --dsl <file>` | Generate a patch against a local DSL file. |
| `forgeplay ai quota` | Show today's AI generation allowance. |

`ai generate` prints the patch, the model, the number of retries and the token usage. The backend applies the patch and validates the result against the runtime schema before it answers, so a returned patch is known to produce a valid DSL. Further flags: `--save` stores the patch as a draft mod (login required, not available with `--dsl`); the draft carries the AI provenance mark only when the backend has `FORGEPLAY_SECRET` set and is saved unmarked otherwise, and the `AI generated mark` line of the output says which, `--patch-out <file>` writes the patch, `--dsl-out <file>` writes the resulting DSL. A generation has already used its quota unit when these run, so if a file cannot be written or the draft cannot be saved, the result is still printed and the command then fails with status 1.

Each call counts against a daily quota of 20 generations, per account for SMS and password accounts and per client IP for guests and anonymous callers.

### dsl

These commands need no backend.

| Command | Description |
| --- | --- |
| `forgeplay dsl validate <file>...` | Validate DSL files against the JSON Schema of their runtime. Exit status 1 when any file is invalid; every violation is listed with its JSON Pointer. |
| `forgeplay dsl patch <base.json> <patch.json> [-o out]` | Apply an RFC 6902 patch and print the result. `--validate` also checks the result against the schema and writes nothing when it is invalid. |
| `forgeplay dsl migrate <file> --to <version> [--from <ref>] [-o out]` | Upgrade a DSL file to a newer runtime version. The only existing path is shooter 0.x to 1.x. `--to` is a full version of the form `<major>.<minor>.<patch>`, such as `1.0.0`. |

The runtime ref (`<name>@<version>`, such as `shooter@1.0.0`) is read from `meta.runtime` and `meta.runtime_version` of the document; `--runtime` overrides it. Supported patch operations are `add`, `replace`, `remove` and `test`; `move` and `copy` are rejected, as on the backend and in the client. Object keys of a printed document are sorted.

The schema directory is resolved in this order: `--schema-dir`, `FORGEPLAY_SCHEMA_DIR`, the `schema-dir` setting, then `packages/schemas` of the repository checkout that contains the working directory.

## Configuration

Files live in one directory: `os.UserConfigDir()/forgeplay`, which is `~/Library/Application Support/forgeplay` on macOS, `~/.config/forgeplay` (or `$XDG_CONFIG_HOME/forgeplay`) on Linux and `%AppData%\forgeplay` on Windows.

| File | Content | Mode |
| --- | --- | --- |
| `config.json` | Settings written by `forgeplay config set`: `server_url`, `language`, `schema_dir`. | 0600 |
| `credentials.json` | One login token per server URL, with the user id, nickname and login method. | 0600 |

The directory itself is created with mode 0700. A directory that already exists keeps its mode, since `FORGEPLAY_CONFIG_DIR` may point at one you also use for other things. If the group or everyone can write to it, every command that connects to a backend prints `Warning: <dir> is writable by other users ...` on standard error, because another user could then replace the stored token or the server URL. `credentials.json` is narrowed to mode 0600 whenever it is read or written. None of this applies on Windows.

| Environment variable | Meaning |
| --- | --- |
| `FORGEPLAY_SERVER_URL` | Backend URL. Overrides the config file; `--server` overrides it. |
| `FORGEPLAY_SCHEMA_DIR` | Schema directory for the `dsl` commands. Overrides the config file; `--schema-dir` overrides it. |
| `FORGEPLAY_LANG` | Language of server messages: `zh`, `en` or `ja`. Overrides the config file. Without any setting the backend answers in Chinese. |
| `FORGEPLAY_CONFIG_DIR` | Use this directory instead of the default one. Useful for CI and tests. |

The server URL defaults to `http://localhost:8080`.

## Examples

Start a game from the runtime baseline, change it with a hand-written patch and publish it. This works on a freshly started backend:

```sh
forgeplay auth login
forgeplay mods create --runtime shooter@1.0.0       # prints the draft mod id
forgeplay mods dsl <draft-id> -o current.dsl.json
echo '[{"op":"replace","path":"/player/hp","value":250}]' > patch.json
forgeplay dsl patch current.dsl.json patch.json --validate > /dev/null
forgeplay mods save <draft-id> --patch patch.json   # prints the new draft id
forgeplay mods publish <new-draft-id> --title "Tanky"
```

To build on somebody else's game instead, replace the `mods create` line with a fork and credit the original when publishing. The game has to be one that was published from a mod and approved by a moderator; the showcase games a development backend is seeded with cannot be forked (see [games](#games)).

```sh
forgeplay games list --sort hot
forgeplay games fork <game-id>                      # prints the draft mod id
# ... the same dsl, patch and save steps ...
forgeplay mods publish <new-draft-id> --title "Tanky" --forked-from <game-id>
```

Generate with the AI on top of an existing mod and keep the patch for review:

```sh
forgeplay ai generate "add a wave of fast birds" --mod <mod-id> --patch-out birds.patch.json
forgeplay mods create --parent <mod-id> --patch birds.patch.json
```

Use the CLI in a script:

```sh
export FORGEPLAY_CONFIG_DIR="$(mktemp -d)" FORGEPLAY_SERVER_URL=https://play.example.com
forgeplay auth login --output json > /dev/null
mod_id=$(forgeplay ai generate "turn the player into a cat" --runtime shooter@1.0.0 --save --output json | jq -r .saved_mod.id)
forgeplay mods publish "$mod_id" --title "Cat Shooter" --output json | jq -r .status
```

Validate every DSL file of a repository in CI:

```sh
forgeplay dsl validate --schema-dir packages/schemas apps/client/runtime/*/baseline.dsl.json
```

## Development

```sh
cd apps/cli
GOWORK=off go vet ./...
GOWORK=off go test ./... -count=1
GOWORK=off go build -o /tmp/forgeplay ./cmd/forgeplay
```

`GOWORK=off` checks that the module builds on its own through its `replace` directives; without it the commands run inside the repository's Go workspace (`go.work`). From the repository root, `make cli-test` and `make cli-build` are the workspace equivalents.

Layout: `cmd/forgeplay` holds `main`, `internal/cli` the cobra command tree, `internal/config` the config and credentials files. The unit tests run the real command tree against an in-memory backend (`net/http/httptest`) and against the real runtime baselines and schemas of this repository.

`TestE2E` runs the same command tree against a real backend and is skipped unless `FORGEPLAY_CLI_E2E_URL` is set. Each run creates one guest account and spends one unit of the AI quota of the client IP:

```sh
# Terminal 1, in apps/server
PORT=18080 FORGEPLAY_DB=/tmp/forgeplay-e2e.db FORGEPLAY_SECRET=local-e2e-secret-0123456789abcdef go run ./cmd/server

# Terminal 2, in apps/cli
FORGEPLAY_CLI_E2E_URL=http://127.0.0.1:18080 GOWORK=off go test ./internal/cli -run TestE2E -count=1 -v
```
