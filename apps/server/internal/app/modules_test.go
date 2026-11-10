package app

import (
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"

	"forgeplay/server/internal/ai"
	"forgeplay/server/internal/auth"
	"forgeplay/server/internal/storage"

	"github.com/gin-gonic/gin"
)

type installerStub struct {
	name string
	deps []string
	err  error
}

func (s installerStub) Name() string                 { return s.name }
func (s installerStub) Dependencies() []string       { return append([]string(nil), s.deps...) }
func (s installerStub) Install(*moduleContext) error { return s.err }

func TestDefaultModuleInstallersHaveStableAcyclicOrder(t *testing.T) {
	installers := defaultModuleInstallers()
	want := []string{"identity", "creation", "catalog", "commerce", "community", "engagement", "operations"}
	if len(installers) != len(want) {
		t.Fatalf("installer count = %d, want %d", len(installers), len(want))
	}
	installed := map[string]bool{}
	for i, installer := range installers {
		if got := installer.Name(); got != want[i] {
			t.Fatalf("installer[%d] = %q, want %q", i, got, want[i])
		}
		if installed[installer.Name()] {
			t.Fatalf("duplicate installer %q", installer.Name())
		}
		for _, dependency := range installer.Dependencies() {
			if !installed[dependency] {
				t.Fatalf("module %q depends on %q before it is installed", installer.Name(), dependency)
			}
		}
		installed[installer.Name()] = true
	}
}

func TestInstallModulesWrapsFailureWithModuleName(t *testing.T) {
	sentinel := errors.New("boom")
	err := installModules(&moduleContext{}, []moduleInstaller{
		installerStub{name: "identity"},
		installerStub{name: "catalog", deps: []string{"identity"}, err: sentinel},
	})
	if !errors.Is(err, sentinel) || !strings.Contains(err.Error(), "module catalog") {
		t.Fatalf("installModules error = %v", err)
	}
}

func TestModuleRouteOwnershipIsUniqueAndRegistered(t *testing.T) {
	cfg := applicationTestConfig(t)
	db, err := storage.Open(cfg.Database.DSN)
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := Migrate(db, DefaultMigrations()); err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(cfg.HTTP)
	if err != nil {
		t.Fatal(err)
	}
	ctx := &moduleContext{cfg: cfg, db: db, provider: ai.StubProvider{}, codeSender: auth.NewLogSender(), engine: engine}
	seen := map[string]string{}
	for _, installer := range defaultModuleInstallers() {
		before := routeSet(engine.Routes())
		if err := installer.Install(ctx); err != nil {
			t.Fatalf("install %s: %v", installer.Name(), err)
		}
		added := routeDelta(before, routeSet(engine.Routes()))
		want := append([]string(nil), moduleRouteOwners()[installer.Name()]...)
		sort.Strings(want)
		if strings.Join(added, "\n") != strings.Join(want, "\n") {
			t.Errorf("%s route ownership mismatch\n got: %q\nwant: %q", installer.Name(), added, want)
		}
		for _, route := range added {
			if previous := seen[route]; previous != "" {
				t.Fatalf("route %s owned by both %s and %s", route, previous, installer.Name())
			}
			seen[route] = installer.Name()
		}
	}
}

func TestModuleResultsExposeOnlyNarrowPorts(t *testing.T) {
	directory := filepath.Dir(currentTestFile(t))
	files, err := filepath.Glob(filepath.Join(directory, "*_module.go"))
	if err != nil {
		t.Fatal(err)
	}
	files = append(files, filepath.Join(directory, "module.go"))
	for _, file := range files {
		parsed, parseErr := parser.ParseFile(token.NewFileSet(), file, nil, 0)
		if parseErr != nil {
			t.Fatal(parseErr)
		}
		ast.Inspect(parsed, func(node ast.Node) bool {
			decl, ok := node.(*ast.TypeSpec)
			if !ok {
				return true
			}
			isResult := strings.HasSuffix(decl.Name.Name, "ModuleResult")
			isPort := strings.HasSuffix(decl.Name.Name, "Port")
			if !isResult && !isPort && decl.Name.Name != "moduleContext" {
				return true
			}
			structure, ok := decl.Type.(*ast.StructType)
			if !ok {
				t.Errorf("%s must be a struct", decl.Name.Name)
				return false
			}
			for _, field := range structure.Fields.List {
				if isResult || isPort {
					for _, name := range field.Names {
						if !name.IsExported() {
							t.Errorf("%s.%s must be an exported named port", decl.Name.Name, name.Name)
						}
					}
				}
				pointer, ok := field.Type.(*ast.StarExpr)
				if !ok {
					continue
				}
				if isResult || isPort {
					t.Errorf("%s exposes a concrete pointer; use a callable or minimal interface", decl.Name.Name)
					continue
				}
				selector, ok := pointer.X.(*ast.SelectorExpr)
				if ok && selector.Sel.Name == "Service" {
					t.Errorf("%s exposes concrete service pointer; use a named narrow port", decl.Name.Name)
				}
			}
			return false
		})
	}
}

func routeSet(routes []gin.RouteInfo) map[string]bool {
	set := make(map[string]bool, len(routes))
	for _, route := range routes {
		set[route.Method+" "+route.Path] = true
	}
	return set
}

func routeDelta(before, after map[string]bool) []string {
	delta := make([]string, 0, len(after)-len(before))
	for route := range after {
		if !before[route] {
			delta = append(delta, route)
		}
	}
	sort.Strings(delta)
	return delta
}

func TestModuleAssemblyFilesStayFocused(t *testing.T) {
	directory := filepath.Dir(currentTestFile(t))
	installerFiles, err := filepath.Glob(filepath.Join(directory, "*_module.go"))
	if err != nil {
		t.Fatal(err)
	}
	if len(installerFiles) != 7 {
		t.Fatalf("module installer file count = %d, want 7", len(installerFiles))
	}
	files := append(installerFiles, filepath.Join(directory, "module.go"))
	for _, file := range files {
		data, readErr := os.ReadFile(file)
		if readErr != nil {
			t.Fatal(readErr)
		}
		if lines := strings.Count(string(data), "\n") + 1; lines > 250 {
			t.Errorf("%s has %d lines; split the installer", filepath.Base(file), lines)
		}
	}
}

func TestInstallersOnlyConstructOwnedDomainRepositories(t *testing.T) {
	directory := filepath.Dir(currentTestFile(t))
	allowed := map[string]map[string]bool{
		"identity_module.go":   {"auth": true},
		"creation_module.go":   {"ai": true, "mods": true, "quota": true},
		"catalog_module.go":    {"games": true, "users": true},
		"commerce_module.go":   {"commerce": true, "participation": true, "payments": true},
		"community_module.go":  {"community": true, "inbox": true, "moderation": true, "social": true},
		"engagement_module.go": {"library": true, "replays": true, "rooms": true},
		"operations_module.go": {"analytics": true, "feedback": true, "prefs": true},
	}
	constructor := regexp.MustCompile(`\b([a-z]+)\.NewGorm(?:Repo|StateStore|UserRepo|RuntimeStore|Recorder)\b`)
	for file, ownedPackages := range allowed {
		data, err := os.ReadFile(filepath.Join(directory, file))
		if err != nil {
			t.Fatal(err)
		}
		for _, match := range constructor.FindAllStringSubmatch(string(data), -1) {
			if !ownedPackages[match[1]] {
				t.Errorf("%s constructs repository owned by %s", file, match[1])
			}
		}
	}
}

func currentTestFile(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime caller failed")
	}
	return file
}
