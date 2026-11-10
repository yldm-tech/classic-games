package cli

import (
	"fmt"
	"io"
	"runtime"

	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/spf13/cobra"
)

type versionReport struct {
	Version    string `json:"version"`
	Commit     string `json:"commit"`
	Date       string `json:"date"`
	GoVersion  string `json:"go_version"`
	OS         string `json:"os"`
	Arch       string `json:"arch"`
	SDKVersion string `json:"sdk_version"`
}

func (a *app) versionCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the CLI version and build information",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			report := versionReport{
				Version:    a.options.Build.Version,
				Commit:     a.options.Build.Commit,
				Date:       a.options.Build.Date,
				GoVersion:  runtime.Version(),
				OS:         runtime.GOOS,
				Arch:       runtime.GOARCH,
				SDKVersion: sdk.Version,
			}
			return a.emit(cmd, report, func(w io.Writer) error {
				_, err := fmt.Fprintf(w, "classic-games %s (commit %s, built %s, %s %s/%s, sdk %s)\n", report.Version, report.Commit, report.Date, report.GoVersion, report.OS, report.Arch, report.SDKVersion)
				return err
			})
		},
	}
}
