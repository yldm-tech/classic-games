package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// The offline tools work from the schema catalog alone; they never contact the backend.

type listRuntimesInput struct{}

type runtimeInfo struct {
	Runtime          string   `json:"runtime" jsonschema:"runtime ref to pass to the other tools, for example shooter@1.0.0"`
	Name             string   `json:"name" jsonschema:"runtime name, the value of meta.runtime in a DSL"`
	Version          string   `json:"version" jsonschema:"schema version, the value of meta.runtime_version in a DSL"`
	Title            string   `json:"title" jsonschema:"title of the schema"`
	Sections         []string `json:"sections" jsonschema:"top-level keys a DSL of this runtime may contain"`
	RequiredSections []string `json:"required_sections" jsonschema:"top-level keys a DSL of this runtime must contain"`
	SchemaURI        string   `json:"schema_uri" jsonschema:"URI of the MCP resource holding the JSON Schema"`
}

type listRuntimesOutput struct {
	Runtimes []runtimeInfo `json:"runtimes" jsonschema:"the runtimes this server has a schema for"`
}

type getDSLSchemaInput struct {
	Runtime string `json:"runtime" jsonschema:"runtime ref, for example shooter@1.0.0; list_runtimes returns the valid values"`
}

type getDSLSchemaOutput struct {
	Runtime string         `json:"runtime" jsonschema:"runtime ref the schema belongs to"`
	Schema  map[string]any `json:"schema" jsonschema:"the JSON Schema (draft 2020-12) of the runtime's DSL"`
}

type validateDSLInput struct {
	DSL     map[string]any `json:"dsl" jsonschema:"the complete DSL document to check"`
	Runtime string         `json:"runtime,omitempty" jsonschema:"runtime ref to validate against, for example shooter@1.0.0. Defaults to meta.runtime and meta.runtime_version of the document."`
}

type validateDSLOutput struct {
	Runtime      string `json:"runtime" jsonschema:"runtime ref of the schema the document was validated against"`
	MigratedFrom string `json:"migrated_from" jsonschema:"an empty string in the normal case. For a legacy shooter@0.x document: the ref that was asked for. Such a document is upgraded to the runtime named in the runtime field before it is validated, so violation paths refer to the upgraded document, not to the one passed in."`
	Validation
}

type applyDSLPatchInput struct {
	DSL     map[string]any `json:"dsl" jsonschema:"the complete base DSL document the patch is written against"`
	Patch   []PatchOp      `json:"patch" jsonschema:"RFC 6902 operations, applied in order"`
	Runtime string         `json:"runtime,omitempty" jsonschema:"runtime ref to validate the result against, for example shooter@1.0.0. Defaults to meta.runtime and meta.runtime_version of the patched document."`
}

type applyDSLPatchOutput struct {
	Runtime      string         `json:"runtime" jsonschema:"runtime ref of the schema the patched document was validated against"`
	MigratedFrom string         `json:"migrated_from" jsonschema:"an empty string in the normal case. For a legacy shooter@0.x document: the ref that was asked for. Such a document is upgraded to the runtime named in the runtime field before it is validated, so violation paths refer to the upgraded document, not to the dsl returned here."`
	DSL          map[string]any `json:"dsl" jsonschema:"the document after the patch; the input document is unchanged"`
	Validation
}

func (s *service) addOfflineTools(server *mcp.Server) {
	addTool(server, &mcp.Tool{
		Name:        "list_runtimes",
		Description: "List the game runtimes and versions this server has a DSL schema for. Start here: a runtime ref such as shooter@1.0.0 identifies which schema a DSL document must satisfy. Works offline.",
		Annotations: readOnly("List runtimes", false),
	}, nil, s.listRuntimes)

	addTool(server, &mcp.Tool{
		Name:        "get_dsl_schema",
		Description: "Return the JSON Schema of one runtime's Mod DSL. Read it before writing a patch: it lists every field with its allowed enum values and numeric ranges. Works offline. The same document is available as the resource forgeplay://schemas/<name>-<version>.",
		Annotations: readOnly("Get DSL schema", false),
	}, nil, s.getDSLSchema)

	addTool(server, &mcp.Tool{
		Name:        "validate_dsl",
		Description: "Check a complete DSL document against its runtime schema and list every violation with the JSON Pointer of the offending value. An invalid document is a normal result with valid=false, not an error. Works offline and stores nothing.",
		Annotations: readOnly("Validate DSL", false),
	}, nil, s.validateDSL)

	addTool(server, &mcp.Tool{
		Name:        "apply_dsl_patch",
		Description: "Apply an RFC 6902 JSON Patch to a DSL document and validate the result against the runtime schema. Returns the patched document and the validation outcome; a patch that does not apply is an error naming the failing operation. Use it to dry-run a patch before update_mod. Works offline and stores nothing.",
		Annotations: readOnly("Apply DSL patch", false),
	}, func(input *jsonschema.Schema) { patchInput(input, 0) }, s.applyDSLPatch)
}

func (s *service) listRuntimes(context.Context, *mcp.CallToolRequest, listRuntimesInput) (*mcp.CallToolResult, listRuntimesOutput, error) {
	runtimes := s.catalog.Runtimes()
	out := listRuntimesOutput{Runtimes: make([]runtimeInfo, len(runtimes))}
	for i, runtime := range runtimes {
		out.Runtimes[i] = runtimeInfo{
			Runtime:          runtime.Ref,
			Name:             runtime.Name,
			Version:          runtime.Version,
			Title:            runtime.Title,
			Sections:         nonNil(runtime.Sections),
			RequiredSections: nonNil(runtime.Required),
			SchemaURI:        schemaURI(runtime.Name, runtime.Version),
		}
	}
	return nil, out, nil
}

func (s *service) getDSLSchema(_ context.Context, _ *mcp.CallToolRequest, in getDSLSchemaInput) (*mcp.CallToolResult, getDSLSchemaOutput, error) {
	runtime, ok := s.catalog.Lookup(in.Runtime)
	if !ok {
		return nil, getDSLSchemaOutput{}, fmt.Errorf("no schema for runtime %q: use one of %s", in.Runtime, strings.Join(s.catalog.Refs(), ", "))
	}
	var schema map[string]any
	if err := json.Unmarshal(runtime.Schema, &schema); err != nil {
		return nil, getDSLSchemaOutput{}, fmt.Errorf("schema of %s is not a JSON object: %v", runtime.Ref, err)
	}
	return nil, getDSLSchemaOutput{Runtime: runtime.Ref, Schema: schema}, nil
}

func (s *service) validateDSL(_ context.Context, _ *mcp.CallToolRequest, in validateDSLInput) (*mcp.CallToolResult, validateDSLOutput, error) {
	result, err := s.check(in.Runtime, in.DSL)
	if err != nil {
		return nil, validateDSLOutput{}, err
	}
	return nil, validateDSLOutput{Runtime: result.runtime, MigratedFrom: result.migratedFrom, Validation: result.Validation}, nil
}

func (s *service) applyDSLPatch(_ context.Context, _ *mcp.CallToolRequest, in applyDSLPatchInput) (*mcp.CallToolResult, applyDSLPatchOutput, error) {
	patched, err := applyPatch(in.DSL, in.Patch)
	if err != nil {
		return nil, applyDSLPatchOutput{}, err
	}
	result, err := s.check(in.Runtime, patched)
	if err != nil {
		return nil, applyDSLPatchOutput{}, err
	}
	return nil, applyDSLPatchOutput{Runtime: result.runtime, MigratedFrom: result.migratedFrom, DSL: patched, Validation: result.Validation}, nil
}

// check validates document against the schema of the explicit runtime ref, or of the runtime named in the document when explicit is empty. The error is non-nil only when validation could not run. The result names the schema that was really used, which is not the requested ref for a legacy document that was migrated first.
func (s *service) check(explicit string, document map[string]any) (checked, error) {
	requested, err := runtimeOf(explicit, document)
	if err != nil {
		return checked{}, err
	}
	used, found, err := s.catalog.Validate(requested, document)
	if err != nil {
		return checked{}, err
	}
	result := checked{Validation: validation(found), runtime: used}
	if used != requested {
		result.migratedFrom = requested
	}
	return result, nil
}
