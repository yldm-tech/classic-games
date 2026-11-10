package cli

import (
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"
	"time"

	"forgeplay/cli/internal/config"
	"forgeplay/sdk"

	"github.com/spf13/cobra"
)

const (
	methodGuest    = "guest"
	methodSMS      = "sms"
	methodPassword = "password"
)

var loginMethods = []string{methodGuest, methodSMS, methodPassword}

// authReport is the JSON shape of every auth command except "auth token". It never carries the token.
type authReport struct {
	Server   string    `json:"server"`
	LoggedIn bool      `json:"logged_in"`
	Method   string    `json:"method,omitempty"`
	User     *sdk.User `json:"user,omitempty"`
}

func (a *app) authCommand() *cobra.Command {
	return group("auth", "Log in to a backend and manage the stored session",
		a.authLoginCommand(),
		a.authLogoutCommand(),
		a.authStatusCommand(),
		a.authRefreshCommand(),
		a.authSetPasswordCommand(),
		a.authTokenCommand(),
	)
}

func (a *app) authLoginCommand() *cobra.Command {
	var (
		method        string
		phone         string
		code          string
		passwordStdin bool
		force         bool
	)
	command := &cobra.Command{
		Use:   "login",
		Short: "Create a session and store its token for the server",
		Long: `Create a session on the backend and store its token in the config directory (mode 0600). This command does not print the token; "forgeplay auth token" prints it on request.

Methods:
  guest     (default) a new guest account; needs no credentials. A guest can create, fork and publish mods, but the account cannot be recovered once its token is lost.
  sms       --phone <number>; the backend texts a code that is then read from standard input. Pass --code to verify a code you already have without requesting a new one. Needs an SMS gateway on the server ("forgeplay server info").
  password  --phone <number> --password-stdin; for accounts that set a password with "forgeplay auth set-password".

Tokens are valid for 30 days; "forgeplay auth refresh" renews one.`,
		Example: `  forgeplay auth login
  forgeplay auth login --method sms --phone 13800000000
  printf '%s\n' "$FORGEPLAY_PASSWORD" | forgeplay auth login --method password --phone 13800000000 --password-stdin`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if !slices.Contains(loginMethods, method) {
				return fmt.Errorf("invalid --method %q: want one of %s", method, strings.Join(loginMethods, ", "))
			}
			if method != methodGuest && phone == "" {
				return fmt.Errorf("--method %s needs --phone", method)
			}
			if method == methodGuest && (phone != "" || code != "" || passwordStdin) {
				return errors.New("--phone, --code and --password-stdin do not apply to a guest login: pass --method sms or --method password")
			}
			if method == methodPassword && !passwordStdin {
				return errors.New("--method password needs --password-stdin: the password is read from standard input so it stays out of the process list and shell history")
			}
			if method == methodPassword && code != "" {
				return errors.New("--code only applies to --method sms")
			}
			if method == methodSMS && passwordStdin {
				return errors.New("--password-stdin only applies to --method password")
			}

			current, err := a.connect()
			if err != nil {
				return err
			}
			server := current.client.BaseURL()
			if current.loggedIn && !force {
				return fmt.Errorf("already logged in to %s as %s: run 'forgeplay auth logout' first, or pass --force to replace and revoke the stored session (a replaced guest account cannot be recovered)", server, describeUser(current.credential))
			}
			// Login requests are sent without the old token.
			current.client.SetToken("")

			ctx := cmd.Context()
			var login *sdk.Session
			switch method {
			case methodGuest:
				login, err = current.client.LoginGuest(ctx)
			case methodPassword:
				password, readErr := readLine(cmd)
				if readErr != nil {
					return fmt.Errorf("read the password: %w", readErr)
				}
				login, err = current.client.LoginPassword(ctx, phone, password)
			case methodSMS:
				if code == "" {
					meta, metaErr := current.client.Meta(ctx)
					if metaErr != nil {
						return metaErr
					}
					if !meta.SMS {
						return fmt.Errorf("%s has no SMS gateway configured, so a login code cannot be delivered: use a guest login ('forgeplay auth login') or --method password", server)
					}
					if err := current.client.SendSMSCode(ctx, phone); err != nil {
						return err
					}
					fmt.Fprintf(cmd.ErrOrStderr(), "A login code was sent to %s. It is valid for 5 minutes.\nCode: ", phone)
					code, err = readLine(cmd)
					if err != nil {
						return fmt.Errorf("read the login code: %w", err)
					}
				}
				login, err = current.client.LoginSMS(ctx, phone, strings.TrimSpace(code))
			}
			if err != nil {
				return err
			}

			credential := config.Credential{Token: login.Token, UserID: login.User.ID, Nickname: login.User.Nickname, Method: method, SavedAt: time.Now().UTC()}
			if err := current.store.SaveCredential(server, credential); err != nil {
				return fmt.Errorf("logged in, but the token could not be stored: %w", err)
			}
			// The replaced token is gone from disk, so it is revoked here or it stays valid on the backend until it expires. This happens only after the new session is stored: revoking first would destroy a guest account whenever the new login fails. A failure is a warning, because the new session is already in place.
			replacedRevoked := false
			if current.loggedIn && current.credential.Token != login.Token {
				current.client.SetToken(current.credential.Token)
				if err := current.client.Logout(ctx); err != nil {
					fmt.Fprintf(cmd.ErrOrStderr(), "Warning: the previous session could not be revoked and stays valid on the backend until it expires: %s\n", describeError(err))
				} else {
					replacedRevoked = true
				}
				current.client.SetToken(login.Token)
			}
			report := authReport{Server: server, LoggedIn: true, Method: method, User: &login.User}
			return a.emit(cmd, report, func(w io.Writer) error {
				if _, err := fmt.Fprintf(w, "Logged in to %s as %s (%s session)\n", server, describeUser(credential), method); err != nil {
					return err
				}
				if replacedRevoked {
					if _, err := fmt.Fprintf(w, "The previous session (%s) was revoked.\n", describeUser(current.credential)); err != nil {
						return err
					}
				}
				if method == methodGuest {
					_, err := fmt.Fprintf(w, "Guest accounts cannot be recovered: keep %s if you want to keep this account.\n", current.store.CredentialsPath())
					return err
				}
				return nil
			})
		},
	}
	command.Flags().StringVar(&method, "method", methodGuest, "login method: "+strings.Join(loginMethods, ", "))
	command.Flags().StringVar(&phone, "phone", "", "phone number, for --method sms and --method password")
	command.Flags().StringVar(&code, "code", "", "SMS code you already received; skips requesting a new one")
	command.Flags().BoolVar(&passwordStdin, "password-stdin", false, "read the password from standard input")
	command.Flags().BoolVar(&force, "force", false, "replace a session that is already stored for the server; once the new login succeeded the replaced session is revoked on the backend")
	return command
}

func (a *app) authLogoutCommand() *cobra.Command {
	var localOnly bool
	command := &cobra.Command{
		Use:   "logout",
		Short: "Revoke the stored session and delete its token",
		Long:  "Revoke the token on the backend, then delete it from the config directory. If the backend cannot be reached the token is kept, so a guest account is not lost by accident; pass --local to delete it without contacting the server.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			server := current.client.BaseURL()
			report := authReport{Server: server, LoggedIn: false}
			if !current.loggedIn {
				return a.emit(cmd, report, func(w io.Writer) error {
					_, err := fmt.Fprintf(w, "Not logged in to %s\n", server)
					return err
				})
			}
			if !localOnly {
				if err := current.client.Logout(cmd.Context()); err != nil {
					return fmt.Errorf("the session was not revoked and is still stored (pass --local to delete it without contacting the server): %w", err)
				}
			}
			if _, err := current.store.DeleteCredential(server); err != nil {
				return err
			}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "Logged out of %s\n", server)
				return err
			})
		},
	}
	command.Flags().BoolVar(&localOnly, "local", false, "delete the stored token without revoking it on the server")
	return command
}

func (a *app) authStatusCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show whether a valid session is stored for the server",
		Long:  "Check the stored session against the backend (GET /users/me). Exits with status 1 when no session is stored or the backend rejects the token.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			server := current.client.BaseURL()
			if !current.loggedIn {
				if err := a.emitAuthStatus(cmd, authReport{Server: server}, time.Time{}); err != nil {
					return err
				}
				return fmt.Errorf("not logged in to %s: run 'forgeplay auth login'", server)
			}
			user, err := current.client.CurrentUser(cmd.Context())
			if sdk.IsUnauthorized(err) {
				if emitErr := a.emitAuthStatus(cmd, authReport{Server: server, Method: current.credential.Method}, current.credential.SavedAt); emitErr != nil {
					return emitErr
				}
				return fmt.Errorf("the session stored for %s is expired or revoked: run 'forgeplay auth login --force'", server)
			}
			if err != nil {
				return err
			}
			return a.emitAuthStatus(cmd, authReport{Server: server, LoggedIn: true, Method: current.credential.Method, User: user}, current.credential.SavedAt)
		},
	}
}

func (a *app) emitAuthStatus(cmd *cobra.Command, report authReport, savedAt time.Time) error {
	return a.emit(cmd, report, func(w io.Writer) error {
		fields := []field{{"Server", report.Server}, {"Logged in", formatBool(report.LoggedIn)}}
		if report.User != nil {
			fields = append(fields, field{"User", report.User.Nickname}, field{"User ID", report.User.ID})
		}
		if report.Method != "" {
			fields = append(fields, field{"Method", report.Method}, field{"Token stored", formatTime(savedAt)})
		}
		return writeFields(w, fields)
	})
}

func (a *app) authRefreshCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "refresh",
		Short: "Trade the stored token for a fresh one valid for 30 days",
		Long:  "Call POST /auth/refresh. The backend revokes the stored token immediately and returns a new one, which replaces it in the config directory.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			server := current.client.BaseURL()
			token, err := current.client.RefreshToken(cmd.Context())
			if err != nil {
				return err
			}
			credential := current.credential
			credential.Token = token
			credential.SavedAt = time.Now().UTC()
			if err := current.store.SaveCredential(server, credential); err != nil {
				return fmt.Errorf("the token was refreshed, but the new one could not be stored and the old one is revoked; log in again: %w", err)
			}
			report := authReport{Server: server, LoggedIn: true, Method: credential.Method, User: &sdk.User{ID: credential.UserID, Nickname: credential.Nickname}}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "Refreshed the session for %s\n", server)
				return err
			})
		},
	}
}

func (a *app) authSetPasswordCommand() *cobra.Command {
	var passwordStdin bool
	command := &cobra.Command{
		Use:     "set-password",
		Short:   "Set the account password used by 'auth login --method password'",
		Long:    "Set or replace the password of the signed-in account (at least 8 characters). The password is read from standard input.",
		Example: `  printf '%s\n' "$FORGEPLAY_PASSWORD" | forgeplay auth set-password --password-stdin`,
		Args:    cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if !passwordStdin {
				return errors.New("pass --password-stdin: the password is read from standard input so it stays out of the process list and shell history")
			}
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			password, err := readLine(cmd)
			if err != nil {
				return fmt.Errorf("read the password: %w", err)
			}
			if err := current.client.SetPassword(cmd.Context(), password); err != nil {
				return err
			}
			server := current.client.BaseURL()
			report := authReport{Server: server, LoggedIn: true, Method: current.credential.Method, User: &sdk.User{ID: current.credential.UserID, Nickname: current.credential.Nickname}}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "Password set for %s on %s\n", describeUser(current.credential), server)
				return err
			})
		},
	}
	command.Flags().BoolVar(&passwordStdin, "password-stdin", false, "read the password from standard input")
	return command
}

// tokenReport is the JSON shape of "auth token", the only command that outputs the token.
type tokenReport struct {
	Server string `json:"server"`
	Token  string `json:"token"`
}

func (a *app) authTokenCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "token",
		Short: "Print the token stored for the server",
		Long: `Print the token stored for the server to standard output and nothing else. This is the only command that outputs the token; it exists to hand the session to another program, such as forgeplay-mcp through FORGEPLAY_TOKEN.

The token is not checked against the backend ("forgeplay auth status" does that). Anyone who holds it can act as the account until it expires or "forgeplay auth logout", "forgeplay auth refresh" or "forgeplay auth login --force" revokes it, so keep it out of logs and shared shell history.`,
		Example: `  export FORGEPLAY_TOKEN="$(forgeplay auth token)"`,
		Args:    cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			report := tokenReport{Server: current.client.BaseURL(), Token: current.credential.Token}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintln(w, report.Token)
				return err
			})
		},
	}
}

func describeUser(credential config.Credential) string {
	switch {
	case credential.Nickname != "" && credential.UserID != "":
		return fmt.Sprintf("%s (%s)", credential.Nickname, credential.UserID)
	case credential.Nickname != "":
		return credential.Nickname
	case credential.UserID != "":
		return credential.UserID
	default:
		return "an unnamed user"
	}
}
