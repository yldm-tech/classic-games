package cli

import (
	"errors"
	"fmt"
	"io"

	"forgeplay/sdk"

	"github.com/spf13/cobra"
)

func (a *app) modsCommand() *cobra.Command {
	return group("mods", "Create, fork, inspect and publish mods",
		a.modsListCommand(),
		a.modsCreateCommand(),
		a.modsForkCommand(),
		a.modsSaveCommand(),
		a.modsShowCommand(),
		a.modsDSLCommand(),
		a.modsLineageCommand(),
		a.modsPublishCommand(),
	)
}

func writeModTable(w io.Writer, mods []sdk.Mod) error {
	rows := make([][]string, len(mods))
	for i, mod := range mods {
		rows[i] = []string{mod.ID, mod.Runtime, mod.ParentID, formatInt(len(mod.Patch)), formatBool(mod.Draft), formatBool(mod.AIGenerated), formatTime(mod.CreatedAt)}
	}
	return writeTable(w, []string{"ID", "RUNTIME", "PARENT", "OPS", "DRAFT", "AI", "CREATED"}, rows)
}

func writePatchTable(w io.Writer, patch []sdk.PatchOp) error {
	rows := make([][]string, len(patch))
	for i, op := range patch {
		rows[i] = []string{op.Op, op.Path, string(op.Value)}
	}
	return writeTable(w, []string{"OP", "PATH", "VALUE"}, rows)
}

func (a *app) emitMod(cmd *cobra.Command, mod *sdk.Mod, headline string) error {
	mod.Patch = orEmpty(mod.Patch)
	return a.emit(cmd, mod, func(w io.Writer) error {
		if headline != "" {
			if _, err := fmt.Fprintln(w, headline); err != nil {
				return err
			}
		}
		err := writeFields(w, []field{
			{"ID", mod.ID},
			{"Runtime", mod.Runtime},
			{"Parent", mod.ParentID},
			{"Author", mod.AuthorID},
			{"Draft", formatBool(mod.Draft)},
			{"AI generated", formatBool(mod.AIGenerated)},
			{"Created", formatTime(mod.CreatedAt)},
			{"Patch operations", formatInt(len(mod.Patch))},
		})
		if err != nil || len(mod.Patch) == 0 {
			return err
		}
		if _, err := fmt.Fprintln(w); err != nil {
			return err
		}
		return writePatchTable(w, mod.Patch)
	})
}

func (a *app) modsListCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List your draft mods, newest first",
		Long:  "List your draft mods, newest first. The backend lists drafts only: a mod created with --draft=false or a draft that was published is reached through 'forgeplay games mine' and the game's mod id.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mods, err := current.client.ListDrafts(cmd.Context())
			if err != nil {
				return err
			}
			mods = orEmpty(mods)
			for i := range mods {
				mods[i].Patch = orEmpty(mods[i].Patch)
			}
			return a.emit(cmd, itemList[sdk.Mod]{Items: mods}, func(w io.Writer) error {
				return writeModTable(w, mods)
			})
		},
	}
}

func (a *app) modsCreateCommand() *cobra.Command {
	var (
		request   sdk.CreateModRequest
		patchPath string
	)
	command := &cobra.Command{
		Use:   "create",
		Short: "Create a mod from a patch file",
		Long: `Create a mod: a JSON Patch relative to the runtime baseline (--runtime) or to the effective DSL of another mod (--parent). Requires a login.

The backend stores the patch without applying it. Run 'forgeplay mods dsl <id>' afterwards to confirm the patch applies, or check it offline first with 'forgeplay dsl patch --validate'.`,
		Example: `  forgeplay mods create --runtime shooter@1.0.0 --patch patch.json
  forgeplay mods create --parent <mod-id> --patch - < patch.json`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if (request.Runtime == "") == (request.ParentID == "") {
				return errors.New("pass exactly one of --runtime (a root mod on the runtime baseline) or --parent (a child of an existing mod)")
			}
			if request.Runtime != "" {
				if _, _, ok := sdk.SplitRuntimeRef(request.Runtime); !ok {
					return fmt.Errorf("invalid --runtime %q: want <name>@<version>, such as shooter@1.0.0", request.Runtime)
				}
			}
			request.Patch = []sdk.PatchOp{}
			if patchPath != "" {
				ops, err := readPatch(cmd, patchPath)
				if err != nil {
					return err
				}
				request.Patch = toSDKPatch(ops)
			}
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mod, err := current.client.CreateMod(cmd.Context(), request)
			if err != nil {
				return err
			}
			return a.emitMod(cmd, mod, fmt.Sprintf("Created mod %s", mod.ID))
		},
	}
	flags := command.Flags()
	flags.StringVar(&request.Runtime, "runtime", "", "runtime ref of a root mod, such as shooter@1.0.0")
	flags.StringVar(&request.ParentID, "parent", "", "id of the mod to build on")
	flags.StringVar(&patchPath, "patch", "", "JSON Patch file (- for standard input); omitted means an empty patch")
	flags.BoolVar(&request.Draft, "draft", true, "create a draft that can be saved again and published; --draft=false creates a final mod")
	flags.StringVar(&request.AIProvenance, "provenance", "", "provenance value from 'forgeplay ai generate --output json', which marks the mod as AI-generated")
	return command
}

func (a *app) modsForkCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "fork <mod-id>",
		Short: "Fork a mod into a draft you own",
		Long:  "Create a draft child with an empty patch, so its effective DSL starts equal to the forked mod. Requires a login.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mod, err := current.client.ForkMod(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitMod(cmd, mod, fmt.Sprintf("Forked mod %s into draft mod %s", args[0], mod.ID))
		},
	}
}

func (a *app) modsSaveCommand() *cobra.Command {
	var patchPath string
	command := &cobra.Command{
		Use:   "save <draft-id>",
		Short: "Save a new version of a draft",
		Long:  "Drafts are immutable versions: this creates a new draft whose parent is <draft-id> and whose patch is relative to that draft's effective DSL. Keep working with the id that is printed. Requires a login.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ops, err := readPatch(cmd, patchPath)
			if err != nil {
				return err
			}
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mod, err := current.client.SaveDraft(cmd.Context(), args[0], toSDKPatch(ops))
			if err != nil {
				return err
			}
			return a.emitMod(cmd, mod, fmt.Sprintf("Saved draft %s as new draft %s", args[0], mod.ID))
		},
	}
	command.Flags().StringVar(&patchPath, "patch", "", "JSON Patch file relative to the draft's effective DSL (- for standard input)")
	_ = command.MarkFlagRequired("patch")
	return command
}

func (a *app) modsShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show <mod-id>",
		Short: "Show one mod and its patch",
		Long:  "Show one mod and its patch. Drafts are readable by their author only.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			mod, err := current.client.GetMod(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitMod(cmd, mod, "")
		},
	}
}

func (a *app) modsDSLCommand() *cobra.Command {
	var out string
	command := &cobra.Command{
		Use:   "dsl <mod-id>",
		Short: "Print the effective DSL of a mod as JSON",
		Long:  "Print the effective DSL of a mod: the runtime baseline with every patch from the root mod down to this one applied. Fails with DSL_INVALID when the patch chain does not apply. The document is JSON in both output modes.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			document, err := current.client.GetModDSL(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitDocument(cmd, out, document)
		},
	}
	command.Flags().StringVarP(&out, "out", "o", "", "write the DSL to this file instead of standard output")
	return command
}

func (a *app) modsLineageCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "lineage <mod-id>",
		Short: "List the chain of mods from the root down to a mod",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			mods, err := current.client.GetModLineage(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			mods = orEmpty(mods)
			for i := range mods {
				mods[i].Patch = orEmpty(mods[i].Patch)
			}
			return a.emit(cmd, itemList[sdk.Mod]{Items: mods}, func(w io.Writer) error {
				return writeModTable(w, mods)
			})
		},
	}
}

func (a *app) modsPublishCommand() *cobra.Command {
	var (
		title       string
		summary     string
		tags        []string
		category    string
		forkedFrom  string
		aiGenerated bool
	)
	command := &cobra.Command{
		Use:   "publish <mod-id>",
		Short: "Submit a mod as a game",
		Long: `Submit a mod as a game. The game starts in status "reviewing" and becomes public once a moderator approves it. Requires a login as the mod's author.

A draft is published through its draft endpoint, which also clears the draft flag so other users can fork the result; a final mod is published directly.`,
		Example: `  forgeplay mods publish <mod-id> --title "Cat Shooter" --summary "The player is a cat" --tag cat --tag shooter`,
		Args:    idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(tags) > 3 {
				return fmt.Errorf("a game takes at most 3 tags, got %d", len(tags))
			}
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mod, err := current.client.GetMod(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			var game *sdk.Game
			if mod.Draft {
				game, err = current.client.PublishDraft(cmd.Context(), mod.ID, sdk.PublishDraftRequest{Title: title, Summary: summary, Tags: tags, Category: category, ForkedFrom: forkedFrom, AIGenerated: aiGenerated})
			} else {
				game, err = current.client.PublishGame(cmd.Context(), sdk.PublishGameRequest{ModID: mod.ID, Title: title, Summary: summary, Tags: tags, Category: category, ForkedFrom: forkedFrom, AIGenerated: aiGenerated})
			}
			if err != nil {
				return err
			}
			return a.emitGame(cmd, game, fmt.Sprintf("Submitted mod %s as game %s (status %s)", mod.ID, game.ID, game.Status))
		},
	}
	flags := command.Flags()
	flags.StringVar(&title, "title", "", "game title")
	flags.StringVar(&summary, "summary", "", "one-line description")
	flags.StringSliceVar(&tags, "tag", nil, "tag, repeatable, at most 3")
	flags.StringVar(&category, "category", "", "catalog category")
	flags.StringVar(&forkedFrom, "forked-from", "", "id of the game this work was forked from")
	flags.BoolVar(&aiGenerated, "ai-generated", false, "declare AI involvement (the backend forces this for mods with a valid provenance mark)")
	_ = command.MarkFlagRequired("title")
	return command
}
