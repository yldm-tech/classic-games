package server_test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"unicode"
)

var runtimeNames = []string{"shooter", "survivor", "tower_defense"}

type runtimesOut struct {
	Runtimes []struct {
		Runtime          string   `json:"runtime"`
		Name             string   `json:"name"`
		Version          string   `json:"version"`
		Title            string   `json:"title"`
		Sections         []string `json:"sections"`
		RequiredSections []string `json:"required_sections"`
		SchemaURI        string   `json:"schema_uri"`
	} `json:"runtimes"`
}

func TestListRuntimes(t *testing.T) {
	out := call[runtimesOut](t, connect(t, session{}), "list_runtimes", map[string]any{})
	var refs []string
	for _, runtime := range out.Runtimes {
		refs = append(refs, runtime.Runtime)
		if runtime.Runtime != runtime.Name+"@"+runtime.Version {
			t.Errorf("runtime %q is not name@version of %q and %q", runtime.Runtime, runtime.Name, runtime.Version)
		}
		if runtime.SchemaURI != "classic-games://schemas/"+runtime.Name+"-"+runtime.Version {
			t.Errorf("%s: schema_uri = %q", runtime.Runtime, runtime.SchemaURI)
		}
		if runtime.Title == "" || !slices.Contains(runtime.Sections, "meta") || !slices.Contains(runtime.RequiredSections, "meta") {
			t.Errorf("%s: incomplete description: %+v", runtime.Runtime, runtime)
		}
	}
	if want := []string{"shooter@1.0.0", "survivor@1.0.0", "tower_defense@1.0.0"}; !slices.Equal(refs, want) {
		t.Fatalf("runtimes = %v, want %v", refs, want)
	}
	shooter := out.Runtimes[0]
	if want := []string{"boss", "drops", "enemies", "meta", "player", "stage"}; !slices.Equal(shooter.Sections, want) {
		t.Errorf("shooter sections = %v, want %v", shooter.Sections, want)
	}
	if want := []string{"meta", "player", "enemies", "stage"}; !slices.Equal(shooter.RequiredSections, want) {
		t.Errorf("shooter required sections = %v, want %v", shooter.RequiredSections, want)
	}
}

func TestGetDSLSchema(t *testing.T) {
	cs := connect(t, session{})
	out := call[struct {
		Runtime string         `json:"runtime"`
		Schema  map[string]any `json:"schema"`
	}](t, cs, "get_dsl_schema", map[string]any{"runtime": "survivor@1.0.0"})

	content, err := os.ReadFile(filepath.Join(schemaDir(t), "survivor-1.0.0.schema.json"))
	if err != nil {
		t.Fatal(err)
	}
	var want map[string]any
	if err := json.Unmarshal(content, &want); err != nil {
		t.Fatal(err)
	}
	if out.Runtime != "survivor@1.0.0" || !jsonEqual(out.Schema, want) {
		t.Errorf("get_dsl_schema did not return the survivor schema file: runtime=%q", out.Runtime)
	}

	message := callError(t, cs, "get_dsl_schema", map[string]any{"runtime": "racing@1.0.0"})
	mustContain(t, message, `no schema for runtime "racing@1.0.0"`, "shooter@1.0.0", "tower_defense@1.0.0")
}

func TestValidateDSLAcceptsEveryBaseline(t *testing.T) {
	cs := connect(t, session{})
	for _, name := range runtimeNames {
		out := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, name)})
		if !out.Valid || out.ViolationCount != 0 || len(out.Violations) != 0 || out.Runtime != name+"@1.0.0" {
			t.Errorf("%s baseline: %+v, want valid against %s@1.0.0", name, out, name)
		}
		if out.Violations == nil {
			t.Errorf("%s baseline: violations must be an empty list, not null", name)
		}
	}
}

func TestValidateDSLReportsViolations(t *testing.T) {
	cs := connect(t, session{})
	document := baseline(t, "shooter")
	player := document["player"].(map[string]any)
	player["hp"] = "lots"
	player["sprite"] = "dinosaur"
	delete(document, "stage")
	document["cheats"] = true

	out := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": document})
	if out.Valid || out.Runtime != "shooter@1.0.0" {
		t.Fatalf("result = %+v, want invalid against shooter@1.0.0", out)
	}
	if out.ViolationCount != len(out.Violations) || out.ViolationCount != 4 {
		t.Fatalf("violation_count = %d with %d listed, want 4: %+v", out.ViolationCount, len(out.Violations), out.Violations)
	}
	byPath := map[string][]string{}
	for _, found := range out.Violations {
		byPath[found.Path] = append(byPath[found.Path], found.Message)
	}
	for path, fragment := range map[string]string{"/player/hp": "integer", "/player/sprite": "plane"} {
		if len(byPath[path]) != 1 {
			t.Fatalf("violations at %s = %v, want exactly one", path, byPath[path])
		}
		mustContain(t, byPath[path][0], fragment)
	}
	// Both document-level problems are reported at the root, whose pointer is the empty string.
	if len(byPath[""]) != 2 {
		t.Fatalf("root violations = %v, want the missing stage and the unknown cheats key", byPath[""])
	}
	mustContain(t, byPath[""][0]+byPath[""][1], "stage", "cheats")
	if !slices.IsSortedFunc(out.Violations, func(a, b violation) int {
		if a.Path < b.Path {
			return -1
		}
		if a.Path > b.Path {
			return 1
		}
		return 0
	}) {
		t.Errorf("violations are not sorted by path: %+v", out.Violations)
	}
}

func TestValidateDSLRuntimeSelection(t *testing.T) {
	cs := connect(t, session{})

	// A shooter document checked against another runtime's schema is invalid, which proves the explicit runtime wins over meta.
	out := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, "shooter"), "runtime": "survivor@1.0.0"})
	if out.Valid || out.Runtime != "survivor@1.0.0" {
		t.Errorf("shooter baseline against survivor@1.0.0 = %+v, want invalid", out)
	}

	withoutMeta := baseline(t, "shooter")
	delete(withoutMeta, "meta")
	mustContain(t, callError(t, cs, "validate_dsl", map[string]any{"dsl": withoutMeta}), "meta.runtime", "pass the runtime argument")

	mustContain(t, callError(t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, "shooter"), "runtime": "shooter"}), "not a runtime ref", "shooter@1.0.0")

	mustContain(t, callError(t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, "shooter"), "runtime": "shooter@7.0.0"}), `no schema for runtime "shooter@7.0.0"`, "survivor@1.0.0")

	// A missing required argument is rejected by the input schema as a tool error the model can read.
	mustContain(t, callError(t, cs, "validate_dsl", map[string]any{"runtime": "shooter@1.0.0"}), "dsl")
}

func TestApplyDSLPatch(t *testing.T) {
	cs := connect(t, session{})
	base := baseline(t, "shooter")
	out := call[patchedOut](t, cs, "apply_dsl_patch", map[string]any{
		"dsl": base,
		"patch": []patchOp{
			{Op: "test", Path: "/player/sprite", Value: "plane"},
			{Op: "replace", Path: "/player/sprite", Value: "cat"},
			{Op: "replace", Path: "/enemies/dog_1/count", Value: 35},
			{Op: "add", Path: "/enemies/bird_1", Value: map[string]any{"type": "bird", "behavior": "sine", "count": 5, "hp": 10, "speed": 12}},
			{Op: "remove", Path: "/drops/shield_1"},
		},
	})
	if !out.Valid || out.Runtime != "shooter@1.0.0" {
		t.Fatalf("result = %+v, want a valid shooter@1.0.0 document", out.validationOut)
	}
	if at(t, out.DSL, "player", "sprite") != "cat" || at(t, out.DSL, "enemies", "dog_1", "count") != float64(35) || at(t, out.DSL, "enemies", "bird_1", "type") != "bird" {
		t.Errorf("patched document does not carry the changes: %v", out.DSL)
	}
	if _, kept := at(t, out.DSL, "drops").(map[string]any)["shield_1"]; kept {
		t.Error("remove did not delete /drops/shield_1")
	}
	// Everything the patch did not touch is unchanged.
	if !jsonEqual(at(t, out.DSL, "stage"), base["stage"]) || !jsonEqual(at(t, out.DSL, "boss"), base["boss"]) {
		t.Error("untouched sections changed")
	}
}

func TestApplyDSLPatchReportsSchemaViolations(t *testing.T) {
	cs := connect(t, session{})
	out := call[patchedOut](t, cs, "apply_dsl_patch", map[string]any{
		"dsl": baseline(t, "tower_defense"),
		"patch": []patchOp{
			{Op: "replace", Path: "/stage/background", Value: "jungle"},
		},
	})
	if out.Valid || out.ViolationCount != 1 || out.Violations[0].Path != "/stage/background" {
		t.Fatalf("result = %+v, want one violation at /stage/background", out.validationOut)
	}
	if at(t, out.DSL, "stage", "background") != "jungle" {
		t.Error("the patched document must be returned even when it is invalid")
	}
}

// Tool errors are read by a model: they are English throughout and name the full pointer, although github.com/yldm-tech/classic-games/packages/dsl words its errors in Chinese and with the tail of the pointer only.
func TestToolErrorsAreEnglishAndNameTheFullPath(t *testing.T) {
	cs := connect(t, session{})
	base := baseline(t, "shooter")
	messages := map[string]string{
		"failed test":     callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": base, "patch": []map[string]any{{"op": "test", "path": "/player/hp", "value": 1}}}),
		"missing target":  callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": base, "patch": []map[string]any{{"op": "remove", "path": "/enemies/nope"}}}),
		"replace missing": callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": base, "patch": []map[string]any{{"op": "replace", "path": "/enemies/nope", "value": 1}}}),
		"unknown runtime": callError(t, cs, "validate_dsl", map[string]any{"dsl": base, "runtime": "racing@1.0.0"}),
		"invalid ref":     callError(t, cs, "validate_dsl", map[string]any{"dsl": base, "runtime": "shooter@../../../etc/passwd"}),
	}
	for name, message := range messages {
		for _, r := range message {
			if unicode.Is(unicode.Han, r) {
				t.Errorf("%s: the message is not English throughout: %q", name, message)
				break
			}
		}
	}
	mustContain(t, messages["failed test"], `patch operation 1 (test "/player/hp") does not apply: the value at /player/hp is not the expected one`)
	mustContain(t, messages["missing target"], `patch operation 1 (remove "/enemies/nope") does not apply: /enemies/nope does not exist`)
	mustContain(t, messages["replace missing"], `does not apply: /enemies/nope does not exist`)
	mustContain(t, messages["unknown runtime"], `no schema for runtime "racing@1.0.0"`, "shooter@1.0.0, survivor@1.0.0, tower_defense@1.0.0")
	mustContain(t, messages["invalid ref"], `"shooter@../../../etc/passwd" is not a valid runtime ref`, "<name>@<version>")
}

// A legacy shooter@0.x ref has no schema of its own: the document is upgraded and checked against shooter@1.0.0, and the result has to say so instead of naming a schema that does not exist.
func TestLegacyShooterRefReportsTheSchemaUsed(t *testing.T) {
	cs := connect(t, session{})
	out := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, "shooter"), "runtime": "shooter@0.9.0"})
	if !out.Valid || out.Runtime != "shooter@1.0.0" || out.MigratedFrom != "shooter@0.9.0" {
		t.Errorf("validate_dsl with a legacy ref = %+v, want valid against shooter@1.0.0, migrated from shooter@0.9.0", out)
	}
	patched := call[patchedOut](t, cs, "apply_dsl_patch", map[string]any{"dsl": baseline(t, "shooter"), "runtime": "shooter@0.1.0", "patch": []patchOp{{Op: "replace", Path: "/player/hp", Value: 5000}}})
	if patched.Valid || patched.Runtime != "shooter@1.0.0" || patched.MigratedFrom != "shooter@0.1.0" {
		t.Errorf("apply_dsl_patch with a legacy ref = %+v, want invalid against shooter@1.0.0, migrated from shooter@0.1.0", patched.validationOut)
	}
	if current := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": baseline(t, "shooter")}); current.MigratedFrom != "" {
		t.Errorf("a current document reports migrated_from %q", current.MigratedFrom)
	}
	mustContain(t, callError(t, cs, "get_dsl_schema", map[string]any{"runtime": "shooter@0.9.0"}), `no schema for runtime "shooter@0.9.0"`)
}

// One violation can name every offending key, so the message is capped as well as the number of violations.
func TestViolationMessagesAreCapped(t *testing.T) {
	cs := connect(t, session{})
	document := baseline(t, "shooter")
	for i := range 3000 {
		document[fmt.Sprintf("unknown_key_%04d", i)] = i
	}
	result := callTool(t, cs, "validate_dsl", map[string]any{"dsl": document})
	out := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": document})
	if out.Valid || out.ViolationCount != 1 {
		t.Fatalf("result = valid %v with %d violations, want one violation", out.Valid, out.ViolationCount)
	}
	message := out.Violations[0].Message
	// The validator lists the keys in no fixed order; what matters is that the first ones are still named.
	mustContain(t, message, "additional properties 'unknown_key_", "more characters)")
	if len([]rune(message)) > 540 {
		t.Errorf("the violation message has %d characters, want about 500", len([]rune(message)))
	}
	if size := len(text(result)); size > 2000 {
		t.Errorf("the result text holds %d bytes, want a bounded result", size)
	}
	// The same text goes into the error of a rejected save.
	fb := newFakeBackend(t)
	writer := connect(t, session{backendURL: fb.server.URL, token: testToken})
	var patch []patchOp
	for i := range 900 {
		patch = append(patch, patchOp{Op: "add", Path: fmt.Sprintf("/unknown_key_%04d", i), Value: i})
	}
	if rejected := callError(t, writer, "create_mod", map[string]any{"runtime": "shooter@1.0.0", "patch": patch}); len(rejected) > 2000 || !strings.Contains(rejected, "nothing was saved") {
		t.Errorf("create_mod error holds %d bytes: %.200q", len(rejected), rejected)
	}
}

// A long patch is applied in one pass, and the input schema bounds its length.
func TestLongPatches(t *testing.T) {
	cs := connect(t, session{})
	var patch []patchOp
	for i := range 1000 {
		patch = append(patch, patchOp{Op: "replace", Path: "/player/hp", Value: 1 + i%500})
	}
	out := call[patchedOut](t, cs, "apply_dsl_patch", map[string]any{"dsl": baseline(t, "shooter"), "patch": patch})
	if !out.Valid || at(t, out.DSL, "player", "hp") != float64(500) {
		t.Errorf("1000 operations: valid %v, hp %v; want the value of the last operation", out.Valid, at(t, out.DSL, "player", "hp"))
	}
	// The failing operation is still named by its position when it is far into the patch.
	patch[700] = patchOp{Op: "remove", Path: "/enemies/nope"}
	mustContain(t, callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": baseline(t, "shooter"), "patch": patch}), `patch operation 701 (remove "/enemies/nope") does not apply`)

	patch = append(patch, patchOp{Op: "replace", Path: "/player/hp", Value: 1})
	mustContain(t, callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": baseline(t, "shooter"), "patch": patch}), "patch")
}

func TestApplyDSLPatchRejectsBadPatches(t *testing.T) {
	cs := connect(t, session{})
	cases := map[string]struct {
		patch     []map[string]any
		fragments []string
	}{
		"missing target": {
			[]map[string]any{{"op": "replace", "path": "/player/hp", "value": 150}, {"op": "replace", "path": "/player/nope", "value": 1}},
			[]string{`patch operation 2 (replace "/player/nope") does not apply`, "need an existing target"},
		},
		"failed test": {
			[]map[string]any{{"op": "test", "path": "/player/sprite", "value": "ufo"}},
			[]string{`patch operation 1 (test "/player/sprite") does not apply`},
		},
		// A well-formed RFC 6902 move or copy carries "from"; it has to get past the input schema to receive the explanation.
		"move": {
			[]map[string]any{{"op": "move", "path": "/player/hp", "from": "/boss/hp"}},
			[]string{`patch operation 1 (move "/player/hp") is not supported`, "remove and an add"},
		},
		"copy": {
			[]map[string]any{{"op": "replace", "path": "/player/hp", "value": 1}, {"op": "copy", "path": "/player/hp", "from": "/boss/hp"}},
			[]string{`patch operation 2 (copy "/player/hp") is not supported`, "an add with the value to copy"},
		},
		"copy without from": {
			[]map[string]any{{"op": "copy", "path": "/player/hp"}},
			[]string{`patch operation 1 (copy "/player/hp") is not supported`},
		},
		// Operations are judged in order: the second one fails on the document before the malformed third one is reached.
		"failure before a malformed operation": {
			[]map[string]any{{"op": "replace", "path": "/player/hp", "value": 150}, {"op": "remove", "path": "/enemies/nope"}, {"op": "move", "path": "/a", "from": "/b"}},
			[]string{`patch operation 2 (remove "/enemies/nope") does not apply: /enemies/nope does not exist`},
		},
		"malformed operation before a failure": {
			[]map[string]any{{"op": "replace", "path": "/player/hp", "value": 150}, {"op": "merge", "path": "/a"}, {"op": "remove", "path": "/enemies/nope"}},
			[]string{`patch operation 2 (merge "/a") has an unknown op`},
		},
		"missing parent": {
			[]map[string]any{{"op": "add", "path": "/nowhere/deep/key", "value": 1}},
			[]string{`patch operation 1 (add "/nowhere/deep/key") does not apply: the parent of /nowhere/deep/key does not exist`},
		},
		"unknown op": {
			[]map[string]any{{"op": "merge", "path": "/player", "value": map[string]any{}}},
			[]string{"unknown op", "add, replace, remove or test"},
		},
		"missing value": {
			[]map[string]any{{"op": "add", "path": "/player/size"}},
			[]string{`patch operation 1 (add "/player/size") has no value`},
		},
		"root path": {
			[]map[string]any{{"op": "replace", "path": "", "value": map[string]any{}}},
			[]string{"invalid path", "document root cannot be patched"},
		},
		"relative path": {
			[]map[string]any{{"op": "replace", "path": "player/hp", "value": 1}},
			[]string{"invalid path", `starting with "/"`},
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			mustContain(t, callError(t, cs, "apply_dsl_patch", map[string]any{"dsl": baseline(t, "shooter"), "patch": tc.patch}), tc.fragments...)
		})
	}

	// JSON null is a legal value and must not be mistaken for a missing one.
	out := call[patchedOut](t, cs, "apply_dsl_patch", map[string]any{
		"dsl":   baseline(t, "shooter"),
		"patch": []map[string]any{{"op": "test", "path": "/meta/fork_of", "value": nil}, {"op": "replace", "path": "/meta/fork_of", "value": "m_1"}},
	})
	if !out.Valid || at(t, out.DSL, "meta", "fork_of") != "m_1" {
		t.Errorf("null test followed by replace = %+v", out.validationOut)
	}
}
