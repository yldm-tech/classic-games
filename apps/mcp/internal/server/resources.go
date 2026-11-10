package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	schemaURIPrefix = "classic-games://schemas/"
	gameURIPrefix   = "classic-games://games/"
	gameDSLSuffix   = "/dsl"
	gameDSLTemplate = gameURIPrefix + "{game_id}" + gameDSLSuffix
)

// schemaURI is the stable resource URI of a runtime schema: classic-games://schemas/<name>-<version>.
func schemaURI(name, version string) string {
	return schemaURIPrefix + name + "-" + version
}

// addResources registers one resource per schema in the catalog and a template for the effective DSL of any game.
func (s *service) addResources(server *mcp.Server) {
	for _, runtime := range s.catalog.Runtimes() {
		content := string(runtime.Schema)
		uri := schemaURI(runtime.Name, runtime.Version)
		title := runtime.Title
		if title == "" {
			title = runtime.Ref + " DSL schema"
		}
		server.AddResource(&mcp.Resource{
			URI:         uri,
			Name:        runtime.Name + "-" + runtime.Version + ".schema.json",
			Title:       title,
			Description: "JSON Schema (draft 2020-12) of the " + runtime.Ref + " Mod DSL: every field with its allowed values and ranges.",
			MIMEType:    "application/schema+json",
			Size:        int64(len(content)),
		}, func(context.Context, *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
			return &mcp.ReadResourceResult{Contents: []*mcp.ResourceContents{{URI: uri, MIMEType: "application/schema+json", Text: content}}}, nil
		})
	}

	server.AddResourceTemplate(&mcp.ResourceTemplate{
		URITemplate: gameDSLTemplate,
		Name:        "game-dsl",
		Title:       "Game DSL",
		Description: "Effective DSL of a game, read from the Classic Games backend: the runtime baseline with the game's whole patch chain applied. game_id is a game id as returned by the list_games tool.",
		MIMEType:    "application/json",
	}, s.readGameDSL)
}

func (s *service) readGameDSL(ctx context.Context, request *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
	uri := request.Params.URI
	rest, ok := strings.CutPrefix(uri, gameURIPrefix)
	gameID, hasSuffix := strings.CutSuffix(rest, gameDSLSuffix)
	if !ok || !hasSuffix || gameID == "" || strings.Contains(gameID, "/") {
		return nil, mcp.ResourceNotFoundError(uri)
	}
	document, err := s.backend.GetGameDSL(ctx, gameID)
	if err != nil {
		if sdk.IsNotFound(err) {
			return nil, mcp.ResourceNotFoundError(uri)
		}
		return nil, s.backendError(fmt.Sprintf("read the DSL of game %q", gameID), err)
	}
	content, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode the DSL of game %q: %w", gameID, err)
	}
	return &mcp.ReadResourceResult{Contents: []*mcp.ResourceContents{{URI: uri, MIMEType: "application/json", Text: string(content)}}}, nil
}
