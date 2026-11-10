package config

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestDirPrefersTheEnvironmentOverride(t *testing.T) {
	override := t.TempDir()
	got, err := Dir(func(key string) string {
		if key == EnvConfigDir {
			return override
		}
		return ""
	})
	if err != nil {
		t.Fatal(err)
	}
	if got != override {
		t.Fatalf("Dir = %q, want %q", got, override)
	}
}

func TestDirDefaultsToTheUserConfigDirectory(t *testing.T) {
	base, err := os.UserConfigDir()
	if err != nil {
		t.Skipf("no user config directory on this machine: %v", err)
	}
	got, err := Dir(func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(base, "forgeplay"); got != want {
		t.Fatalf("Dir = %q, want %q", got, want)
	}
}

func TestSettingsRoundTrip(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "nested", "forgeplay"))

	empty, err := store.LoadSettings()
	if err != nil {
		t.Fatalf("loading settings before any write: %v", err)
	}
	if empty != (Settings{}) {
		t.Fatalf("settings before any write = %+v, want zero", empty)
	}

	want := Settings{ServerURL: "https://play.example.com", Language: "en", SchemaDir: "/srv/schemas"}
	if err := store.SaveSettings(want); err != nil {
		t.Fatal(err)
	}
	got, err := store.LoadSettings()
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("settings = %+v, want %+v", got, want)
	}
}

func TestCredentialsAreStoredPerServerWithOwnerOnlyPermissions(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "forgeplay"))
	first := Credential{Token: "token-a", UserID: "u1", Nickname: "Ada", Method: "guest", SavedAt: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)}
	second := Credential{Token: "token-b", UserID: "u2", Method: "password", SavedAt: time.Date(2026, 2, 2, 3, 4, 5, 0, time.UTC)}

	if err := store.SaveCredential("http://a.example", first); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveCredential("http://b.example", second); err != nil {
		t.Fatal(err)
	}

	got, found, err := store.Credential("http://a.example")
	if err != nil || !found || got != first {
		t.Fatalf("credential for a = %+v, found %v, err %v; want %+v", got, found, err, first)
	}
	if _, found, _ := store.Credential("http://c.example"); found {
		t.Fatal("a credential was reported for a server that never logged in")
	}

	if runtime.GOOS != "windows" {
		assertMode(t, store.CredentialsPath(), 0o600)
		assertMode(t, store.Dir(), 0o700)
	}

	removed, err := store.DeleteCredential("http://a.example")
	if err != nil || !removed {
		t.Fatalf("delete = %v, %v; want true, nil", removed, err)
	}
	if removed, _ := store.DeleteCredential("http://a.example"); removed {
		t.Fatal("deleting twice reported a removal the second time")
	}
	if _, found, _ := store.Credential("http://a.example"); found {
		t.Fatal("the credential is still there after delete")
	}
	if got, found, _ := store.Credential("http://b.example"); !found || got != second {
		t.Fatalf("deleting a removed b as well: %+v, found %v", got, found)
	}
}

func TestSaveCredentialTightensAnExistingFile(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX permission bits are not enforced on Windows")
	}
	store := NewStore(t.TempDir())
	if err := os.WriteFile(store.CredentialsPath(), []byte(`{"servers":{}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveCredential("http://a.example", Credential{Token: "token-a"}); err != nil {
		t.Fatal(err)
	}
	assertMode(t, store.CredentialsPath(), 0o600)
}

// A credentials file that is only read keeps whatever mode it was given, so reading narrows it; every write already does.
func TestReadingCredentialsNarrowsAWideFile(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX permission bits are not enforced on Windows")
	}
	// t.TempDir follows the umask, which may leave the directory group-writable; the file is what this test is about.
	dir := t.TempDir()
	if err := os.Chmod(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	store := NewStore(dir)
	if err := os.WriteFile(store.CredentialsPath(), []byte(`{"servers":{"http://a.example":{"token":"token-a"}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(store.CredentialsPath(), 0o644); err != nil {
		t.Fatal(err)
	}
	credential, found, err := store.Credential("http://a.example")
	if err != nil || !found || credential.Token != "token-a" {
		t.Fatalf("credential = %+v, found %v, err %v", credential, found, err)
	}
	assertMode(t, store.CredentialsPath(), 0o600)
	if warnings := store.PermissionWarnings(); len(warnings) != 0 {
		t.Fatalf("warnings = %q, want none for a private directory and a narrowed file", warnings)
	}
	// Settings are not secret and are not touched by a read.
	if err := os.WriteFile(store.SettingsPath(), []byte(`{}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := store.LoadSettings(); err != nil {
		t.Fatal(err)
	}
	assertMode(t, store.SettingsPath(), 0o644)
}

// The directory may be one the user chose and also uses for other things, so its mode is reported, never changed.
func TestADirectoryWritableByOthersIsReportedAndLeftAlone(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX permission bits are not enforced on Windows")
	}
	for _, mode := range []os.FileMode{0o777, 0o775, 0o1777} {
		dir := t.TempDir()
		if err := os.Chmod(dir, mode); err != nil {
			t.Fatal(err)
		}
		store := NewStore(dir)
		if err := store.SaveCredential("http://a.example", Credential{Token: "token-a"}); err != nil {
			t.Fatal(err)
		}
		if _, _, err := store.Credential("http://a.example"); err != nil {
			t.Fatal(err)
		}
		warnings := store.PermissionWarnings()
		if len(warnings) != 1 || !strings.Contains(warnings[0], dir+" is writable by other users") {
			t.Fatalf("mode %o: warnings = %q, want one about the directory", mode, warnings)
		}
		assertMode(t, dir, mode.Perm())
		assertMode(t, store.CredentialsPath(), 0o600)
	}
	for _, mode := range []os.FileMode{0o700, 0o755, 0o750} {
		dir := t.TempDir()
		if err := os.Chmod(dir, mode); err != nil {
			t.Fatal(err)
		}
		if warnings := NewStore(dir).PermissionWarnings(); len(warnings) != 0 {
			t.Fatalf("mode %o: warnings = %q, want none", mode, warnings)
		}
	}
	// A directory that does not exist yet is created private on the first write.
	if warnings := NewStore(filepath.Join(t.TempDir(), "missing")).PermissionWarnings(); len(warnings) != 0 {
		t.Fatalf("missing directory: warnings = %q, want none", warnings)
	}
}

func TestSaveCredentialRejectsAnEmptyToken(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := store.SaveCredential("http://a.example", Credential{}); err == nil {
		t.Fatal("an empty token was stored")
	}
}

func TestWritesLeaveNoTemporaryFiles(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := store.SaveSettings(Settings{Language: "ja"}); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveCredential("http://a.example", Credential{Token: "token-a"}); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(store.Dir())
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	if got := strings.Join(names, ","); got != "config.json,credentials.json" {
		t.Fatalf("directory holds %q, want only config.json and credentials.json", got)
	}
}

func TestCorruptFilesAreReportedWithTheirPath(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := os.WriteFile(store.SettingsPath(), []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := store.LoadSettings()
	if err == nil || !strings.Contains(err.Error(), store.SettingsPath()) {
		t.Fatalf("error = %v, want one naming %s", err, store.SettingsPath())
	}
}

func assertMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != want {
		t.Fatalf("%s has mode %o, want %o", path, got, want)
	}
}
