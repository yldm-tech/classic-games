package cli

import (
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/spf13/cobra"
)

func (a *app) aiCommand() *cobra.Command {
	return group("ai", "Generate Mod DSL patches with the backend AI",
		a.aiGenerateCommand(),
		a.aiQuotaCommand(),
	)
}

// generationBase is the DSL a prompt is applied to, and where a saved result attaches in the mod graph.
type generationBase struct {
	runtime string
	dsl     map[string]any
	// parentID is the mod whose effective DSL equals dsl; empty means the runtime baseline.
	parentID    string
	description string
}

type generateOptions struct {
	runtime  string
	gameID   string
	modID    string
	dslPath  string
	save     bool
	patchOut string
	dslOut   string
}

// generateReport is the JSON shape of "ai generate": the backend response plus the runtime it was generated for and the draft it was saved as.
type generateReport struct {
	Runtime string `json:"runtime"`
	*sdk.GenerateModResponse
	SavedMod *sdk.Mod `json:"saved_mod,omitempty"`
}

func (a *app) aiGenerateCommand() *cobra.Command {
	var options generateOptions
	command := &cobra.Command{
		Use:   "generate <prompt>",
		Short: "Turn a natural-language request into a DSL patch",
		Long: `Ask the backend AI to change a DSL. The model only returns an RFC 6902 JSON Patch; the backend applies it and validates the result against the runtime schema before answering, so a returned patch is known to produce a valid DSL.

The DSL to change is chosen by one of:
  --runtime <ref>   the runtime baseline, such as shooter@1.0.0
  --game <id>       the effective DSL of a game
  --mod <id>        the effective DSL of a mod
  --dsl <file>      a local DSL file (its runtime is read from meta, or given with --runtime)

Nothing is stored unless --save is passed, which creates a draft mod holding the patch (requires a login; not available with --dsl). The draft carries the AI-generated mark only when the backend signs its results, which needs CLASSIC_GAMES_SECRET on the backend; the "AI generated mark" line of the output says whether it does.

Each call counts against the daily AI quota (see 'classic-games ai quota'). On a backend in stub mode the answer is a fixed patch per runtime.`,
		Example: `  classic-games ai generate "turn the player into a cat" --runtime shooter@1.0.0
  classic-games ai generate "double the boss health" --game <game-id> --save
  classic-games ai generate "more enemies" --dsl my.dsl.json --patch-out patch.json`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return a.runGenerate(cmd, args[0], options)
		},
	}
	flags := command.Flags()
	flags.StringVar(&options.runtime, "runtime", "", "runtime ref, such as shooter@1.0.0")
	flags.StringVar(&options.gameID, "game", "", "start from the effective DSL of this game")
	flags.StringVar(&options.modID, "mod", "", "start from the effective DSL of this mod")
	flags.StringVar(&options.dslPath, "dsl", "", "start from this local DSL file (- for standard input)")
	flags.BoolVar(&options.save, "save", false, "store the patch as a draft mod")
	flags.StringVar(&options.patchOut, "patch-out", "", "write the generated patch to this file")
	flags.StringVar(&options.dslOut, "dsl-out", "", "write the resulting DSL to this file")
	command.MarkFlagsMutuallyExclusive("game", "mod", "dsl")
	command.MarkFlagsMutuallyExclusive("runtime", "game")
	command.MarkFlagsMutuallyExclusive("runtime", "mod")
	command.MarkFlagsMutuallyExclusive("save", "dsl")
	return command
}

func (a *app) runGenerate(cmd *cobra.Command, prompt string, options generateOptions) error {
	if prompt == "" {
		return errors.New("the prompt is empty")
	}
	if options.runtime == "" && options.gameID == "" && options.modID == "" && options.dslPath == "" {
		return errors.New("choose the DSL to change: pass --runtime, --game, --mod or --dsl")
	}
	if options.runtime != "" {
		if _, _, ok := sdk.SplitRuntimeRef(options.runtime); !ok {
			return fmt.Errorf("invalid --runtime %q: want <name>@<version>, such as shooter@1.0.0", options.runtime)
		}
	}
	// A login is checked before the model is called, so a missing session does not cost a quota unit.
	connect := a.connect
	if options.save {
		connect = a.connectSignedIn
	}
	current, err := connect()
	if err != nil {
		return err
	}
	ctx := cmd.Context()
	base, err := resolveGenerationBase(ctx, cmd, current.client, options)
	if err != nil {
		return err
	}

	response, err := current.client.GenerateMod(ctx, sdk.GenerateModRequest{Runtime: base.runtime, CurrentDSL: base.dsl, Prompt: prompt})
	if err != nil {
		return err
	}
	response.DSLPatch = orEmpty(response.DSLPatch)
	report := generateReport{Runtime: base.runtime, GenerateModResponse: response}

	// A failed write or save must not hide a result that already cost a quota unit: the report is printed first and the errors are returned after it.
	var patchOutErr, dslOutErr, saveErr error
	if options.patchOut != "" {
		patchOutErr = writeDocumentFile(options.patchOut, response.DSLPatch)
	}
	if options.dslOut != "" {
		dslOutErr = writeDocumentFile(options.dslOut, response.NewDSL)
	}
	if options.save {
		request := sdk.CreateModRequest{ParentID: base.parentID, Patch: response.DSLPatch, AIProvenance: response.Provenance, Draft: true}
		if base.parentID == "" {
			request.Runtime = base.runtime
		}
		saved, err := current.client.CreateMod(ctx, request)
		if err != nil {
			saveErr = fmt.Errorf("the patch was generated but could not be saved as a draft: %w", err)
		} else {
			saved.Patch = orEmpty(saved.Patch)
			report.SavedMod = saved
		}
	}

	err = a.emit(cmd, report, func(w io.Writer) error {
		if _, err := fmt.Fprintf(w, "Generated a patch with %d operation(s) for %s, based on %s\n", len(response.DSLPatch), base.runtime, base.description); err != nil {
			return err
		}
		fields := []field{
			{"Model", response.Model},
			{"Retries", formatInt(response.Retries)},
			{"Tokens", fmt.Sprintf("%d prompt, %d completion", response.Tokens.Prompt, response.Tokens.Completion)},
			{"Schema check", "passed on the server"},
			{"Balance hint", response.BalanceHint},
		}
		if report.SavedMod != nil {
			fields = append(fields, field{"Saved as", "draft mod " + report.SavedMod.ID}, field{"AI generated mark", formatBool(report.SavedMod.AIGenerated)})
		}
		if options.patchOut != "" && patchOutErr == nil {
			fields = append(fields, field{"Patch written to", options.patchOut})
		}
		if options.dslOut != "" && dslOutErr == nil {
			fields = append(fields, field{"DSL written to", options.dslOut})
		}
		if err := writeFields(w, fields); err != nil {
			return err
		}
		if len(response.DSLPatch) == 0 {
			return nil
		}
		if _, err := fmt.Fprintln(w); err != nil {
			return err
		}
		return writePatchTable(w, response.DSLPatch)
	})
	if err != nil {
		return err
	}
	return errors.Join(patchOutErr, dslOutErr, saveErr)
}

func resolveGenerationBase(ctx context.Context, cmd *cobra.Command, client *sdk.Client, options generateOptions) (*generationBase, error) {
	switch {
	case options.gameID != "":
		game, err := client.GetGame(ctx, options.gameID)
		if err != nil {
			return nil, err
		}
		document, err := client.GetGameDSL(ctx, options.gameID)
		if err != nil {
			return nil, err
		}
		return &generationBase{runtime: game.Runtime, dsl: document, parentID: game.ModID, description: "game " + game.ID}, nil
	case options.modID != "":
		mod, err := client.GetMod(ctx, options.modID)
		if err != nil {
			return nil, err
		}
		document, err := client.GetModDSL(ctx, options.modID)
		if err != nil {
			return nil, err
		}
		return &generationBase{runtime: mod.Runtime, dsl: document, parentID: mod.ID, description: "mod " + mod.ID}, nil
	case options.dslPath != "":
		document, err := readDSL(cmd, options.dslPath)
		if err != nil {
			return nil, err
		}
		runtime := options.runtime
		if runtime == "" {
			declared, ok := runtimeRefOf(document)
			if !ok {
				return nil, fmt.Errorf("%s declares no meta.runtime and meta.runtime_version: pass --runtime", displayPath(options.dslPath))
			}
			runtime = declared
		}
		return &generationBase{runtime: runtime, dsl: document, description: displayPath(options.dslPath)}, nil
	default:
		name, version, _ := sdk.SplitRuntimeRef(options.runtime)
		document, err := client.GetRuntimeBaseline(ctx, name, version)
		if err != nil {
			return nil, err
		}
		return &generationBase{runtime: options.runtime, dsl: document, description: "the runtime baseline"}, nil
	}
}

func (a *app) aiQuotaCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "quota",
		Short: "Show today's AI generation allowance",
		Long:  "Show today's AI generation allowance. Reading it never consumes it. Accounts created with SMS or password login are metered per account; guests and anonymous callers are metered per client IP.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			quota, err := current.client.AIQuota(cmd.Context())
			if err != nil {
				return err
			}
			return a.emit(cmd, quota, func(w io.Writer) error {
				return writeFields(w, []field{
					{"Used", formatInt(quota.Used)},
					{"Remaining", formatInt(quota.Remaining)},
					{"Daily limit", formatInt(quota.Limit)},
				})
			})
		},
	}
}
