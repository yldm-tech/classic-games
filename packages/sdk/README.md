# forgeplay/sdk

Typed Go client for the ForgePlay backend HTTP API (`apps/server`). It is the transport layer shared by the `forgeplay` CLI (`apps/cli`) and the MCP server (`apps/mcp`), and it depends only on the Go standard library.

## Install

The module lives in this repository and is consumed through a `replace` directive. From another module in the monorepo, for example `apps/cli`:

```
require forgeplay/sdk v0.0.0

replace forgeplay/sdk => ../../packages/sdk
```

Then run `GOWORK=off go mod tidy`.

## Example

```go
package main

import (
	"context"
	"fmt"
	"log"

	"forgeplay/sdk"
)

func main() {
	ctx := context.Background()

	client, err := sdk.New("http://localhost:8080", sdk.WithLanguage("en"))
	if err != nil {
		log.Fatal(err)
	}

	// A guest session needs no credentials. Login methods return the token; SetToken makes the client use it.
	session, err := client.LoginGuest(ctx)
	if err != nil {
		log.Fatal(err)
	}
	client.SetToken(session.Token)

	// Ask the AI for a change to the shooter baseline. The model only returns a JSON Patch; the backend applies and validates it.
	baseline, err := client.GetRuntimeBaseline(ctx, "shooter", "1.0.0")
	if err != nil {
		log.Fatal(err)
	}
	generated, err := client.GenerateMod(ctx, sdk.GenerateModRequest{
		Runtime:    "shooter@1.0.0",
		CurrentDSL: baseline,
		Prompt:     "turn the player into a cat",
	})
	if err != nil {
		log.Fatal(err)
	}

	// Store the patch as a draft mod, then submit it for review as a game.
	draft, err := client.CreateMod(ctx, sdk.CreateModRequest{
		Runtime:      "shooter@1.0.0",
		Patch:        generated.DSLPatch,
		AIProvenance: generated.Provenance,
		Draft:        true,
	})
	if err != nil {
		log.Fatal(err)
	}
	game, err := client.PublishDraft(ctx, draft.ID, sdk.PublishDraftRequest{Title: "Cat Shooter"})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(game.ID, game.Status) // status is "reviewing" until a moderator approves it
}
```

Cursor-paginated listings return a `Page` with `Items` and `NextCursor`. `Paginate` walks every page:

```go
for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
	return client.ListGames(ctx, sdk.ListGamesParams{Runtime: "shooter", PageParams: sdk.PageParams{Cursor: cursor, Limit: sdk.MaxPageLimit}})
}) {
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(game.ID, game.Title)
}
```

## Authentication

Send a bearer token with `sdk.WithToken` at construction or `client.SetToken` later. `SetToken` is the only method that changes the client's credentials.

- `LoginGuest` always works and is the default for tools. Guest accounts cannot be recovered once the token is lost.
- `SendSMSCode` plus `LoginSMS` needs a backend with an SMS gateway (`Meta().SMS` is true).
- `LoginPassword` works for accounts that called `SetPassword` before.
- `RefreshToken` revokes the current token and returns a new one valid for 30 days; call `SetToken` with it. `Logout` revokes the current token.

Reads of the public catalog (games, ranking, runtimes, comments, profiles) need no token. Creating mods, forking, publishing, commenting, liking and reporting play sessions need one.

## AI quota

`GenerateMod` and `GenerateStructure` share a quota of 20 calls per day, counted per account for signed-in users and per client IP for guests and anonymous callers. An exhausted quota fails with `429 QUOTA_EXCEEDED`. Requests rejected before the model runs (`400`) are refunded; `422 DSL_INVALID` and `502 PROVIDER_ERROR` still count. `AIQuota` reads the current state without consuming it. `AutoBalance` and `ValidateDSL` are free.

## Error handling

Every non-2xx response is returned as `*sdk.APIError` carrying the HTTP status, the backend's error code and its localized message. When the body is not a ForgePlay error envelope (a proxy error page, for example), `Message` holds only its first 512 bytes. Network failures and context cancellation are returned as ordinary wrapped errors.

Two kinds of failure are raised by the client itself and can be matched with `errors.Is`:

- `sdk.ErrInvalidArgument`: an id or name argument is empty, contains `/` or is `.` or `..`. Path parameters are escaped, which keeps `?` and `#` out of the query string, but the backend routes on the decoded path, so such an id would reach a different endpoint. The call fails before any request is sent.
- `sdk.ErrBadResponse`: a 2xx answer whose body is not the expected JSON or is larger than 32 MiB, which usually means the base URL does not point at a ForgePlay backend.

Some words are endpoints of their own: `GET /games/mine`, `GET /users/me`, `GET /games/{id}/replays/leaderboard`. Passing such a word as an id makes the backend answer 200 with something else. `GetGame`, `GetMod`, `GetModForkTree`, `GetUserProfile` and `GetLatestReplay` compare the id of the answer with the id that was asked for and return a `404 NOT_FOUND` `*sdk.APIError` on a mismatch, so `sdk.IsNotFound` covers this case and no zero-value resource is returned.

```go
game, err := client.GetGame(ctx, id)
switch {
case err == nil:
	fmt.Println(game.Title)
case sdk.IsNotFound(err):
	fmt.Println("no such game")
case sdk.IsUnauthorized(err):
	fmt.Println("sign in first")
case sdk.IsCode(err, sdk.CodeQuotaExceeded):
	fmt.Println("AI quota used up for today")
default:
	var apiErr *sdk.APIError
	if errors.As(err, &apiErr) {
		fmt.Println(apiErr.StatusCode, apiErr.Code, apiErr.Message)
	}
	log.Fatal(err)
}
```

## Tests

```
GOWORK=off go vet ./...
GOWORK=off go test ./... -count=1
```

`TestE2E` runs against a real backend and is skipped unless `FORGEPLAY_SDK_E2E_URL` is set. Start a backend with the stub AI provider (no `ANTHROPIC_API_KEY`) and a throwaway database, then point the test at it:

```
cd apps/server
PORT=18080 FORGEPLAY_DB=/tmp/forgeplay-e2e.db FORGEPLAY_SECRET=local-e2e-secret go run ./cmd/server

cd packages/sdk
FORGEPLAY_SDK_E2E_URL=http://127.0.0.1:18080 GOWORK=off go test ./... -run TestE2E -count=1 -v
```
