// Package server builds the forgeplay-mcp Model Context Protocol server: offline Mod DSL tools backed by the schema catalog, backend tools backed by forgeplay/sdk, and the schema and game DSL resources.
package server

import (
	"log/slog"
	"net/url"
	"strings"

	"forgeplay/mcp/internal/schemas"
	"forgeplay/sdk"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// Name is the server name reported to MCP clients.
const Name = "forgeplay-mcp"

// Options configures New.
type Options struct {
	// Version is reported to clients in the initialize result.
	Version string
	// Catalog holds the runtime schemas used by the offline tools and by pre-save validation.
	Catalog *schemas.Catalog
	// Backend is the ForgePlay API client. Its token decides whether the write tools can succeed.
	Backend *sdk.Client
	// ReadOnly leaves out every tool that changes backend state or consumes AI quota.
	ReadOnly bool
	// Logger receives server activity; nil disables logging. It must not write to stdout when the stdio transport is used.
	Logger *slog.Logger
}

// service carries the dependencies shared by the tool and resource handlers.
type service struct {
	catalog *schemas.Catalog
	backend *sdk.Client
	// backendURL is the backend address as it may be shown in logs and tool errors (see DisplayURL).
	backendURL string
}

// DisplayURL returns a backend URL in the form that is safe to log and to put into tool results: without the userinfo part. A URL such as http://user:password@host carries credentials for a proxy in front of the backend; tool errors go to the model and the log goes to the client, and neither may receive them.
func DisplayURL(backendURL string) string {
	parsed, err := url.Parse(backendURL)
	if err != nil {
		return "the configured backend URL"
	}
	parsed.User = nil
	return parsed.String()
}

// New returns an MCP server with the ForgePlay tools and resources registered. Both Catalog and Backend are required.
func New(options Options) *mcp.Server {
	s := &service{catalog: options.Catalog, backend: options.Backend, backendURL: DisplayURL(options.Backend.BaseURL())}
	server := mcp.NewServer(&mcp.Implementation{
		Name:    Name,
		Title:   "ForgePlay",
		Version: options.Version,
	}, &mcp.ServerOptions{
		Instructions: instructions(options.ReadOnly, options.Backend.Token() != ""),
		Logger:       options.Logger,
	})
	s.addOfflineTools(server)
	s.addReadTools(server)
	if !options.ReadOnly {
		s.addWriteTools(server)
	}
	s.addResources(server)
	return server
}

// instructions is the usage guide sent to clients at initialization. It states the one rule of the platform (only the DSL is edited, never code) and the fork, patch, validate, publish workflow.
func instructions(readOnly, hasToken bool) string {
	paragraphs := []string{
		"ForgePlay is a mini-game creation platform. A game is not code: it is a JSON document, the Mod DSL, interpreted by a fixed runtime (shooter, survivor or tower_defense). A game is changed only by editing its DSL with RFC 6902 JSON Patch operations (add, replace, remove, test). Never write or request executable code, scripts or assets; every value must satisfy the enums and ranges of the runtime's JSON Schema.",
		"Workflow: (1) Discover: list_runtimes and get_dsl_schema describe what a DSL may contain; list_games, get_game and get_game_dsl show existing games. (2) Start a draft: fork_game copies a published game into a draft mod you own, create_mod starts one from a runtime baseline; both return the mod_id and the draft's effective DSL. (3) Patch: write a patch against that DSL and save it with update_mod, or call generate_mod to have the backend AI turn an instruction into a patch and then save that patch with update_mod, passing its provenance value. (4) Validate: create_mod and update_mod apply the patch and validate the result against the schema before saving; an invalid result is rejected with the list of violations and nothing is stored, so fix the patch and call again. validate_dsl and apply_dsl_patch run the same checks offline without saving. (5) Publish: publish_mod submits the draft as a game, which stays in status \"reviewing\" until a moderator approves it.",
		"Mods are immutable: update_mod returns a new mod_id that supersedes the one passed in, so always continue with the newest id. Patch paths are JSON Pointers. Collections such as enemies and drops are objects keyed by id (for example /enemies/dog_1/count), not arrays.",
	}
	switch {
	case readOnly:
		paragraphs = append(paragraphs, "This server runs in read-only mode: fork_game, create_mod, update_mod, generate_mod and publish_mod are not available. Use the offline tools to prepare and check patches.")
	case !hasToken:
		paragraphs = append(paragraphs, "No FORGEPLAY_TOKEN is configured: reading, the offline tools and generate_mod work, while fork_game, create_mod, update_mod, publish_mod and list_my_drafts fail until a token is set.")
	}
	return strings.Join(paragraphs, "\n\n")
}
