package cli

import (
	"cmp"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/yldm-tech/classic-games/packages/dsl"
	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/santhosh-tekuri/jsonschema/v6"
	"github.com/spf13/cobra"
)

func (a *app) dslCommand() *cobra.Command {
	var schemaDir string
	command := group("dsl", "Validate, patch and migrate Mod DSL files offline",
		a.dslValidateCommand(&schemaDir),
		a.dslPatchCommand(&schemaDir),
		a.dslMigrateCommand(),
	)
	command.Long = `Work with Mod DSL documents without a backend. These commands use the same Go implementation as the server (github.com/yldm-tech/classic-games/packages/dsl), so a document that passes here passes there.

Schema validation needs the directory with the JSON Schemas (packages/schemas in the repository). It is taken from --schema-dir, then ` + EnvSchemaDir + `, then "classic-games config set schema-dir", and is found automatically when the command runs inside a repository checkout.`
	command.PersistentFlags().StringVar(&schemaDir, "schema-dir", "", "directory with the <runtime>-<version>.schema.json files")
	return command
}

// validationIssue is one schema violation: a JSON Pointer into the document and what is wrong there. An empty path means the document as a whole.
type validationIssue struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

type fileValidation struct {
	File    string            `json:"file"`
	Runtime string            `json:"runtime"`
	Valid   bool              `json:"valid"`
	Errors  []validationIssue `json:"errors"`
}

type validationReport struct {
	Valid     bool             `json:"valid"`
	SchemaDir string           `json:"schema_dir"`
	Results   []fileValidation `json:"results"`
}

// schemaValidator resolves the schema directory and returns a validator for it.
func (a *app) schemaValidator(flag string) (*dsl.SchemaValidator, string, error) {
	store, err := a.store()
	if err != nil {
		return nil, "", err
	}
	settings, err := store.LoadSettings()
	if err != nil {
		return nil, "", err
	}
	directory := a.resolveSchemaDir(settings, flag)
	if directory.Value == "" {
		return nil, "", fmt.Errorf("no schema directory: pass --schema-dir, set %s, run 'classic-games config set schema-dir <dir>', or run the command inside a repository checkout (packages/schemas)", EnvSchemaDir)
	}
	if !hasSchemas(directory.Value) {
		return nil, "", fmt.Errorf("schema directory %s (from %s) holds no *%s files", directory.Value, directory.Source, schemaFileSuffix)
	}
	return dsl.NewSchemaValidator(directory.Value), directory.Value, nil
}

// validateDocument returns the schema violations of document for the runtime ref, or nil when it is valid.
func validateDocument(validator *dsl.SchemaValidator, runtime string, document map[string]any) []validationIssue {
	err := validator.Validate(runtime, document)
	if err == nil {
		return nil
	}
	var schemaError *jsonschema.ValidationError
	if !errors.As(err, &schemaError) {
		return []validationIssue{{Message: err.Error()}}
	}
	var issues []validationIssue
	collectIssues(schemaError.DetailedOutput(), &issues)
	slices.SortFunc(issues, func(x, y validationIssue) int {
		return cmp.Or(cmp.Compare(x.Path, y.Path), cmp.Compare(x.Message, y.Message))
	})
	return slices.Compact(issues)
}

// collectIssues gathers the leaves of the validator's error tree. Inner nodes only say that a subschema failed; the leaves say what is wrong and where.
func collectIssues(unit *jsonschema.OutputUnit, issues *[]validationIssue) {
	if len(unit.Errors) == 0 {
		if unit.Error != nil {
			*issues = append(*issues, validationIssue{Path: unit.InstanceLocation, Message: unit.Error.String()})
		}
		return
	}
	for i := range unit.Errors {
		collectIssues(&unit.Errors[i], issues)
	}
}

func writeIssues(w io.Writer, issues []validationIssue) error {
	for _, issue := range issues {
		path := issue.Path
		if path == "" {
			path = "(document)"
		}
		if _, err := fmt.Fprintf(w, "  %s: %s\n", path, issue.Message); err != nil {
			return err
		}
	}
	return nil
}

func (a *app) dslValidateCommand(schemaDir *string) *cobra.Command {
	var runtime string
	command := &cobra.Command{
		Use:   "validate <file>...",
		Short: "Validate DSL files against the runtime schema",
		Long: `Validate one or more DSL files against the JSON Schema of their runtime. The runtime ref is read from meta.runtime and meta.runtime_version of each file unless --runtime is given.

Exits with status 1 when any file is invalid and lists every violation with its JSON Pointer.`,
		Example: `  classic-games dsl validate apps/client/runtime/shooter/baseline.dsl.json
  classic-games dsl validate --schema-dir packages/schemas --output json my.dsl.json`,
		Args: cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if runtime != "" {
				if _, _, ok := sdk.SplitRuntimeRef(runtime); !ok {
					return fmt.Errorf("invalid --runtime %q: want <name>@<version>, such as shooter@1.0.0", runtime)
				}
			}
			validator, directory, err := a.schemaValidator(*schemaDir)
			if err != nil {
				return err
			}
			report := validationReport{Valid: true, SchemaDir: directory, Results: make([]fileValidation, 0, len(args))}
			failed := 0
			for _, path := range args {
				result := fileValidation{File: path, Runtime: runtime}
				document, err := readDSL(cmd, path)
				// An interrupt while waiting for standard input ends the command; it is not a property of the file.
				if ctxErr := cmd.Context().Err(); ctxErr != nil {
					return ctxErr
				}
				switch {
				case err != nil:
					result.Errors = []validationIssue{{Message: err.Error()}}
				case result.Runtime == "":
					declared, ok := runtimeRefOf(document)
					if !ok {
						result.Errors = []validationIssue{{Path: "/meta", Message: "meta.runtime and meta.runtime_version are missing, so the runtime is unknown: pass --runtime"}}
						break
					}
					result.Runtime = declared
					fallthrough
				default:
					result.Errors = validateDocument(validator, result.Runtime, document)
				}
				result.Valid = len(result.Errors) == 0
				result.Errors = orEmpty(result.Errors)
				if !result.Valid {
					failed++
					report.Valid = false
				}
				report.Results = append(report.Results, result)
			}
			err = a.emit(cmd, report, func(w io.Writer) error {
				for _, result := range report.Results {
					verdict, runtime := "valid", result.Runtime
					if !result.Valid {
						verdict = "invalid"
					}
					if runtime == "" {
						runtime = "unknown runtime"
					}
					if _, err := fmt.Fprintf(w, "%s: %s (%s)\n", displayPath(result.File), verdict, runtime); err != nil {
						return err
					}
					if err := writeIssues(w, result.Errors); err != nil {
						return err
					}
				}
				return nil
			})
			if err != nil {
				return err
			}
			if failed > 0 {
				return fmt.Errorf("%d of %d file(s) failed validation", failed, len(args))
			}
			return nil
		},
	}
	command.Flags().StringVar(&runtime, "runtime", "", "runtime ref to validate against, such as shooter@1.0.0 (default: read from each file's meta)")
	return command
}

func (a *app) dslPatchCommand(schemaDir *string) *cobra.Command {
	var (
		out      string
		validate bool
		runtime  string
	)
	command := &cobra.Command{
		Use:   "patch <base.json> <patch.json>",
		Short: "Apply an RFC 6902 JSON Patch to a DSL file",
		Long: `Apply an RFC 6902 JSON Patch to a DSL file and print the result. The base file is not modified.

Supported operations are add, replace, remove and test; move and copy are rejected, as on the backend and in the client. The first failing operation aborts the patch. Object keys of the result are sorted, which makes the output a canonical form.

With --validate the result is also checked against the runtime schema, and nothing is written when it is invalid. One of the two files may be - for standard input.`,
		Example: `  classic-games dsl patch baseline.dsl.json patch.json -o modded.dsl.json
  classic-games dsl patch baseline.dsl.json patch.json --validate`,
		Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			if args[0] == stdioPath && args[1] == stdioPath {
				return errors.New("only one of the base and the patch can be read from standard input")
			}
			if runtime != "" && !validate {
				return errors.New("--runtime only applies together with --validate")
			}
			base, err := readDSL(cmd, args[0])
			if err != nil {
				return err
			}
			ops, err := readPatch(cmd, args[1])
			if err != nil {
				return err
			}
			patched, err := applyPatch(base, ops)
			if err != nil {
				return fmt.Errorf("the patch does not apply to %s: %w", displayPath(args[0]), err)
			}
			if validate {
				ref := runtime
				if ref == "" {
					declared, ok := runtimeRefOf(patched)
					if !ok {
						return errors.New("the patched DSL declares no meta.runtime and meta.runtime_version: pass --runtime")
					}
					ref = declared
				}
				validator, _, err := a.schemaValidator(*schemaDir)
				if err != nil {
					return err
				}
				if issues := validateDocument(validator, ref, patched); len(issues) > 0 {
					var details strings.Builder
					if err := writeIssues(&details, issues); err != nil {
						return err
					}
					return fmt.Errorf("the patched DSL is not valid for %s; nothing was written:\n%s", ref, strings.TrimRight(details.String(), "\n"))
				}
			}
			return a.emitDocument(cmd, out, patched)
		},
	}
	flags := command.Flags()
	flags.StringVarP(&out, "out", "o", "", "write the patched DSL to this file instead of standard output")
	flags.BoolVar(&validate, "validate", false, "validate the patched DSL against the runtime schema")
	flags.StringVar(&runtime, "runtime", "", "runtime ref for --validate (default: read from the patched DSL's meta)")
	return command
}

// applyPatch applies ops one at a time so a failure can name the operation that caused it; dsl.Apply itself only reports the reason. The result equals one dsl.Apply call over the whole patch, because Apply is sequential and never mutates its input.
func applyPatch(document map[string]any, ops []dsl.Op) (map[string]any, error) {
	if len(ops) == 0 {
		return dsl.Apply(document, ops)
	}
	for i, op := range ops {
		next, err := dsl.Apply(document, []dsl.Op{op})
		if err != nil {
			return nil, fmt.Errorf("operation %d (%s %q): %w", i, op.Op, op.Path, err)
		}
		document = next
	}
	return document, nil
}

func (a *app) dslMigrateCommand() *cobra.Command {
	var (
		out  string
		from string
		to   string
	)
	command := &cobra.Command{
		Use:   "migrate <file>",
		Short: "Upgrade a DSL file written for an older runtime version",
		Long: `Upgrade a DSL file to a newer runtime version and print the result. The input file is not modified.

The only migration path that exists is shooter 0.x to shooter 1.x: it rewrites meta, turns a string weapon into a weapon object, defaults player.size and converts array-form enemies and drops into id-keyed maps. Any other request fails.

The source runtime ref is read from meta.runtime and meta.runtime_version unless --from is given; legacy files often lack them.`,
		Example: `  classic-games dsl migrate old.dsl.json --from shooter@0.9.0 --to 1.0.0 -o new.dsl.json`,
		Args:    cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			document, err := readDSL(cmd, args[0])
			if err != nil {
				return err
			}
			source := from
			if source == "" {
				declared, ok := runtimeRefOf(document)
				if !ok {
					return fmt.Errorf("%s declares no meta.runtime and meta.runtime_version: pass --from, such as --from shooter@0.9.0", displayPath(args[0]))
				}
				source = declared
			}
			if _, _, ok := sdk.SplitRuntimeRef(source); !ok {
				return fmt.Errorf("invalid source runtime %q: want <name>@<version>, such as shooter@0.9.0", source)
			}
			target, migrated, err := dsl.Migrate(source, to, document)
			if err != nil {
				return fmt.Errorf("cannot migrate %s from %s to version %s: %w", displayPath(args[0]), source, to, err)
			}
			if _, err := fmt.Fprintf(cmd.ErrOrStderr(), "Migrated %s from %s to %s\n", displayPath(args[0]), source, target); err != nil {
				return err
			}
			return a.emitDocument(cmd, out, migrated)
		},
	}
	flags := command.Flags()
	flags.StringVarP(&out, "out", "o", "", "write the migrated DSL to this file instead of standard output")
	flags.StringVar(&from, "from", "", "source runtime ref, such as shooter@0.9.0 (default: read from the file's meta)")
	flags.StringVar(&to, "to", "", "target version, such as 1.0.0")
	_ = command.MarkFlagRequired("to")
	return command
}
