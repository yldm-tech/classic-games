// Package config persists the classic-games CLI state on disk: user settings in config.json and per-server login tokens in credentials.json, both inside one directory. The directory is created with mode 0700 and the files are written with mode 0600. A directory that already exists keeps its mode, because CLASSIC_GAMES_CONFIG_DIR may point at a directory the user also uses for other things; PermissionWarnings reports one that other users can write to.
package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// EnvConfigDir overrides the directory that holds config.json and credentials.json. It exists for tests, CI jobs and sandboxes that must not touch the user's real configuration.
const EnvConfigDir = "CLASSIC_GAMES_CONFIG_DIR"

const (
	appDirName      = "classic-games"
	settingsFile    = "config.json"
	credentialsFile = "credentials.json"
	dirMode         = 0o700
	fileMode        = 0o600
)

// Settings are the values a user stores with "classic-games config set". Every field is optional; an empty field means "not set".
type Settings struct {
	// ServerURL is the backend root, such as "http://localhost:8080".
	ServerURL string `json:"server_url,omitempty"`
	// Language is the language of server messages: "zh", "en" or "ja".
	Language string `json:"language,omitempty"`
	// SchemaDir is an absolute path to the directory with the Mod DSL JSON Schemas.
	SchemaDir string `json:"schema_dir,omitempty"`
}

// Credential is the login state for one server. The token is a bearer secret and must never be printed.
type Credential struct {
	Token    string `json:"token"`
	UserID   string `json:"user_id,omitempty"`
	Nickname string `json:"nickname,omitempty"`
	// Method records how the session was created ("guest", "sms" or "password"). The backend does not expose whether an account is a guest, so the CLI remembers it.
	Method  string    `json:"method,omitempty"`
	SavedAt time.Time `json:"saved_at"`
}

type credentialsDocument struct {
	Servers map[string]Credential `json:"servers"`
}

// Dir returns the configuration directory: $CLASSIC_GAMES_CONFIG_DIR when set, otherwise os.UserConfigDir()/classic-games.
func Dir(getenv func(string) string) (string, error) {
	if override := getenv(EnvConfigDir); override != "" {
		absolute, err := filepath.Abs(override)
		if err != nil {
			return "", fmt.Errorf("resolve %s: %w", EnvConfigDir, err)
		}
		return absolute, nil
	}
	base, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("locate the user config directory (set %s to choose one): %w", EnvConfigDir, err)
	}
	return filepath.Join(base, appDirName), nil
}

// Store reads and writes the files of one configuration directory.
type Store struct {
	dir string
}

// NewStore returns a store rooted at dir. The directory is created on the first write.
func NewStore(dir string) *Store { return &Store{dir: dir} }

// Dir returns the configuration directory.
func (s *Store) Dir() string { return s.dir }

// SettingsPath returns the path of config.json.
func (s *Store) SettingsPath() string { return filepath.Join(s.dir, settingsFile) }

// CredentialsPath returns the path of credentials.json.
func (s *Store) CredentialsPath() string { return filepath.Join(s.dir, credentialsFile) }

// LoadSettings reads config.json. A missing file yields the zero Settings.
func (s *Store) LoadSettings() (Settings, error) {
	var settings Settings
	if err := readJSON(s.SettingsPath(), &settings); err != nil {
		return Settings{}, err
	}
	return settings, nil
}

// SaveSettings replaces config.json.
func (s *Store) SaveSettings(settings Settings) error {
	return s.writeJSON(s.SettingsPath(), settings)
}

// Credential returns the stored login for server. found is false when there is none.
func (s *Store) Credential(server string) (credential Credential, found bool, err error) {
	document, err := s.loadCredentials()
	if err != nil {
		return Credential{}, false, err
	}
	credential, found = document.Servers[server]
	if found && credential.Token == "" {
		return Credential{}, false, nil
	}
	return credential, found, nil
}

// SaveCredential stores the login for server, replacing an earlier one for the same server.
func (s *Store) SaveCredential(server string, credential Credential) error {
	if credential.Token == "" {
		return errors.New("refusing to store an empty token")
	}
	document, err := s.loadCredentials()
	if err != nil {
		return err
	}
	document.Servers[server] = credential
	return s.writeJSON(s.CredentialsPath(), document)
}

// DeleteCredential removes the login for server. removed is false when none was stored.
func (s *Store) DeleteCredential(server string) (removed bool, err error) {
	document, err := s.loadCredentials()
	if err != nil {
		return false, err
	}
	if _, found := document.Servers[server]; !found {
		return false, nil
	}
	delete(document.Servers, server)
	if err := s.writeJSON(s.CredentialsPath(), document); err != nil {
		return false, err
	}
	return true, nil
}

// othersMask selects the permission bits of the group and of everyone else.
const othersMask = 0o077

// othersWriteMask selects the write bits of the group and of everyone else.
const othersWriteMask = 0o022

// PermissionWarnings returns one message for each way other local users can still reach the stored tokens: a configuration directory they can write to (they can replace or delete credentials.json and config.json whatever the mode of the files), and a credentials.json they can read whose mode could not be narrowed. It changes nothing and returns nil on Windows, where the mode bits do not describe access.
func (s *Store) PermissionWarnings() []string {
	if runtime.GOOS == "windows" {
		return nil
	}
	var warnings []string
	if info, err := os.Stat(s.dir); err == nil && info.Mode().Perm()&othersWriteMask != 0 {
		warnings = append(warnings, fmt.Sprintf("%s is writable by other users (mode %04o); credentials and settings stored there can be replaced", s.dir, info.Mode().Perm()))
	}
	if info, err := os.Stat(s.CredentialsPath()); err == nil && info.Mode().Perm()&othersMask != 0 {
		warnings = append(warnings, fmt.Sprintf("%s is readable by other users (mode %04o) and its mode could not be changed to 0600", s.CredentialsPath(), info.Mode().Perm()))
	}
	return warnings
}

// restrictCredentials narrows credentials.json to mode 0600 when the group or everyone else has any access to it. Every write already does this through the rename in writeJSON; this covers a file that is only read. The file belongs to the CLI alone, so changing its mode has no side effect on anything else. A failure (a read-only mount, a file owned by someone else) is left to PermissionWarnings, since the token can still be used.
func (s *Store) restrictCredentials() {
	if runtime.GOOS == "windows" {
		return
	}
	if info, err := os.Stat(s.CredentialsPath()); err == nil && info.Mode().Perm()&othersMask != 0 {
		_ = os.Chmod(s.CredentialsPath(), fileMode)
	}
}

func (s *Store) loadCredentials() (credentialsDocument, error) {
	s.restrictCredentials()
	var document credentialsDocument
	if err := readJSON(s.CredentialsPath(), &document); err != nil {
		return credentialsDocument{}, err
	}
	if document.Servers == nil {
		document.Servers = map[string]Credential{}
	}
	return document, nil
}

func readJSON(path string, out any) error {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}
	return nil
}

// writeJSON writes value to path through a temporary file in the same directory followed by a rename, so a crash never leaves a half-written file and the result always has mode 0600 even when it replaces a file with wider permissions.
func (s *Store) writeJSON(path string, value any) error {
	if err := os.MkdirAll(s.dir, dirMode); err != nil {
		return fmt.Errorf("create %s: %w", s.dir, err)
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", path, err)
	}
	data = append(data, '\n')

	temporary, err := os.CreateTemp(s.dir, filepath.Base(path)+".*.tmp")
	if err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	temporaryPath := temporary.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(temporaryPath)
		}
	}()

	if err := temporary.Chmod(fileMode); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write %s: %w", path, err)
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write %s: %w", path, err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	committed = true
	return nil
}
