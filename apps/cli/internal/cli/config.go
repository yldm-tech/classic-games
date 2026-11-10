package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"forgeplay/cli/internal/config"
	"forgeplay/sdk"

	"github.com/spf13/cobra"
)

// Keys accepted by "forgeplay config get|set|unset".
const (
	keyServer    = "server"
	keyLanguage  = "language"
	keySchemaDir = "schema-dir"
)

var configKeys = []string{keyServer, keyLanguage, keySchemaDir}

var languages = []string{"zh", "en", "ja"}

func validateLanguage(value string) error {
	if !slices.Contains(languages, value) {
		return fmt.Errorf("invalid language %q: want one of %s", value, strings.Join(languages, ", "))
	}
	return nil
}

func validateKey(key string) error {
	if !slices.Contains(configKeys, key) {
		return fmt.Errorf("unknown config key %q: want one of %s", key, strings.Join(configKeys, ", "))
	}
	return nil
}

func (a *app) configCommand() *cobra.Command {
	return group("config", "Read and change the CLI configuration",
		a.configGetCommand(),
		a.configSetCommand(),
		a.configUnsetCommand(),
		a.configPathCommand(),
	)
}

func (a *app) configGetCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "get [key]",
		Short: "Show effective settings and where each value comes from",
		Long: `Show the effective value of every setting, or of one key, after applying flags and environment variables on top of the config file.

Keys: ` + strings.Join(configKeys, ", ") + `. With a key and table output only the value is printed, which suits shell substitution.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			store, err := a.store()
			if err != nil {
				return err
			}
			settings, err := store.LoadSettings()
			if err != nil {
				return err
			}
			effective := []setting{a.resolveServer(settings), a.resolveLanguage(settings), a.resolveSchemaDir(settings, "")}
			if len(args) == 1 {
				if err := validateKey(args[0]); err != nil {
					return err
				}
				index := slices.IndexFunc(effective, func(s setting) bool { return s.Key == args[0] })
				one := effective[index]
				return a.emit(cmd, itemList[setting]{Items: []setting{one}}, func(w io.Writer) error {
					_, err := fmt.Fprintln(w, one.Value)
					return err
				})
			}
			return a.emit(cmd, itemList[setting]{Items: effective}, func(w io.Writer) error {
				rows := make([][]string, len(effective))
				for i, s := range effective {
					rows[i] = []string{s.Key, s.Value, s.Source}
				}
				return writeTable(w, []string{"KEY", "VALUE", "SOURCE"}, rows)
			})
		},
	}
}

func (a *app) configSetCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "set <key> <value>",
		Short: "Store a setting in the config file",
		Long: `Store a setting in the config file.

  server      backend URL, such as http://localhost:8080
  language    language of server messages: ` + strings.Join(languages, ", ") + `
  schema-dir  directory with the Mod DSL JSON Schemas (stored as an absolute path)`,
		Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			key, value := args[0], args[1]
			if err := validateKey(key); err != nil {
				return err
			}
			store, err := a.store()
			if err != nil {
				return err
			}
			settings, err := store.LoadSettings()
			if err != nil {
				return err
			}
			switch key {
			case keyServer:
				client, err := sdk.New(value)
				if err != nil {
					return fmt.Errorf("invalid server URL %q: want http(s)://host[:port][/prefix]", value)
				}
				value = client.BaseURL()
				settings.ServerURL = value
			case keyLanguage:
				if err := validateLanguage(value); err != nil {
					return err
				}
				settings.Language = value
			case keySchemaDir:
				absolute, err := filepath.Abs(value)
				if err != nil {
					return fmt.Errorf("resolve %s: %w", value, err)
				}
				if !hasSchemas(absolute) {
					return fmt.Errorf("%s holds no *.schema.json files", absolute)
				}
				value = absolute
				settings.SchemaDir = value
			}
			if err := store.SaveSettings(settings); err != nil {
				return err
			}
			return a.emit(cmd, setting{Key: key, Value: value, Source: sourceConfig}, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "Set %s to %s in %s\n", key, value, store.SettingsPath())
				return err
			})
		},
	}
}

func (a *app) configUnsetCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "unset <key>",
		Short: "Remove a setting from the config file",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			key := args[0]
			if err := validateKey(key); err != nil {
				return err
			}
			store, err := a.store()
			if err != nil {
				return err
			}
			settings, err := store.LoadSettings()
			if err != nil {
				return err
			}
			switch key {
			case keyServer:
				settings.ServerURL = ""
			case keyLanguage:
				settings.Language = ""
			case keySchemaDir:
				settings.SchemaDir = ""
			}
			if err := store.SaveSettings(settings); err != nil {
				return err
			}
			return a.emit(cmd, setting{Key: key, Source: sourceUnset}, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "Removed %s from %s\n", key, store.SettingsPath())
				return err
			})
		},
	}
}

type configPaths struct {
	Dir         string `json:"config_dir"`
	Settings    string `json:"config_file"`
	Credentials string `json:"credentials_file"`
}

func (a *app) configPathCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "path",
		Short: "Print the path of the config file",
		Long:  "Print the path of the config file. Set " + config.EnvConfigDir + " to use another directory. Login tokens are kept next to it in credentials.json with mode 0600.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			store, err := a.store()
			if err != nil {
				return err
			}
			paths := configPaths{Dir: store.Dir(), Settings: store.SettingsPath(), Credentials: store.CredentialsPath()}
			return a.emit(cmd, paths, func(w io.Writer) error {
				_, err := fmt.Fprintln(w, paths.Settings)
				return err
			})
		},
	}
}

// resolveSchemaDir picks the schema directory: the --schema-dir flag, then FORGEPLAY_SCHEMA_DIR, then the config file, then packages/schemas of the repository that contains the working directory.
func (a *app) resolveSchemaDir(settings config.Settings, flag string) setting {
	result := setting{Key: keySchemaDir, Source: sourceUnset}
	switch {
	case flag != "":
		result.Value, result.Source = flag, sourceFlag
	case a.options.Getenv(EnvSchemaDir) != "":
		result.Value, result.Source = a.options.Getenv(EnvSchemaDir), sourceEnv
	case settings.SchemaDir != "":
		result.Value, result.Source = settings.SchemaDir, sourceConfig
	default:
		if detected, ok := detectSchemaDir(); ok {
			result.Value, result.Source = detected, sourceDetected
		}
	}
	return result
}

const (
	sourceDetected   = "repository"
	schemaFileSuffix = ".schema.json"
)

// detectSchemaDir walks from the working directory up to the filesystem root and returns the first packages/schemas directory that holds schema files.
func detectSchemaDir() (string, bool) {
	directory, err := os.Getwd()
	if err != nil {
		return "", false
	}
	for {
		candidate := filepath.Join(directory, "packages", "schemas")
		if hasSchemas(candidate) {
			return candidate, true
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			return "", false
		}
		directory = parent
	}
}

func hasSchemas(directory string) bool {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), schemaFileSuffix) {
			return true
		}
	}
	return false
}
