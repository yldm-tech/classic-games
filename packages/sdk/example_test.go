package sdk_test

import (
	"context"
	"errors"
	"fmt"
	"log"

	"forgeplay/sdk"
)

// The examples below are compiled with the tests but not executed, because they need a running backend. They mirror the snippets in README.md.

func Example() {
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

func ExamplePaginate() {
	ctx := context.Background()
	client, err := sdk.New(sdk.DefaultBaseURL)
	if err != nil {
		log.Fatal(err)
	}

	for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
		return client.ListGames(ctx, sdk.ListGamesParams{Runtime: "shooter", PageParams: sdk.PageParams{Cursor: cursor, Limit: sdk.MaxPageLimit}})
	}) {
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(game.ID, game.Title)
	}
}

func ExampleAPIError() {
	ctx := context.Background()
	client, err := sdk.New(sdk.DefaultBaseURL)
	if err != nil {
		log.Fatal(err)
	}

	game, err := client.GetGame(ctx, "ashfall")
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
}
