package cli

import (
	"context"
	"fmt"
	"io"
	"strings"

	"forgeplay/sdk"

	"github.com/spf13/cobra"
)

func (a *app) gamesCommand() *cobra.Command {
	return group("games", "Browse the game catalog and manage your published games",
		a.gamesListCommand(),
		a.gamesShowCommand(),
		a.gamesDSLCommand(),
		a.gamesRankingCommand(),
		a.gamesForkCommand(),
		a.gamesMineCommand(),
		a.gamesDelistCommand(),
		a.gamesResubmitCommand(),
	)
}

func (a *app) gamesListCommand() *cobra.Command {
	var (
		params sdk.ListGamesParams
		ai     bool
		all    bool
	)
	command := &cobra.Command{
		Use:   "list",
		Short: "List published games",
		Long:  "List published games, newest first unless --sort says otherwise. One page is printed; pass the reported cursor to --cursor for the next one, or --all to fetch every page.",
		Example: `  forgeplay games list --runtime shooter --sort hot
  forgeplay games list --query cat --all --output json`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if cmd.Flags().Changed("ai") {
				params.AI = &ai
			}
			if all && params.Cursor != "" {
				return fmt.Errorf("--all starts from the first page and cannot be combined with --cursor")
			}
			current, err := a.connect()
			if err != nil {
				return err
			}
			var games []sdk.Game
			nextCursor := ""
			if all {
				if params.Limit <= 0 {
					params.Limit = sdk.MaxPageLimit
				}
				pages := sdk.Paginate(cmd.Context(), func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
					next := params
					next.Cursor = cursor
					return current.client.ListGames(ctx, next)
				})
				for game, err := range pages {
					if err != nil {
						return err
					}
					games = append(games, game)
				}
			} else {
				page, err := current.client.ListGames(cmd.Context(), params)
				if err != nil {
					return err
				}
				games, nextCursor = page.Items, page.NextCursor
			}
			return a.emit(cmd, itemPage[gameView]{Items: viewGames(games), NextCursor: nextCursor}, func(w io.Writer) error {
				if err := writeGameTable(w, games); err != nil {
					return err
				}
				if nextCursor != "" {
					_, err := fmt.Fprintf(w, "\nMore results: --cursor %s\n", nextCursor)
					return err
				}
				return nil
			})
		},
	}
	flags := command.Flags()
	flags.StringVarP(&params.Query, "query", "q", "", "search title, summary, author and tags (case-insensitive substring)")
	flags.StringVar(&params.Sort, "sort", "", "sort order: new (default), hot or rising")
	flags.StringVar(&params.Runtime, "runtime", "", "keep one runtime, by name (shooter) or ref (shooter@1.0.0)")
	flags.StringVar(&params.Category, "category", "", "keep one category")
	flags.BoolVar(&ai, "ai", false, "keep only AI-generated games; --ai=false keeps only the others")
	flags.IntVar(&params.Limit, "limit", 0, fmt.Sprintf("page size, up to %d (server default %d)", sdk.MaxPageLimit, sdk.DefaultPageLimit))
	flags.StringVar(&params.Cursor, "cursor", "", "cursor of the page to fetch, as reported by the previous page")
	flags.BoolVar(&all, "all", false, "fetch every page")
	return command
}

// gameView is the JSON shape of a game in CLI output: the backend fields of sdk.Game with "tags" always present as an array. sdk.Game mirrors the wire format, where a game without tags has no "tags" key at all; the Tags field here is shallower than the embedded one, so encoding/json uses it.
type gameView struct {
	sdk.Game
	Tags []string `json:"tags"`
}

func viewGame(game sdk.Game) gameView {
	return gameView{Game: game, Tags: orEmpty(game.Tags)}
}

// viewGames converts a listing; the result is never nil, so an empty listing is encoded as [].
func viewGames(games []sdk.Game) []gameView {
	views := make([]gameView, len(games))
	for i, game := range games {
		views[i] = viewGame(game)
	}
	return views
}

// rankedGameView is gameView for a leaderboard entry.
type rankedGameView struct {
	sdk.RankedGame
	Tags []string `json:"tags"`
}

// rankingView is the JSON shape of "games ranking".
type rankingView struct {
	Type  string           `json:"type"`
	Items []rankedGameView `json:"items"`
}

func writeGameTable(w io.Writer, games []sdk.Game) error {
	rows := make([][]string, len(games))
	for i, game := range games {
		rows[i] = []string{game.ID, game.Title, game.Runtime, game.By, string(game.Status), formatBool(game.AIGenerated), formatInt(game.Likes), formatInt(game.Plays), formatInt(game.Forks)}
	}
	return writeTable(w, []string{"ID", "TITLE", "RUNTIME", "AUTHOR", "STATUS", "AI", "LIKES", "PLAYS", "FORKS"}, rows)
}

func writeGameDetail(w io.Writer, game *sdk.Game) error {
	return writeFields(w, []field{
		{"ID", game.ID},
		{"Title", game.Title},
		{"Summary", game.Summary},
		{"Status", string(game.Status)},
		{"Runtime", game.Runtime},
		{"Mod", game.ModID},
		{"Author", fmt.Sprintf("%s (%s)", game.By, game.AuthorID)},
		{"Forked from", game.ForkedFrom},
		{"Category", game.Category},
		{"Tags", strings.Join(game.Tags, ", ")},
		{"AI generated", formatBool(game.AIGenerated)},
		{"Created", formatTime(game.CreatedAt)},
		{"Likes", formatInt(game.Likes)},
		{"Plays", formatInt(game.Plays)},
		{"Forks", formatInt(game.Forks)},
		{"Views", formatInt(game.Views)},
	})
}

func (a *app) emitGame(cmd *cobra.Command, game *sdk.Game, headline string) error {
	return a.emit(cmd, viewGame(*game), func(w io.Writer) error {
		if headline != "" {
			if _, err := fmt.Fprintln(w, headline); err != nil {
				return err
			}
		}
		return writeGameDetail(w, game)
	})
}

func (a *app) gamesShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show <game-id>",
		Short: "Show one game",
		Long:  "Show one game. Published games are public; a game that is reviewing, rejected or delisted is visible to its author only.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			game, err := current.client.GetGame(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitGame(cmd, game, "")
		},
	}
}

func (a *app) gamesDSLCommand() *cobra.Command {
	var out string
	command := &cobra.Command{
		Use:   "dsl <game-id>",
		Short: "Print the effective DSL of a game as JSON",
		Long:  "Print the effective DSL of a game: the runtime baseline with the whole patch chain of the game's mod applied. The document is JSON in both output modes.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			document, err := current.client.GetGameDSL(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitDocument(cmd, out, document)
		},
	}
	command.Flags().StringVarP(&out, "out", "o", "", "write the DSL to this file instead of standard output")
	return command
}

func (a *app) gamesRankingCommand() *cobra.Command {
	var params sdk.RankingParams
	command := &cobra.Command{
		Use:   "ranking",
		Short: "Show a leaderboard of published games",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connect()
			if err != nil {
				return err
			}
			ranking, err := current.client.GetRanking(cmd.Context(), params)
			if err != nil {
				return err
			}
			view := rankingView{Type: ranking.Type, Items: make([]rankedGameView, len(ranking.Items))}
			for i, entry := range ranking.Items {
				view.Items[i] = rankedGameView{RankedGame: entry, Tags: orEmpty(entry.Tags)}
			}
			return a.emit(cmd, view, func(w io.Writer) error {
				rows := make([][]string, len(ranking.Items))
				for i, entry := range ranking.Items {
					rows[i] = []string{formatInt(entry.Rank), entry.ID, entry.Title, entry.Runtime, entry.By, formatInt(entry.Likes), formatInt(entry.Plays)}
				}
				return writeTable(w, []string{"RANK", "ID", "TITLE", "RUNTIME", "AUTHOR", "LIKES", "PLAYS"}, rows)
			})
		},
	}
	flags := command.Flags()
	flags.StringVar(&params.Type, "type", "", "ranking type: hot (default), new or rising")
	flags.IntVar(&params.Limit, "limit", 0, "maximum number of entries (0 returns every published game)")
	flags.StringVar(&params.Runtime, "runtime", "", "keep one runtime, by name (shooter) or ref (shooter@1.0.0)")
	flags.StringVar(&params.Category, "category", "", "keep one category (case-sensitive)")
	return command
}

func (a *app) gamesForkCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "fork <game-id>",
		Short: "Fork a game into a draft mod you own",
		Long:  "Create a draft mod whose effective DSL starts equal to the game's. Edit it with 'forgeplay mods save' and release it with 'forgeplay mods publish'. Requires a login.",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			mod, err := current.client.ForkGame(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitMod(cmd, mod, fmt.Sprintf("Forked game %s into draft mod %s", args[0], mod.ID))
		},
	}
}

func (a *app) gamesMineCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "mine",
		Short: "List your own games in every status",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			games, err := current.client.ListMyGames(cmd.Context())
			if err != nil {
				return err
			}
			return a.emit(cmd, itemList[gameView]{Items: viewGames(games)}, func(w io.Writer) error {
				return writeGameTable(w, games)
			})
		},
	}
}

func (a *app) gamesDelistCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "delist <game-id>",
		Short: "Take your own published game offline",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			game, err := current.client.DelistGame(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitGame(cmd, game, fmt.Sprintf("Delisted game %s", game.ID))
		},
	}
}

func (a *app) gamesResubmitCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "resubmit <game-id>",
		Short: "Send your own rejected game back to review",
		Args:  idArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := a.connectSignedIn()
			if err != nil {
				return err
			}
			game, err := current.client.ResubmitGame(cmd.Context(), args[0])
			if err != nil {
				return err
			}
			return a.emitGame(cmd, game, fmt.Sprintf("Resubmitted game %s for review", game.ID))
		},
	}
}
