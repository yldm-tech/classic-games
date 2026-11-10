// Package cli implements the classic-games command tree. Networked commands go through github.com/yldm-tech/classic-games/packages/sdk, offline DSL commands through github.com/yldm-tech/classic-games/packages/dsl; the package itself holds no business rules.
package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/yldm-tech/classic-games/apps/cli/internal/config"
	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/spf13/cobra"
)

// Environment variables read by the CLI. config.EnvConfigDir (CLASSIC_GAMES_CONFIG_DIR) is the fourth one.
const (
	// EnvServerURL overrides the configured backend URL; the --server flag overrides both.
	EnvServerURL = "CLASSIC_GAMES_SERVER_URL"
	// EnvSchemaDir points the offline dsl commands at the directory with the Mod DSL JSON Schemas; the --schema-dir flag overrides it.
	EnvSchemaDir = "CLASSIC_GAMES_SCHEMA_DIR"
	// EnvLanguage selects the language of server messages ("zh", "en" or "ja") and overrides the configured one.
	EnvLanguage = "CLASSIC_GAMES_LANG"
)

const (
	outputTable = "table"
	outputJSON  = "json"
)

// Exit codes returned by Run.
const (
	ExitOK          = 0
	ExitFailure     = 1
	ExitInterrupted = 130
)

// BuildInfo is injected at link time through -ldflags.
type BuildInfo struct {
	Version string
	Commit  string
	Date    string
}

// Options carries everything the command tree takes from the process, so tests can run it against buffers and a temporary configuration directory.
type Options struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
	// Getenv looks up an environment variable; os.Getenv in production.
	Getenv func(string) string
	Build  BuildInfo
}

// Run executes the CLI with args (without the program name) and returns the process exit code. Results go to Stdout, errors to Stderr.
func Run(ctx context.Context, args []string, options Options) int {
	if args == nil {
		args = []string{}
	}
	root := NewRootCommand(options)
	root.SetArgs(args)
	err := root.ExecuteContext(ctx)
	if err == nil {
		return ExitOK
	}
	// ctx.Err is checked as well as the error chain: signal.NotifyContext cancels with a cause ("interrupt signal received"), and net/http reports that cause instead of context.Canceled.
	if ctx.Err() != nil || errors.Is(err, context.Canceled) {
		fmt.Fprintln(options.Stderr, "Error: interrupted")
		return ExitInterrupted
	}
	fmt.Fprintln(options.Stderr, "Error: "+describeError(err))
	return ExitFailure
}

type app struct {
	options Options
	// server and output hold the global --server and --output flags.
	server string
	output string
}

// NewRootCommand builds the whole command tree.
func NewRootCommand(options Options) *cobra.Command {
	a := &app{options: options}
	root := &cobra.Command{
		Use:   "classic-games",
		Short: "Command-line client for the Classic Games backend and the Mod DSL",
		Long: `classic-games talks to a Classic Games backend (catalog, mods, AI generation) and works with Mod DSL documents offline (schema validation, RFC 6902 patches, migration).

The backend URL comes from --server, then ` + EnvServerURL + `, then "classic-games config set server", then ` + sdk.DefaultBaseURL + `.`,
		Args:          cobra.NoArgs,
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(*cobra.Command, []string) error {
			if a.output != outputTable && a.output != outputJSON {
				return fmt.Errorf("invalid --output %q: want %s or %s", a.output, outputTable, outputJSON)
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, _ []string) error { return cmd.Help() },
	}
	root.SetIn(options.Stdin)
	root.SetOut(options.Stdout)
	root.SetErr(options.Stderr)
	root.PersistentFlags().StringVar(&a.server, "server", "", "backend URL, such as http://localhost:8080 (overrides "+EnvServerURL+" and the config file)")
	root.PersistentFlags().StringVar(&a.output, "output", outputTable, "output format: table or json")

	root.AddCommand(
		a.versionCommand(),
		a.configCommand(),
		a.authCommand(),
		a.serverCommand(),
		a.gamesCommand(),
		a.modsCommand(),
		a.aiCommand(),
		a.dslCommand(),
	)
	return root
}

// group returns a command that only holds subcommands. It prints its help when called bare and rejects an unknown subcommand instead of silently showing help.
func group(use, short string, children ...*cobra.Command) *cobra.Command {
	command := &cobra.Command{
		Use:   use,
		Short: short,
		Args:  cobra.NoArgs,
		RunE:  func(cmd *cobra.Command, _ []string) error { return cmd.Help() },
	}
	command.AddCommand(children...)
	return command
}

// idArgs requires exactly n positional arguments, none of them blank. An empty id would address the collection instead of one resource (GET /games/ rather than GET /games/<id>).
func idArgs(n int) cobra.PositionalArgs {
	return func(cmd *cobra.Command, args []string) error {
		if err := cobra.ExactArgs(n)(cmd, args); err != nil {
			return err
		}
		for _, arg := range args {
			if strings.TrimSpace(arg) == "" {
				return errors.New("the id argument is empty")
			}
		}
		return nil
	}
}

func (a *app) jsonOutput() bool { return a.output == outputJSON }

func (a *app) store() (*config.Store, error) {
	dir, err := config.Dir(a.options.Getenv)
	if err != nil {
		return nil, err
	}
	return config.NewStore(dir), nil
}

// setting is one effective configuration value together with where it came from.
type setting struct {
	Key    string `json:"key"`
	Value  string `json:"value"`
	Source string `json:"source"`
}

const (
	sourceFlag    = "flag"
	sourceEnv     = "env"
	sourceConfig  = "config"
	sourceDefault = "default"
	sourceUnset   = "unset"
)

func (a *app) resolveServer(settings config.Settings) setting {
	result := setting{Key: keyServer}
	switch {
	case a.server != "":
		result.Value, result.Source = a.server, sourceFlag
	case a.options.Getenv(EnvServerURL) != "":
		result.Value, result.Source = a.options.Getenv(EnvServerURL), sourceEnv
	case settings.ServerURL != "":
		result.Value, result.Source = settings.ServerURL, sourceConfig
	default:
		result.Value, result.Source = sdk.DefaultBaseURL, sourceDefault
	}
	return result
}

func (a *app) resolveLanguage(settings config.Settings) setting {
	result := setting{Key: keyLanguage, Source: sourceUnset}
	switch {
	case a.options.Getenv(EnvLanguage) != "":
		result.Value, result.Source = a.options.Getenv(EnvLanguage), sourceEnv
	case settings.Language != "":
		result.Value, result.Source = settings.Language, sourceConfig
	}
	return result
}

// session is a client for the resolved server plus the login stored for it.
type session struct {
	client     *sdk.Client
	store      *config.Store
	credential config.Credential
	loggedIn   bool
}

// connect builds a client for the resolved server. When a token is stored for that server it is attached, so public endpoints still get the signed-in view.
func (a *app) connect() (*session, error) {
	store, err := a.store()
	if err != nil {
		return nil, err
	}
	settings, err := store.LoadSettings()
	if err != nil {
		return nil, err
	}
	server := a.resolveServer(settings)
	language := a.resolveLanguage(settings)
	if language.Value != "" {
		if err := validateLanguage(language.Value); err != nil {
			return nil, err
		}
	}
	client, err := sdk.New(server.Value, sdk.WithUserAgent("classic-games-cli/"+a.options.Build.Version), sdk.WithLanguage(language.Value))
	if err != nil {
		return nil, fmt.Errorf("invalid server URL %q (from %s): want http(s)://host[:port][/prefix]", server.Value, server.Source)
	}
	credential, found, err := store.Credential(client.BaseURL())
	if err != nil {
		return nil, err
	}
	for _, warning := range store.PermissionWarnings() {
		fmt.Fprintln(a.options.Stderr, "Warning: "+warning)
	}
	if found {
		client.SetToken(credential.Token)
	}
	return &session{client: client, store: store, credential: credential, loggedIn: found}, nil
}

// connectSignedIn is connect for commands whose endpoints reject anonymous callers. It fails before any request when no login is stored.
func (a *app) connectSignedIn() (*session, error) {
	current, err := a.connect()
	if err != nil {
		return nil, err
	}
	if !current.loggedIn {
		return nil, fmt.Errorf("not logged in to %s: run 'classic-games auth login' first", current.client.BaseURL())
	}
	return current, nil
}

// describeError renders an error for stderr. A backend error becomes "CODE: message" in place of the SDK's request-oriented text, any context wrapped around it is kept, and a 401 also says how to recover.
func describeError(err error) string {
	var apiError *sdk.APIError
	if !errors.As(err, &apiError) {
		return err.Error()
	}
	code := apiError.Code
	if code == "" {
		code = fmt.Sprintf("HTTP %d", apiError.StatusCode)
	}
	message := strings.TrimSpace(apiError.Message)
	if message == "" {
		message = fmt.Sprintf("%s %s failed", apiError.Method, apiError.Path)
	}
	text := strings.Replace(err.Error(), apiError.Error(), code+": "+message, 1)
	if sdk.IsUnauthorized(err) && apiError.Code != sdk.CodeAuthInvalid {
		// --force is part of the hint because a rejected session is still stored, and a plain login refuses to replace a stored session.
		text += "\nThe stored login is missing, expired or revoked: run 'classic-games auth login --force'."
	}
	return text
}
