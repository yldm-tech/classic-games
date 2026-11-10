package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/spf13/cobra"
)

func (a *app) serverCommand() *cobra.Command {
	return group("server", "Inspect the backend the CLI talks to",
		a.serverHealthCommand(),
		a.serverInfoCommand(),
	)
}

type healthReport struct {
	Server string `json:"server"`
	OK     bool   `json:"ok"`
}

func (a *app) serverHealthCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "health",
		Short: "Check that the backend is reachable and reports healthy",
		Long:  "Call GET /healthz. Exits with status 1 when the backend is unreachable or unhealthy.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			if err := current.client.Health(cmd.Context()); err != nil {
				return err
			}
			report := healthReport{Server: current.client.BaseURL(), OK: true}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "%s is healthy\n", report.Server)
				return err
			})
		},
	}
}

type infoReport struct {
	Server string `json:"server"`
	*sdk.Meta
}

func (a *app) serverInfoCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "info",
		Short: "Show which optional integrations the backend has configured",
		Long:  "Call GET /api/v1/meta: environment, AI mode (live model or deterministic stub), SMS gateway, OAuth providers, payments, admin and moderation.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			meta, err := current.client.Meta(cmd.Context())
			if err != nil {
				return err
			}
			meta.OAuthProviders = orEmpty(meta.OAuthProviders)
			report := infoReport{Server: current.client.BaseURL(), Meta: meta}
			return a.emit(cmd, report, func(w io.Writer) error {
				return writeFields(w, []field{
					{"Server", report.Server},
					{"Environment", meta.Environment},
					{"AI mode", meta.AI.Mode},
					{"SMS gateway", formatBool(meta.SMS)},
					{"OAuth providers", strings.Join(meta.OAuthProviders, ", ")},
					{"Payments", formatBool(meta.Payments)},
					{"Admin configured", formatBool(meta.AdminConfigured)},
					{"External moderation", formatBool(meta.Moderation)},
				})
			})
		},
	}
}
