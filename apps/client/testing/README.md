# apps/client/testing

Test-only material for the game module contract. Nothing here is shipped: every export preset excludes `testing/*`, and the launcher's catalog only reads `games/`.

| Path | What it is |
|---|---|
| `games/fixture_duo/` | The fixture module: the smallest game that uses the whole contract (two players, a scrolling stage, a countdown, lives, a boss, options, procedural sound). It has a manifest, an `ASSETS.md` and its own test, like a shipped game |
| `games/fixture_arena/` | A second fixture for what the first one lacks: a single seat, a smooth (not pixel-art) stage, analogue movement, a run that ends when the arena is cleared, and achievements that read fields `finish()` adds to the result. It was written from `docs/20-adding-a-game.md` alone, as a check of that guide |
| `unfit_games/` | Directories with a valid manifest and exactly one thing wrong with the directory (no test, a test in a sub-directory, no `ASSETS.md`, an unlisted asset, an entry script with its own `_process`, an entry that is not a `GameModule`, a HUD field the snapshot lacks, one seat reported by a two-seat game, a missing website screenshot). The `*_test.gd` files in them are never run; they exist so each directory has only the problem it is named after |
| `broken_games/` | Manifests that are wrong on purpose (unreadable JSON, a missing manifest, a manifest of the wrong shape) |
| `mixed_games/` | One valid game next to one broken one, to check that the launcher offers the first and reports the second |
| `module_contract_test.gd` | The contract as a host sees it, through `GameSession` |
| `module_flow_test.gd` | The contract as a player sees it, through the launcher: the game menu's player row, the HUD's second corner, per-player input and pause ownership |
| `manifest_check_test.gd` | The manifest check (`make games-check`) itself, run as a child process on `unfit_games/` and on `games/`: every kind of unfit directory must fail with a line that says why |

`make games-test` runs every `*_test.gd` here and under `games/*/`. `make games-check` validates the games under `games/` with the same rules as a shipped game. See [docs/20-adding-a-game.md](../../../docs/20-adding-a-game.md).
