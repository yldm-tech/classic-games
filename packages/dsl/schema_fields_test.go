package dsl

import (
	"encoding/json"
	"slices"
	"strconv"
	"testing"
)

// freeFormFields lists every schema location outside the bookkeeping "meta" block that is neither an enum, a ranged number nor a boolean: strings without "enum" or "const", and arrays. The documentation (docs/05-dsl-design.md, CONTRIBUTING.md, the website landing page) names exactly these exceptions to "a DSL field is an enum, a ranged number or a boolean", and apps/web/src/data/runtimes.ts enforces the same list at build time. A schema change that adds or removes one has to update this list and those texts together.
var freeFormFields = map[string][]string{
	"shooter-1.0.0.schema.json":       {"/properties/stage/properties/bgm"},
	"survivor-1.0.0.schema.json":      {"/properties/progression/properties/upgrades"},
	"tower_defense-1.0.0.schema.json": {"/$defs/placement/properties/tower", "/$defs/point", "/properties/path/properties/points"},
}

// freeFormPointers collects the JSON pointers of all schema nodes whose type allows a string without an enum or const, or an array. The top-level "meta" property is skipped.
func freeFormPointers(node any, pointer string, found []string) []string {
	switch value := node.(type) {
	case []any:
		for index, item := range value {
			found = freeFormPointers(item, pointer+"/"+strconv.Itoa(index), found)
		}
	case map[string]any:
		types := []any{value["type"]}
		if list, ok := value["type"].([]any); ok {
			types = list
		}
		_, hasEnum := value["enum"]
		_, hasConst := value["const"]
		if (slices.Contains(types, any("string")) && !hasEnum && !hasConst) || slices.Contains(types, any("array")) {
			found = append(found, pointer)
		}
		for key, child := range value {
			if pointer == "/properties" && key == "meta" {
				continue
			}
			found = freeFormPointers(child, pointer+"/"+key, found)
		}
	}
	return found
}

func TestSchemas_FreeFormFieldsAreTheDocumentedExceptions(t *testing.T) {
	for file, want := range freeFormFields {
		var schema any
		if err := json.Unmarshal(repoFile(t, "packages", "schemas", file), &schema); err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		got := freeFormPointers(schema, "", nil)
		slices.Sort(got)
		if !slices.Equal(got, want) {
			t.Errorf("%s: free-form fields are %v, want %v. Update freeFormFields here, FREE_FORM_FIELDS in apps/web/src/data/runtimes.ts and the texts that list the exceptions", file, got, want)
		}
	}
}
