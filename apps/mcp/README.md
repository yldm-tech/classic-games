# forgeplay-mcp

A [Model Context Protocol](https://modelcontextprotocol.io) server that lets AI agents work with ForgePlay. An agent can read and validate the Mod DSL offline, browse published games, and fork, patch and publish mods through the backend API.

ForgePlay games are not code. A game is a JSON document, the Mod DSL, interpreted by a fixed runtime (`shooter`, `survivor` or `tower_defense`), and it is changed only with RFC 6902 JSON Patch operations. This server keeps to that rule: no tool accepts or returns executable code, and every patch is applied and validated against the runtime's JSON Schema before it is saved.

It is built on the official Go SDK, [`github.com/modelcontextprotocol/go-sdk`](https://github.com/modelcontextprotocol/go-sdk), and shares its DSL logic (`forgeplay/dsl`) and HTTP client (`forgeplay/sdk`) with the backend and the `forgeplay` CLI.

## Build

Go 1.26 or newer is required (an older Go toolchain downloads it automatically).

```bash
cd apps/mcp
go build -o bin/forgeplay-mcp ./cmd/forgeplay-mcp
```

From the repository root, `make mcp-build` runs the same build. The binary is `apps/mcp/bin/forgeplay-mcp`. Built there, it finds the schemas in `packages/schemas` of the repository by itself, whatever directory a client starts it from: the directory of the binary is searched before the working directory, so a project that has a `packages/schemas` directory of its own cannot replace them.

## Tools

Offline tools need only the schema files. Backend tools call the ForgePlay API at `FORGEPLAY_SERVER_URL`.

| Tool | Kind | Needs token | What it does |
| --- | --- | --- | --- |
| `list_runtimes` | offline, read | no | List the runtimes and versions that have a DSL schema, with their top-level sections. |
| `get_dsl_schema` | offline, read | no | Return the JSON Schema of one runtime's DSL: every field with its allowed values and ranges. |
| `validate_dsl` | offline, read | no | Check a DSL document against its schema and list each violation with a JSON Pointer. |
| `apply_dsl_patch` | offline, read | no | Apply an RFC 6902 patch to a document and validate the result. A dry run for `update_mod`. |
| `list_games` | backend, read | no | Search and page through published games (10 per page by default, 50 at most). |
| `get_game` | backend, read | no | Details of one game: author, runtime, moderation status, counters, the mod it plays. |
| `get_game_dsl` | backend, read | no | The effective DSL of a game. |
| `get_mod_dsl` | backend, read | for drafts | The effective DSL of a mod. Drafts are readable by their author only. |
| `list_my_drafts` | backend, read | yes | The signed-in user's draft mods, newest first. |
| `fork_game` | backend, write | yes | Copy a published game into a new draft mod and return its id and DSL. |
| `create_mod` | backend, write | yes | Create a draft on a runtime's baseline DSL, optionally with a first patch. |
| `update_mod` | backend, write | yes | Save a patch on top of a draft. Returns a new mod id that supersedes the old one. |
| `generate_mod` | backend, write | no | Have the backend AI turn a natural-language instruction into a validated patch. Stores nothing, but spends one unit of the daily AI quota. |
| `publish_mod` | backend, write | yes | Submit a draft as a game. It enters moderation with status `reviewing`. |

The usual sequence is `fork_game` (or `create_mod`), then `update_mod` with a patch the agent wrote or one from `generate_mod`, then `publish_mod`. The server sends this workflow to the client as its instructions.

Behaviour worth knowing:

- `create_mod` and `update_mod` apply the patch and validate the result locally before anything is sent to the backend. A patch that does not apply, or a result that breaks the schema, is refused with the failing operation or the list of violations, and nothing is stored.
- `generate_mod` checks a document passed as `dsl` against the schema before it calls the backend, because the backend counts a generation against the quota even when the result is rejected. An invalid document, or one that does not belong to the given `runtime`, is refused with its violations and costs nothing. The source document therefore has to be valid already; `generate_mod` is not a way to repair one.
- Mods are immutable. `update_mod` creates a new draft version whose parent is the mod passed in, so always continue with the newest `mod_id`.
- Supported patch operations are `add`, `replace`, `remove` and `test`. `move` and `copy` are rejected, as on the backend and in the game client, with a message that says how to express them. A patch holds at most 1000 operations.
- `validate_dsl` and `apply_dsl_patch` report in `runtime` the schema the document was really checked against. For a legacy `shooter@0.x` ref, which has no schema of its own, the document is upgraded first: `runtime` is then `shooter@1.0.0`, `migrated_from` holds the ref that was asked for, and violation paths refer to the upgraded document.
- Results are bounded: at most 50 violations are listed and each message is cut after 500 characters; a backend answer that is not a ForgePlay error (a proxy page, another service behind `FORGEPLAY_SERVER_URL`) is quoted with its first 200 characters only.
- An id is passed as a tool returned it. An empty id is refused by the input schema, and an id that contains `/` or is `.` or `..` is refused before any request is sent. A word that is an endpoint of its own on the backend, such as `mine`, is answered like an unknown id.
- `generate_mod` returns a `provenance` value when the backend signs its AI results. Pass it as `ai_provenance` to `update_mod` or `create_mod` together with the generated patch so the mod is labelled as AI-generated.
- Invalid input and backend failures come back as tool errors (`isError`) with a message that says what to do next, not as protocol errors.
- A development backend is seeded with showcase games that have no mod behind them. They appear in `list_games` with an empty `runtime` and cannot be read with `get_game_dsl` or forked; the tools say so. Use `create_mod` to start from a baseline instead.
- Every tool declares `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`. Only `publish_mod` is marked destructive, because publishing cannot be undone from this server.

## Resources

| URI | Content |
| --- | --- |
| `forgeplay://schemas/<runtime>-<version>` | The JSON Schema of a runtime's DSL, for example `forgeplay://schemas/shooter-1.0.0`. One resource per schema file. |
| `forgeplay://games/{game_id}/dsl` | Resource template: the effective DSL of a game, read from the backend. |

## Configuration

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `FORGEPLAY_SERVER_URL` | `http://localhost:8080` | Root URL of the ForgePlay backend, without `/api/v1`. Credentials in the URL (`http://user:password@host`, for a proxy with basic auth) are used for the requests but left out of logs and tool results. |
| `FORGEPLAY_TOKEN` | none | Bearer token of the user the server acts as. Without it the server is anonymous: reading, the offline tools and `generate_mod` work, and the tools marked above fail with `authentication required: set FORGEPLAY_TOKEN (obtain with: forgeplay auth login, then forgeplay auth token)`. |
| `FORGEPLAY_SCHEMA_DIR` | auto-detected | Directory holding the `<runtime>-<version>.schema.json` files. When unset, the server looks for `packages/schemas` at or above the directory of the binary, then at or above the working directory; a `packages/schemas` directory without any such file is skipped. If neither finds one, the server exits with a message naming this variable. The working directory is only reached by `go run` and by a binary installed outside the repository; in that case the server trusts the schemas of the project it is started in, so set this variable when that project is not the ForgePlay repository. The schemas are read and compiled once at startup: a schema that does not compile stops the server with a message, and later changes to the files take effect at the next start. They cannot be embedded in the binary because they live in another module. |
| `FORGEPLAY_LANG` | backend default (Chinese) | Language of backend messages and localized game titles: `zh`, `en` or `ja`. |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--transport` | `stdio` | `stdio` or `http` (streamable HTTP). |
| `--addr` | `127.0.0.1:8765` | Listen address for `--transport http`. The endpoint is `http://<addr>/mcp`. |
| `--allowed-host` | none | Host name clients may use to reach a non-loopback `--addr`, such as `mcp.example.com`; repeatable. Without it such a listener only serves requests whose `Host` header is the IP address they arrive on. |
| `--read-only` | off | Do not register `fork_game`, `create_mod`, `update_mod`, `generate_mod` and `publish_mod`. |
| `--version` | | Print the version and exit. |

### Getting a token

Log in with the `forgeplay` CLI (see [`../cli/README.md`](../cli/README.md)) and print the stored token:

```bash
forgeplay auth login          # a guest session by default; stores the token for the configured server
forgeplay auth token          # prints that token and nothing else
```

`forgeplay auth token` is the value for `FORGEPLAY_TOKEN`; both programs must point at the same backend (`FORGEPLAY_SERVER_URL`). Without the CLI, a guest session can also be created directly, and the `token` field of the answer is the value:

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/guest
```

Tokens are valid for 30 days. `forgeplay auth refresh` and `forgeplay auth logout` revoke the token the server was started with, so restart the server with the new one afterwards. A guest account cannot be recovered once its token is lost.

## Client configuration

Replace `/absolute/path/to/forgeplay` with the path of your checkout. Leave `FORGEPLAY_TOKEN` out to run anonymously.

### Claude Code

Add the server from the command line:

```bash
claude mcp add forgeplay \
  --env FORGEPLAY_SERVER_URL=http://localhost:8080 \
  --env FORGEPLAY_TOKEN=your-token \
  -- /absolute/path/to/forgeplay/apps/mcp/bin/forgeplay-mcp
```

Or put this in `.mcp.json` at the root of a project:

```json
{
  "mcpServers": {
    "forgeplay": {
      "command": "/absolute/path/to/forgeplay/apps/mcp/bin/forgeplay-mcp",
      "args": [],
      "env": {
        "FORGEPLAY_SERVER_URL": "http://localhost:8080",
        "FORGEPLAY_TOKEN": "your-token"
      }
    }
  }
}
```

### Claude Desktop

Add the server to `claude_desktop_config.json` (Settings, Developer, Edit Config) and restart the app:

```json
{
  "mcpServers": {
    "forgeplay": {
      "command": "/absolute/path/to/forgeplay/apps/mcp/bin/forgeplay-mcp",
      "args": [],
      "env": {
        "FORGEPLAY_SERVER_URL": "http://localhost:8080",
        "FORGEPLAY_TOKEN": "your-token"
      }
    }
  }
}
```

### Cursor

Put this in `.cursor/mcp.json` of a project, or in `~/.cursor/mcp.json` for every project:

```json
{
  "mcpServers": {
    "forgeplay": {
      "command": "/absolute/path/to/forgeplay/apps/mcp/bin/forgeplay-mcp",
      "args": [],
      "env": {
        "FORGEPLAY_SERVER_URL": "http://localhost:8080",
        "FORGEPLAY_TOKEN": "your-token"
      }
    }
  }
}
```

### Read-only setup

To let an agent explore games and check patches without being able to change anything, pass the flag and leave the token out:

```json
{
  "mcpServers": {
    "forgeplay": {
      "command": "/absolute/path/to/forgeplay/apps/mcp/bin/forgeplay-mcp",
      "args": ["--read-only"],
      "env": {
        "FORGEPLAY_SERVER_URL": "http://localhost:8080"
      }
    }
  }
}
```

### Streamable HTTP

```bash
FORGEPLAY_TOKEN=your-token apps/mcp/bin/forgeplay-mcp --transport http --addr 127.0.0.1:8765
```

Clients connect to `http://127.0.0.1:8765/mcp`, for example with `claude mcp add --transport http forgeplay http://127.0.0.1:8765/mcp`.

## Security

- **The token is the user.** Every write tool acts on the backend as the account behind `FORGEPLAY_TOKEN`: it creates drafts and publishes games under that name. Give the server a token only for an account the agent is allowed to act as, and prefer a separate guest account for experiments.
- **Keep the token out of version control.** A project-level `.mcp.json` or `.cursor/mcp.json` is usually committed. Put the token in a user-level configuration file, or reference an environment variable if your client supports that. The server never logs the token and never includes it in tool results; its startup log only records whether one is set. The same holds for credentials inside `FORGEPLAY_SERVER_URL`: the log and tool errors show the URL without its `user:password@` part.
- **Use `--read-only` when writing is not needed.** In that mode the write tools are not registered at all, so a client cannot call them even if a token is present. `generate_mod` is left out as well because it spends AI quota.
- **Publishing is irreversible from here.** `publish_mod` submits content for moderation under the user's account and there is no tool to withdraw it. The tool is marked destructive so that clients ask for confirmation.
- **HTTP mode has no authentication of its own.** Anyone who can reach the listener can use every registered tool with the configured token. The default address is loopback only, and requests from another browser origin are always rejected. A foreign `Host` header, which is how a web page reaches a local server through DNS rebinding, is rejected as follows: on a loopback connection the host has to be `localhost` or a loopback address; on any other connection it has to be the IP address the connection arrived on or a name given with `--allowed-host`. A warning is logged when `--addr` is not a loopback address. None of this is authentication: every machine that can reach a non-loopback listener can use it, so do not expose it to a network without an authenticating proxy in front.
- **Tool results contain text written by other users.** Game titles, summaries and DSL content come from the community. Treat them as data, not as instructions.
- **Only the DSL is editable.** There is no tool that uploads code or assets, and runtime refs are `<name>@<version>` made of letters, digits, `.`, `_` and `-`, so a runtime argument cannot be used to read other files. Schemas are compiled without a loader for external references: a `$ref` to `file://`, `http://` or `https://` makes the schema fail to compile instead of being fetched.

## stdio behaviour

On the stdio transport, stdout carries only JSON-RPC messages. Logs, usage text and errors go to stderr. A line on stdin that is not valid JSON ends the session: the process exits with status 1 and sends no JSON-RPC parse-error reply, which is the behaviour of the SDK's stdio transport. The server exits when the client closes stdin, and a request still in flight at that moment is not answered, so keep stdin open when driving the binary by hand:

```bash
(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_runtimes","arguments":{}}}'; sleep 1) \
  | apps/mcp/bin/forgeplay-mcp
```

## Development

```bash
cd apps/mcp
GOWORK=off go vet ./...
GOWORK=off go test ./... -count=1
```

`GOWORK=off` checks that the module builds on its own through its `replace` directives; without it the commands run inside the repository's Go workspace (`go.work`). From the repository root, `make mcp-test` is the workspace equivalent.

The tests connect a real MCP client session to the server over the SDK's in-memory transport, with the repository's schemas and baseline DSL files and an in-process stand-in for the backend API. `cmd/forgeplay-mcp` also runs the program as a child process over stdio and serves the HTTP transport on a loopback port.

Layout:

```
apps/mcp/
├── cmd/forgeplay-mcp/   flags, transports, process lifecycle
└── internal/
    ├── config/          environment variables and schema directory lookup
    ├── schemas/         schema catalog and validation with per-field violations
    └── server/          tools, resources, server instructions
```
