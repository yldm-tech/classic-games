package server

import (
	"encoding/json"
	"fmt"
	"reflect"
	"slices"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// typeSchemas overrides schema inference for types whose Go kind does not match their JSON shape: json.RawMessage is a byte slice in Go but carries an arbitrary JSON value.
var typeSchemas = map[reflect.Type]*jsonschema.Schema{
	reflect.TypeFor[json.RawMessage](): {},
}

// schemaFor infers the JSON Schema of T from its json and jsonschema struct tags and then applies adjust to the root schema. Inference marks slices and pointers as nullable (type ["null", "array"]); the null alternative is removed so tool schemas show one plain type per field, which every MCP client understands. Handlers therefore never return a nil slice in an output. It panics on a type that has no schema, which is a programming error caught by any test that builds the server.
func schemaFor[T any](adjust func(root *jsonschema.Schema)) *jsonschema.Schema {
	schema, err := jsonschema.For[T](&jsonschema.ForOptions{TypeSchemas: typeSchemas})
	if err != nil {
		panic(fmt.Sprintf("infer schema: %v", err))
	}
	dropNull(schema)
	if adjust != nil {
		adjust(schema)
	}
	return schema
}

// dropNull rewrites a ["null", T] type union to T, recursively.
func dropNull(schema *jsonschema.Schema) {
	if schema == nil {
		return
	}
	if len(schema.Types) == 2 && slices.Contains(schema.Types, "null") {
		for _, name := range schema.Types {
			if name != "null" {
				schema.Type = name
			}
		}
		schema.Types = nil
	}
	for _, property := range schema.Properties {
		dropNull(property)
	}
	dropNull(schema.Items)
	dropNull(schema.AdditionalProperties)
}

// addTool registers a typed tool whose input and output schemas are inferred with schemaFor. adjustInput may refine the input schema with enums, bounds and defaults.
func addTool[In, Out any](server *mcp.Server, tool *mcp.Tool, adjustInput func(input *jsonschema.Schema), handler mcp.ToolHandlerFor[In, Out]) {
	tool.InputSchema = schemaFor[In](adjustInput)
	tool.OutputSchema = schemaFor[Out](nil)
	mcp.AddTool(server, tool, handler)
}

// Annotation presets. Every hint is set explicitly because some clients treat an absent hint as its pessimistic default.
func boolPtr(value bool) *bool { return &value }

// readOnly describes a tool that changes nothing. openWorld is true for tools that reach the ForgePlay backend, whose content is written by other users.
func readOnly(title string, openWorld bool) *mcp.ToolAnnotations {
	return &mcp.ToolAnnotations{Title: title, ReadOnlyHint: true, IdempotentHint: true, DestructiveHint: boolPtr(false), OpenWorldHint: boolPtr(openWorld)}
}

// additive describes a backend tool that creates something new on every call and never overwrites or removes existing data.
func additive(title string) *mcp.ToolAnnotations {
	return &mcp.ToolAnnotations{Title: title, ReadOnlyHint: false, IdempotentHint: false, DestructiveHint: boolPtr(false), OpenWorldHint: boolPtr(true)}
}

// maxPatchOps bounds the patch array of one call. A DSL has a few dozen fields, so a real patch has a handful of operations; the bound keeps one request from occupying the server with a patch of arbitrary length.
const maxPatchOps = 1000

// requireID makes an id property reject the empty string, so a blank id is refused by input validation instead of reaching the backend client.
func requireID(schema *jsonschema.Schema, property string) {
	schema.Properties[property].MinLength = jsonschema.Ptr(1)
}

// patchInput refines the "patch" property of a tool input: at least minOps and at most maxPatchOps operations, and an optional "from" member on each operation. RFC 6902 requires "from" on move and copy; neither is supported, but the member has to be accepted for such an operation to reach the handler, which explains how to express it with remove and add. Without it the closed item schema would reject the operation with a generic message about an unexpected property.
func patchInput(schema *jsonschema.Schema, minOps int) {
	patch := schema.Properties["patch"]
	if minOps > 0 {
		patch.MinItems = jsonschema.Ptr(minOps)
	}
	patch.MaxItems = jsonschema.Ptr(maxPatchOps)
	patch.Items.Properties["from"] = &jsonschema.Schema{Type: "string", Description: "only used by move and copy, which are not supported: express a move as a remove and an add, and a copy as an add"}
}

// enum sets the allowed values of a string property.
func enum(schema *jsonschema.Schema, property string, values ...string) {
	allowed := make([]any, len(values))
	for i, value := range values {
		allowed[i] = value
	}
	schema.Properties[property].Enum = allowed
}

// intRange bounds an integer property and records its default.
func intRange(schema *jsonschema.Schema, property string, minimum, maximum, defaultValue int) {
	target := schema.Properties[property]
	target.Minimum = jsonschema.Ptr(float64(minimum))
	target.Maximum = jsonschema.Ptr(float64(maximum))
	target.Default = json.RawMessage(fmt.Sprint(defaultValue))
}
