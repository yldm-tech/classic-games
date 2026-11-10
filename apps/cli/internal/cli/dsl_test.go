package cli

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

var runtimeNames = []string{"shooter", "survivor", "tower_defense"}

// forkChain is the patch the client and the server both assert against apps/client/runtime/shooter/testdata/fork_expected.dsl.json.
const forkChain = `[
	{"op":"replace","path":"/player/sprite","value":"cat"},
	{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}},
	{"op":"replace","path":"/enemies/dog_1/count","value":30},
	{"op":"remove","path":"/enemies/turret_1"}
]`

func baselinePath(t *testing.T, runtime string) string {
	t.Helper()
	return repoPath(t, "apps", "client", "runtime", runtime, "baseline.dsl.json")
}

// canonical re-encodes JSON with sorted keys so two documents can be compared as text.
func canonical(t *testing.T, data []byte) string {
	t.Helper()
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		t.Fatalf("not JSON: %v\n%s", err, data)
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(encoded)
}

// brokenShooter is the shooter baseline with a wrong type, a value below its minimum and an unknown top-level key.
func brokenShooter(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(baselinePath(t, "shooter"))
	if err != nil {
		t.Fatal(err)
	}
	document := decode[map[string]any](t, string(data))
	player := document["player"].(map[string]any)
	player["hp"] = "lots"
	player["speed"] = -5
	document["cheats"] = true
	encoded, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	return writeFile(t, "broken.dsl.json", string(encoded))
}

func TestDSLValidateAcceptsEveryRuntimeBaseline(t *testing.T) {
	h := newHarness(t)
	schemas := repoPath(t, "packages", "schemas")
	var files []string
	for _, runtime := range runtimeNames {
		files = append(files, baselinePath(t, runtime))
	}

	// Inside the repository the schema directory is found without any configuration.
	detected := h.ok(append([]string{"dsl", "validate"}, files...)...)
	for i, runtime := range runtimeNames {
		mustContain(t, detected, files[i]+": valid ("+runtime+"@1.0.0)")
	}

	report := decode[validationReport](t, h.ok(append([]string{"dsl", "validate", "--schema-dir", schemas, "--output", "json"}, files...)...))
	if !report.Valid || report.SchemaDir != schemas || len(report.Results) != 3 {
		t.Fatalf("report = %+v", report)
	}
	for i, result := range report.Results {
		if !result.Valid || result.File != files[i] || result.Runtime != runtimeNames[i]+"@1.0.0" || result.Errors == nil || len(result.Errors) != 0 {
			t.Fatalf("result %d = %+v, want a valid entry with an empty errors array", i, result)
		}
	}
}

func TestDSLValidateRejectsAnInvalidDocument(t *testing.T) {
	h := newHarness(t)
	broken := brokenShooter(t)

	got := h.fails("dsl", "validate", baselinePath(t, "shooter"), broken)
	mustContain(t, got.stdout,
		baselinePath(t, "shooter")+": valid (shooter@1.0.0)",
		broken+": invalid (shooter@1.0.0)",
		"  (document): additional properties 'cheats' not allowed",
		"  /player/hp: got string, want integer",
		"  /player/speed: ",
	)
	if got.stderr != "Error: 1 of 2 file(s) failed validation\n" {
		t.Fatalf("stderr = %q", got.stderr)
	}

	asJSON := h.fails("dsl", "validate", broken, "--output", "json")
	report := decode[validationReport](t, asJSON.stdout)
	if report.Valid || len(report.Results) != 1 || report.Results[0].Valid {
		t.Fatalf("report = %+v", report)
	}
	issues := map[string]string{}
	for _, issue := range report.Results[0].Errors {
		issues[issue.Path] = issue.Message
	}
	if issues[""] != "additional properties 'cheats' not allowed" || issues["/player/hp"] != "got string, want integer" || issues["/player/speed"] == "" || len(issues) != 3 {
		t.Fatalf("issues = %v", issues)
	}
}

func TestDSLValidateReportsUnreadableAndUnidentifiedFiles(t *testing.T) {
	h := newHarness(t)
	missing := filepath.Join(t.TempDir(), "missing.json")
	notJSON := writeFile(t, "notes.json", "player: cat")
	array := writeFile(t, "array.json", "[1, 2, 3]")
	noMeta := writeFile(t, "nometa.json", `{"player": {"hp": 1}}`)
	unknown := writeFile(t, "unknown.json", `{"meta": {"runtime": "racing", "runtime_version": "9.9.9"}}`)

	got := h.fails("dsl", "validate", missing, notJSON, array, noMeta, unknown, baselinePath(t, "survivor"))
	mustContain(t, got.stdout,
		missing+": invalid (unknown runtime)",
		"no such file or directory",
		notJSON+": invalid (unknown runtime)",
		"not a JSON object",
		array+": invalid (unknown runtime)",
		noMeta+": invalid (unknown runtime)",
		"/meta: meta.runtime and meta.runtime_version are missing",
		unknown+": invalid (racing@9.9.9)",
		"racing@9.9.9",
		baselinePath(t, "survivor")+": valid (survivor@1.0.0)",
	)
	mustContain(t, got.stderr, "5 of 6 file(s) failed validation")

	// --runtime supplies what the file does not declare, and overrides what it does.
	mustContain(t, h.fails("dsl", "validate", "--runtime", "shooter@1.0.0", noMeta).stdout, noMeta+": invalid (shooter@1.0.0)", "missing propert")
	mustContain(t, h.fails("dsl", "validate", "--runtime", "survivor@1.0.0", baselinePath(t, "shooter")).stdout, "invalid (survivor@1.0.0)")
	mustContain(t, h.fails("dsl", "validate", "--runtime", "shooter", noMeta).stderr, `invalid --runtime "shooter"`)
}

func TestDSLValidateReadsStandardInput(t *testing.T) {
	h := newHarness(t)
	data, err := os.ReadFile(baselinePath(t, "tower_defense"))
	if err != nil {
		t.Fatal(err)
	}
	got := h.runWith(context.Background(), string(data), "dsl", "validate", "-")
	if got.code != 0 {
		t.Fatalf("validating standard input failed: %s%s", got.stdout, got.stderr)
	}
	mustContain(t, got.stdout, "standard input: valid (tower_defense@1.0.0)")
}

func TestSchemaDirectoryResolution(t *testing.T) {
	schemas := repoPath(t, "packages", "schemas")
	baseline := baselinePath(t, "shooter")
	empty := t.TempDir()
	// Outside a repository checkout nothing can be detected.
	t.Chdir(t.TempDir())

	h := newHarness(t)
	mustContain(t, h.fails("dsl", "validate", baseline).stderr, "no schema directory", "--schema-dir", EnvSchemaDir)
	mustContain(t, h.fails("dsl", "validate", baseline, "--schema-dir", empty).stderr, "holds no *.schema.json files", "(from flag)")

	h.ok("dsl", "validate", baseline, "--schema-dir", schemas)

	h.ok("config", "set", "schema-dir", schemas)
	h.ok("dsl", "validate", baseline)

	h.env[EnvSchemaDir] = empty
	mustContain(t, h.fails("dsl", "validate", baseline).stderr, "(from env)")
	h.ok("dsl", "validate", baseline, "--schema-dir", schemas)

	delete(h.env, EnvSchemaDir)
	h.ok("config", "unset", "schema-dir")
	h.env[EnvSchemaDir] = schemas
	report := decode[validationReport](t, h.ok("dsl", "validate", baseline, "--output", "json"))
	if report.SchemaDir != schemas {
		t.Fatalf("schema dir = %q, want the one from %s", report.SchemaDir, EnvSchemaDir)
	}
}

func TestDSLPatchMatchesTheSharedGoldenFile(t *testing.T) {
	h := newHarness(t)
	baseline := baselinePath(t, "shooter")
	before, err := os.ReadFile(baseline)
	if err != nil {
		t.Fatal(err)
	}
	golden, err := os.ReadFile(repoPath(t, "apps", "client", "runtime", "shooter", "testdata", "fork_expected.dsl.json"))
	if err != nil {
		t.Fatal(err)
	}
	patch := writeFile(t, "fork.patch.json", forkChain)

	printed := h.ok("dsl", "patch", baseline, patch)
	if canonical(t, []byte(printed)) != canonical(t, golden) {
		t.Fatalf("patched DSL differs from the golden file shared with the client and the server:\n%s", printed)
	}
	if !strings.HasSuffix(printed, "}\n") || !strings.Contains(printed, "\n  \"") {
		t.Fatalf("the document is not indented JSON with a trailing newline:\n%s", printed)
	}

	out := filepath.Join(t.TempDir(), "forked.dsl.json")
	mustContain(t, h.ok("dsl", "patch", baseline, patch, "-o", out, "--validate"), "Wrote "+out)
	written, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != printed {
		t.Fatal("-o wrote a different document than the one printed to standard output")
	}
	if report := decode[map[string]string](t, h.ok("dsl", "patch", baseline, patch, "--out", out, "--output", "json")); report["out"] != out {
		t.Fatalf("json report = %v", report)
	}

	fromStdin := h.runWith(context.Background(), forkChain, "dsl", "patch", baseline, "-")
	if fromStdin.code != 0 || fromStdin.stdout != printed {
		t.Fatalf("reading the patch from standard input: exit %d, stderr %s", fromStdin.code, fromStdin.stderr)
	}

	after, err := os.ReadFile(baseline)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatal("dsl patch modified the base file")
	}
	h.ok("dsl", "validate", out)
}

func TestDSLPatchFailures(t *testing.T) {
	h := newHarness(t)
	baseline := baselinePath(t, "shooter")
	out := filepath.Join(t.TempDir(), "out.dsl.json")

	cases := []struct {
		name  string
		patch string
		args  []string
		want  []string
	}{
		{"unsupported operation", `[{"op":"move","from":"/player/hp","path":"/player/max_hp"}]`, nil, []string{`operation 0 uses unsupported op "move"`, "supported: add, replace, remove, test"}},
		{"unsupported operation after a valid one", `[{"op":"remove","path":"/boss"},{"op":"copy","from":"/player/hp","path":"/player/max_hp"}]`, nil, []string{`operation 1 uses unsupported op "copy"`}},
		{"missing target", `[{"op":"replace","path":"/player/nope","value":1}]`, nil, []string{"the patch does not apply", `operation 0 (replace "/player/nope")`}},
		{"failed test operation", `[{"op":"test","path":"/player/sprite","value":"dragon"},{"op":"remove","path":"/boss"}]`, nil, []string{"the patch does not apply", `operation 0 (test "/player/sprite")`}},
		{"root path", `[{"op":"replace","path":"/player/hp","value":1},{"op":"remove","path":""}]`, nil, []string{"the patch does not apply", `operation 1 (remove "")`}},
		{"not an array", `{"op":"remove","path":"/boss"}`, nil, []string{"not a JSON Patch array"}},
		{"null patch", `null`, nil, []string{"must be a JSON array of operations"}},
		{"operation without op", `[{"path":"/boss"}]`, nil, []string{`operation 0 has no "op"`}},
		{"schema violation", `[{"op":"replace","path":"/player/hp","value":"lots"}]`, []string{"--validate"}, []string{"the patched DSL is not valid for shooter@1.0.0; nothing was written", "  /player/hp: got string, want integer"}},
		{"runtime without validate", `[]`, []string{"--runtime", "shooter@1.0.0"}, []string{"--runtime only applies together with --validate"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			args := append([]string{"dsl", "patch", baseline, writeFile(t, "patch.json", c.patch), "-o", out}, c.args...)
			got := h.fails(args...)
			mustContain(t, got.stderr, c.want...)
			if got.stdout != "" {
				t.Fatalf("stdout = %q, want nothing on failure", got.stdout)
			}
			if _, err := os.Stat(out); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("a failed patch still wrote %s (stat error: %v)", out, err)
			}
		})
	}

	mustContain(t, h.fails("dsl", "patch", "-", "-").stderr, "only one of the base and the patch")
	mustContain(t, h.fails("dsl", "patch", baseline).stderr, "accepts 2 arg(s), received 1")
}

func TestDSLMigrateUpgradesALegacyShooterDocument(t *testing.T) {
	h := newHarness(t)
	data, err := os.ReadFile(baselinePath(t, "shooter"))
	if err != nil {
		t.Fatal(err)
	}
	// Build a 0.x document from the current baseline: no meta, a string weapon, no player size, and array-form enemies and drops.
	legacy := decode[map[string]any](t, string(data))
	delete(legacy, "meta")
	player := legacy["player"].(map[string]any)
	player["weapon"] = "spread"
	delete(player, "size")
	for _, section := range []string{"enemies", "drops"} {
		var items []any
		for id, raw := range legacy[section].(map[string]any) {
			item := raw.(map[string]any)
			item["id"] = id
			items = append(items, item)
		}
		legacy[section] = items
	}
	encoded, err := json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	legacyFile := writeFile(t, "legacy.dsl.json", string(encoded))

	mustContain(t, h.fails("dsl", "migrate", legacyFile, "--to", "1.0.0").stderr, "declares no meta.runtime", "--from")
	mustContain(t, h.fails("dsl", "migrate", legacyFile, "--from", "shooter@0.9.0").stderr, `required flag(s) "to" not set`)

	out := filepath.Join(t.TempDir(), "migrated.dsl.json")
	got := h.run("dsl", "migrate", legacyFile, "--from", "shooter@0.9.0", "--to", "1.0.0", "-o", out)
	if got.code != 0 {
		t.Fatalf("migrate failed: %s", got.stderr)
	}
	mustContain(t, got.stderr, "Migrated "+legacyFile+" from shooter@0.9.0 to shooter@1.0.0")
	mustContain(t, got.stdout, "Wrote "+out)

	written, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	migrated := decode[map[string]any](t, string(written))
	meta := migrated["meta"].(map[string]any)
	if meta["runtime"] != "shooter" || meta["runtime_version"] != "1.0.0" {
		t.Fatalf("meta = %v", meta)
	}
	if weapon, ok := migrated["player"].(map[string]any)["weapon"].(map[string]any); !ok || weapon["type"] != "spread" {
		t.Fatalf("weapon = %v, want an object of type spread", migrated["player"].(map[string]any)["weapon"])
	}
	if _, ok := migrated["enemies"].(map[string]any)["dog_1"]; !ok {
		t.Fatalf("enemies = %v, want a map keyed by the original ids", migrated["enemies"])
	}
	// The migrated document passes the 1.0.0 schema, and the legacy one is still untouched on disk.
	h.ok("dsl", "validate", out)
	if untouched, _ := os.ReadFile(legacyFile); string(untouched) != string(encoded) {
		t.Fatal("dsl migrate modified its input file")
	}

	printed := h.run("dsl", "migrate", legacyFile, "--from", "shooter@0.9.0", "--to", "1.0.0")
	if printed.code != 0 || printed.stdout != string(written) {
		t.Fatalf("printing to standard output: exit %d, differs from -o: %v", printed.code, printed.stdout != string(written))
	}
}

// --to ends up in meta.runtime_version, so a value that is not a plain version must not produce a document.
func TestDSLMigrateRejectsTargetsThatAreNotVersions(t *testing.T) {
	h := newHarness(t)
	legacy := writeFile(t, "legacy.dsl.json", `{"meta":{},"player":{"weapon":"spread"}}`)
	for _, target := range []string{"1", "1.0", "1.x; rm -rf", "01.0.0", " 1.0.0"} {
		out := filepath.Join(t.TempDir(), "migrated.dsl.json")
		got := h.fails("dsl", "migrate", legacy, "--from", "shooter@0.9.0", "--to", target, "-o", out)
		mustContain(t, got.stderr, "cannot migrate", "from shooter@0.9.0 to version "+target)
		mustNotContain(t, got.stderr, "Migrated")
		if got.stdout != "" {
			t.Fatalf("--to %q printed %q, want nothing", target, got.stdout)
		}
		if _, err := os.Stat(out); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("--to %q still wrote %s (stat error: %v)", target, out, err)
		}
	}
}

// signalReader tells the test when the command has started to read standard input.
type signalReader struct {
	io.Reader
	started chan struct{}
	once    sync.Once
}

func (r *signalReader) Read(buffer []byte) (int, error) {
	r.once.Do(func() { close(r.started) })
	return r.Reader.Read(buffer)
}

// A command that waits for a document on standard input must end on the first interrupt, like a command that waits for the network.
func TestInterruptEndsACommandThatWaitsForStandardInput(t *testing.T) {
	baseline := baselinePath(t, "shooter")
	for name, args := range map[string][]string{
		"dsl validate": {"dsl", "validate", "--schema-dir", repoPath(t, "packages", "schemas"), "-"},
		"dsl patch":    {"dsl", "patch", baseline, "-"},
		"dsl migrate":  {"dsl", "migrate", "-", "--to", "1.0.0"},
		"mods save":    {"mods", "save", "draft-1", "--patch", "-"},
		"ai generate":  {"ai", "generate", "cats", "--dsl", "-"},
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			// Standard input that never ends: the read end of a pipe nobody writes to.
			pipe, writer := io.Pipe()
			defer writer.Close()
			stdin := &signalReader{Reader: pipe, started: make(chan struct{})}

			ctx, cancel := context.WithCancelCause(context.Background())
			defer cancel(nil)
			done := make(chan result, 1)
			go func() { done <- h.runReader(ctx, stdin, args...) }()
			select {
			case <-stdin.started:
			case <-time.After(10 * time.Second):
				t.Fatal("the command never read standard input")
			}
			cancel(errors.New("interrupt signal received"))
			select {
			case got := <-done:
				if got.code != ExitInterrupted || got.stderr != "Error: interrupted\n" {
					t.Fatalf("exit %d, stderr %q; want %d and \"Error: interrupted\"", got.code, got.stderr, ExitInterrupted)
				}
				if got.stdout != "" {
					t.Fatalf("stdout = %q, want nothing after an interrupt", got.stdout)
				}
			case <-time.After(10 * time.Second):
				t.Fatal("the command kept waiting for standard input after the interrupt")
			}
		})
	}
}

func TestDSLMigrateRejectsPathsThatDoNotExist(t *testing.T) {
	h := newHarness(t)
	// A current document declares its runtime, so --from is not needed; there is no 1.0.0 to 2.0.0 path.
	mustContain(t, h.fails("dsl", "migrate", baselinePath(t, "shooter"), "--to", "2.0.0").stderr, "cannot migrate", "from shooter@1.0.0 to version 2.0.0")
	mustContain(t, h.fails("dsl", "migrate", baselinePath(t, "survivor"), "--from", "survivor@0.5.0", "--to", "1.0.0").stderr, "cannot migrate", "survivor@0.5.0")
	mustContain(t, h.fails("dsl", "migrate", baselinePath(t, "shooter"), "--from", "shooter", "--to", "1.0.0").stderr, `invalid source runtime "shooter"`)
}

func TestHelpIsAvailableForEveryGroup(t *testing.T) {
	h := newHarness(t)
	groups := map[string][]string{
		"config": {"get", "set", "unset", "path"},
		"auth":   {"login", "logout", "status", "refresh", "set-password", "token"},
		"server": {"health", "info"},
		"games":  {"list", "show", "dsl", "ranking", "fork", "mine", "delist", "resubmit"},
		"mods":   {"list", "create", "fork", "save", "show", "dsl", "lineage", "publish"},
		"ai":     {"generate", "quota"},
		"dsl":    {"validate", "patch", "migrate"},
	}
	root := h.ok("--help")
	for name, subcommands := range groups {
		mustContain(t, root, "\n  "+name+" ")
		help := h.ok(name, "--help")
		mustContain(t, help, "Usage:", "classic-games "+name+" [command]", "--output string", "--server string")
		for _, subcommand := range subcommands {
			mustContain(t, help, "\n  "+subcommand+" ")
			mustContain(t, h.ok(name, subcommand, "--help"), "Usage:\n  classic-games "+name+" "+subcommand)
		}
		// A bare group prints the same help and succeeds.
		if bare := h.ok(name); bare != help {
			t.Fatalf("'classic-games %s' and 'classic-games %s --help' differ", name, name)
		}
	}
	mustContain(t, root, "\n  version ")
}
