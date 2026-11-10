package dsl

import "testing"

func TestMigrateShooterV0ToV1(t *testing.T) {
	in := map[string]any{"meta": map[string]any{}, "player": map[string]any{"weapon": "spread"}, "enemies": []any{map[string]any{"id": "dog_old", "type": "dog"}}, "drops": []any{map[string]any{"type": "heal"}}}
	ref, out, err := Migrate("shooter@0.9.0", "1.0.0", in)
	if err != nil {
		t.Fatal(err)
	}
	if ref != "shooter@1.0.0" || out["player"].(map[string]any)["weapon"].(map[string]any)["type"] != "spread" {
		t.Fatalf("out=%v", out)
	}
	if _, ok := out["enemies"].(map[string]any)["dog_old"]; !ok {
		t.Fatalf("stable id missing: %v", out)
	}
	if _, ok := in["enemies"].([]any); !ok {
		t.Fatal("input mutated")
	}
}

// The target version is written into meta.runtime_version, so only a plain <major>.<minor>.<patch> version with major 1 is a migration path.
func TestMigrateRejectsTargetsThatAreNotPlainVersions(t *testing.T) {
	in := map[string]any{"meta": map[string]any{}, "player": map[string]any{"weapon": "spread"}}
	for _, target := range []string{"", "1", "1.0", "1.x; rm -rf", "01.0.0", "1.0.0.0", "1.0.0-rc.1", " 1.0.0", "1..0", "+1.0.0", "2.0.0", "0.9.0"} {
		ref, out, err := Migrate("shooter@0.9.0", target, in)
		if err == nil {
			t.Errorf("target %q: got ref %q and a document, want an error", target, ref)
			continue
		}
		if out != nil {
			t.Errorf("target %q: got a document next to the error %v", target, err)
		}
	}
	for _, target := range []string{"1.0.0", "1.5.0", "1.10.12"} {
		ref, out, err := Migrate("shooter@0.9.0", target, in)
		if err != nil {
			t.Errorf("target %q: %v", target, err)
			continue
		}
		if ref != "shooter@"+target || out["meta"].(map[string]any)["runtime_version"] != target {
			t.Errorf("target %q: got ref %q meta %v", target, ref, out["meta"])
		}
	}
}
