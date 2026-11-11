# apps/client/testing

Test-only material for the game module contract. Nothing here is shipped: every export preset excludes `testing/*`, and the launcher's catalog only reads `games/`.

| Path | What it is |
|---|---|
| `games/fixture_duo/` | The fixture module: the smallest game that uses the whole contract (two players, a scrolling stage, a countdown, lives, a boss, options, procedural sound). It has a manifest, an `ASSETS.md` and its own test, like a shipped game |
| `broken_games/` | Manifests that are wrong on purpose (unreadable JSON, a missing manifest, a manifest of the wrong shape) |
| `mixed_games/` | One valid game next to one broken one, to check that the launcher offers the first and reports the second |
| `module_contract_test.gd` | The contract as a host sees it, through `GameSession` |
| `module_flow_test.gd` | The contract as a player sees it, through the launcher: the game menu's player row, the HUD's second corner, per-player input and pause ownership |

`make games-test` runs every `*_test.gd` here and under `games/*/`. `make games-check` validates `games/fixture_duo/` with the same rules as a shipped game. See [docs/20-adding-a-game.md](../../../docs/20-adding-a-game.md).
