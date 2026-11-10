package server_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/jsonrpc"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestSchemaResources(t *testing.T) {
	cs := connect(t, session{})
	ctx := context.Background()

	var uris []string
	for resource, err := range cs.Resources(ctx, nil) {
		if err != nil {
			t.Fatalf("list resources: %v", err)
		}
		uris = append(uris, resource.URI)
		if resource.MIMEType != "application/schema+json" || resource.Name == "" || resource.Description == "" || resource.Size == 0 {
			t.Errorf("resource %s is not fully described: %+v", resource.URI, resource)
		}
	}
	slices.Sort(uris)
	want := []string{"classic-games://schemas/shooter-1.0.0", "classic-games://schemas/survivor-1.0.0", "classic-games://schemas/tower_defense-1.0.0"}
	if !slices.Equal(uris, want) {
		t.Fatalf("resources = %v, want %v", uris, want)
	}

	for _, name := range runtimeNames {
		uri := "classic-games://schemas/" + name + "-1.0.0"
		result, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: uri})
		if err != nil {
			t.Fatalf("read %s: %v", uri, err)
		}
		file, err := os.ReadFile(filepath.Join(schemaDir(t), name+"-1.0.0.schema.json"))
		if err != nil {
			t.Fatal(err)
		}
		if len(result.Contents) != 1 || result.Contents[0].URI != uri || result.Contents[0].MIMEType != "application/schema+json" || result.Contents[0].Text != string(file) {
			t.Errorf("%s does not serve the schema file verbatim", uri)
		}
	}

	_, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "classic-games://schemas/racing-1.0.0"})
	requireNotFound(t, err)
}

func TestGameDSLResourceTemplate(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL})
	ctx := context.Background()

	var templates []string
	for template, err := range cs.ResourceTemplates(ctx, nil) {
		if err != nil {
			t.Fatalf("list resource templates: %v", err)
		}
		templates = append(templates, template.URITemplate)
		if template.MIMEType != "application/json" || template.Description == "" {
			t.Errorf("template is not fully described: %+v", template)
		}
	}
	if want := []string{"classic-games://games/{game_id}/dsl"}; !slices.Equal(templates, want) {
		t.Fatalf("resource templates = %v, want %v", templates, want)
	}

	result, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "classic-games://games/g_3/dsl"})
	if err != nil {
		t.Fatalf("read game DSL: %v", err)
	}
	var document map[string]any
	if err := json.Unmarshal([]byte(result.Contents[0].Text), &document); err != nil {
		t.Fatalf("game DSL resource is not JSON: %v", err)
	}
	if result.Contents[0].MIMEType != "application/json" || at(t, document, "stage", "background") != "desert" || at(t, document, "meta", "runtime") != "tower_defense" {
		t.Errorf("game DSL resource = %v", document)
	}

	_, err = cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "classic-games://games/g_404/dsl"})
	requireNotFound(t, err)
	_, err = cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "classic-games://games/g_3/lineage"})
	requireNotFound(t, err)
}

// requireNotFound asserts err is the protocol's resource-not-found error.
func requireNotFound(t *testing.T, err error) {
	t.Helper()
	var wireErr *jsonrpc.Error
	if !errors.As(err, &wireErr) || wireErr.Code != mcp.CodeResourceNotFound {
		t.Fatalf("error = %v, want resource not found (%d)", err, mcp.CodeResourceNotFound)
	}
}
