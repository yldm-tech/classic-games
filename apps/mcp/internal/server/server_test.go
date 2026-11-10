package server_test

import (
	"context"
	"encoding/json"
	"slices"
	"sort"
	"strings"
	"testing"

	"forgeplay/mcp/internal/server"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// hints is the annotation set a tool is expected to declare.
type hints struct {
	readOnly    bool
	destructive bool
	idempotent  bool
	openWorld   bool
}

var (
	offlineRead = hints{readOnly: true, idempotent: true}
	backendRead = hints{readOnly: true, idempotent: true, openWorld: true}
	backendAdd  = hints{openWorld: true}
)

// wantTools is every tool of a read-write server with its required arguments and annotations.
var wantTools = map[string]struct {
	required []string
	hints    hints
}{
	"list_runtimes":   {nil, offlineRead},
	"get_dsl_schema":  {[]string{"runtime"}, offlineRead},
	"validate_dsl":    {[]string{"dsl"}, offlineRead},
	"apply_dsl_patch": {[]string{"dsl", "patch"}, offlineRead},
	"list_games":      {nil, backendRead},
	"get_game":        {[]string{"game_id"}, backendRead},
	"get_game_dsl":    {[]string{"game_id"}, backendRead},
	"get_mod_dsl":     {[]string{"mod_id"}, backendRead},
	"list_my_drafts":  {nil, backendRead},
	"fork_game":       {[]string{"game_id"}, backendAdd},
	"create_mod":      {[]string{"runtime"}, backendAdd},
	"update_mod":      {[]string{"mod_id", "patch"}, backendAdd},
	"generate_mod":    {[]string{"instruction"}, backendAdd},
	"publish_mod":     {[]string{"mod_id", "title"}, hints{destructive: true, openWorld: true}},
}

var writeTools = []string{"fork_game", "create_mod", "update_mod", "generate_mod", "publish_mod"}

func listTools(t *testing.T, cs *mcp.ClientSession) map[string]*mcp.Tool {
	t.Helper()
	tools := map[string]*mcp.Tool{}
	for tool, err := range cs.Tools(context.Background(), nil) {
		if err != nil {
			t.Fatalf("list tools: %v", err)
		}
		tools[tool.Name] = tool
	}
	return tools
}

func TestInitialize(t *testing.T) {
	cs := connect(t, session{})
	result := cs.InitializeResult()
	if result.ServerInfo.Name != server.Name || result.ServerInfo.Version != testVersion {
		t.Errorf("server info = %+v, want name %q version %q", result.ServerInfo, server.Name, testVersion)
	}
	mustContain(t, result.Instructions, "Never write or request executable code", "RFC 6902", "fork_game", "update_mod", "validate", "publish_mod", "No FORGEPLAY_TOKEN is configured")
	if result.Capabilities.Tools == nil || result.Capabilities.Resources == nil {
		t.Errorf("capabilities = %+v, want tools and resources", result.Capabilities)
	}

	withToken := connect(t, session{token: "tok"}).InitializeResult().Instructions
	if strings.Contains(withToken, "No FORGEPLAY_TOKEN") || strings.Contains(withToken, "read-only") {
		t.Errorf("instructions with a token mention a missing token or read-only mode: %q", withToken)
	}
	mustContain(t, connect(t, session{readOnly: true}).InitializeResult().Instructions, "read-only mode")
}

func TestToolList(t *testing.T) {
	tools := listTools(t, connect(t, session{}))

	var got, want []string
	for name := range tools {
		got = append(got, name)
	}
	for name := range wantTools {
		want = append(want, name)
	}
	sort.Strings(got)
	sort.Strings(want)
	if !slices.Equal(got, want) {
		t.Fatalf("tools = %v, want %v", got, want)
	}

	for name, expected := range wantTools {
		tool := tools[name]
		t.Run(name, func(t *testing.T) {
			if len(tool.Description) < 40 {
				t.Errorf("description is too short to guide a model: %q", tool.Description)
			}

			annotations := tool.Annotations
			if annotations == nil || annotations.Title == "" || annotations.DestructiveHint == nil || annotations.OpenWorldHint == nil {
				t.Fatalf("annotations must set a title and every hint explicitly, got %+v", annotations)
			}
			actual := hints{readOnly: annotations.ReadOnlyHint, destructive: *annotations.DestructiveHint, idempotent: annotations.IdempotentHint, openWorld: *annotations.OpenWorldHint}
			if actual != expected.hints {
				t.Errorf("hints = %+v, want %+v", actual, expected.hints)
			}

			input := schemaObject(t, tool.InputSchema)
			if input["type"] != "object" || input["additionalProperties"] != false {
				t.Errorf("input schema must be a closed object, got type=%v additionalProperties=%v", input["type"], input["additionalProperties"])
			}
			var required []string
			for _, property := range asList(input["required"]) {
				required = append(required, property.(string))
			}
			sort.Strings(required)
			wantRequired := slices.Clone(expected.required)
			sort.Strings(wantRequired)
			if !slices.Equal(required, wantRequired) {
				t.Errorf("required = %v, want %v", required, wantRequired)
			}
			checkSchema(t, "input", input, true)

			if tool.OutputSchema == nil {
				t.Fatal("output schema is missing")
			}
			output := schemaObject(t, tool.OutputSchema)
			if output["type"] != "object" {
				t.Errorf("output schema type = %v, want object", output["type"])
			}
			checkSchema(t, "output", output, true)
		})
	}
}

func TestToolSchemaDetails(t *testing.T) {
	tools := listTools(t, connect(t, session{}))

	games := schemaObject(t, tools["list_games"].InputSchema)["properties"].(map[string]any)
	limit := games["limit"].(map[string]any)
	if limit["minimum"] != float64(1) || limit["maximum"] != float64(50) || limit["default"] != float64(10) {
		t.Errorf("list_games limit = %v, want minimum 1, maximum 50, default 10", limit)
	}
	if !jsonEqual(games["sort"].(map[string]any)["enum"], []string{"new", "hot", "rising"}) {
		t.Errorf("list_games sort enum = %v", games["sort"])
	}
	if games["ai_generated"].(map[string]any)["type"] != "boolean" {
		t.Errorf("list_games ai_generated = %v, want a plain boolean", games["ai_generated"])
	}

	patch := schemaObject(t, tools["update_mod"].InputSchema)["properties"].(map[string]any)["patch"].(map[string]any)
	if patch["type"] != "array" || patch["minItems"] != float64(1) {
		t.Errorf("update_mod patch = %v, want a non-empty array", patch)
	}
	operation := patch["items"].(map[string]any)
	if !jsonEqual(operation["required"], []string{"op", "path"}) {
		t.Errorf("patch operation required = %v, want [op path]", operation["required"])
	}
	value := operation["properties"].(map[string]any)["value"].(map[string]any)
	if _, typed := value["type"]; typed {
		t.Errorf("patch operation value must accept any JSON value, got %v", value)
	}

	tags := schemaObject(t, tools["publish_mod"].InputSchema)["properties"].(map[string]any)["tags"].(map[string]any)
	if tags["maxItems"] != float64(3) {
		t.Errorf("publish_mod tags = %v, want maxItems 3", tags)
	}
}

func TestReadOnlyHidesWriteTools(t *testing.T) {
	cs := connect(t, session{readOnly: true, token: "tok"})
	tools := listTools(t, cs)
	for _, name := range writeTools {
		if _, present := tools[name]; present {
			t.Errorf("read-only server exposes write tool %s", name)
		}
	}
	if len(tools) != len(wantTools)-len(writeTools) {
		t.Errorf("read-only server has %d tools, want %d", len(tools), len(wantTools)-len(writeTools))
	}
	for name, tool := range tools {
		if !tool.Annotations.ReadOnlyHint {
			t.Errorf("read-only server exposes %s, which is not marked read-only", name)
		}
	}
	// A hidden tool is unknown to the server, not merely unlisted.
	if _, err := cs.CallTool(context.Background(), &mcp.CallToolParams{Name: "publish_mod", Arguments: map[string]any{"mod_id": "m_1", "title": "x"}}); err == nil {
		t.Error("calling publish_mod on a read-only server succeeded, want an unknown tool error")
	}
}

// schemaObject decodes a schema as received by the client into a generic object.
func schemaObject(t *testing.T, schema any) map[string]any {
	t.Helper()
	encoded, err := json.Marshal(schema)
	if err != nil {
		t.Fatalf("encode schema: %v", err)
	}
	var object map[string]any
	if err := json.Unmarshal(encoded, &object); err != nil {
		t.Fatalf("schema is not an object: %v", err)
	}
	return object
}

func asList(value any) []any {
	list, _ := value.([]any)
	return list
}

// checkSchema walks a tool schema and requires a description on every property and a single plain type everywhere (no ["null", T] unions).
func checkSchema(t *testing.T, where string, schema map[string]any, root bool) {
	t.Helper()
	if _, isUnion := schema["type"].([]any); isUnion {
		t.Errorf("%s: type is a union %v, want one plain type", where, schema["type"])
	}
	if !root {
		if description, _ := schema["description"].(string); description == "" {
			t.Errorf("%s: missing description", where)
		}
	}
	properties, _ := schema["properties"].(map[string]any)
	for name, property := range properties {
		checkSchema(t, where+"."+name, property.(map[string]any), false)
	}
	if items, ok := schema["items"].(map[string]any); ok {
		// Array items are described by the array property itself; only their own properties need descriptions.
		checkSchema(t, where+"[]", items, true)
	}
}
