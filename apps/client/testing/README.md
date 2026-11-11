# apps/client/testing

Test-only material for the game module contract. Nothing here is shipped: every export preset excludes `testing/*`, and the launcher's catalog only reads `games/`.

| Path | What it is |
|---|---|
| `games/fixture_duo/` | The fixture module: the smallest game that uses the whole contract (two players, a scrolling stage, a countdown, lives, a boss, options, procedural sound). It has a manifest, an `ASSETS.md` and its own test, like a shipped game |
| `games/fixture_arena/` | A second fixture for what the first one lacks: a single seat, a smooth (not pixel-art) stage, analogue movement, a run that ends when the arena is cleared, and achievements that read fields `finish()` adds to the result. It was written from `docs/20-adding-a-game.md` alone, as a check of that guide |
| `games/fixture_gallery/` | A third fixture for high-resolution art and recorded audio: a sprite atlas with a frame table and an animation, a tiled texture, smooth text, a looping music file, a stinger that ducks the music, a sound effect from a file and effects from the preset library. Its media were made with `scripts/assets/` and are recorded in its `ASSETS.md`. The export check loads and plays it from inside an exported pack |
| `unfit_games/` | Directories with a valid manifest and exactly one thing wrong with the directory (no test, a test in a sub-directory, no `ASSETS.md`, an unlisted asset, an entry script with its own `_process`, an entry that is not a `GameModule`, a HUD field the snapshot lacks, one seat reported by a two-seat game, a missing website screenshot, an asset file over the size limit and a directory over its media budget, audio in a format that cannot loop cleanly, an image without mipmaps on a stage that is not pixel art). The `*_test.gd` files in them are never run; they exist so each directory has only the problem it is named after |
| `broken_games/` | Manifests that are wrong on purpose (unreadable JSON, a missing manifest, a manifest of the wrong shape) |
| `mixed_games/` | One valid game next to one broken one, to check that the launcher offers the first and reports the second |
| `module_contract_test.gd` | The contract as a host sees it, through `GameSession` |
| `module_flow_test.gd` | The contract as a player sees it, through the launcher: the game menu's player row, the HUD's second corner, per-player input and pause ownership |
| `media_test.gd` | The shared support for recorded audio and high-resolution art (`GameAudio` tracks, cross-fades, stingers and file effects; `GameSprites` atlases, frames, animations and drawing; `GameText`), against the media of `games/fixture_gallery/` |
| `manifest_check_test.gd` | The manifest check (`make games-check`) itself, run as a child process on `unfit_games/` and on `games/`: every kind of unfit directory must fail with a line that says why |

`make games-test` runs every `*_test.gd` here and under `games/*/`. `make games-check` validates the games under `games/` with the same rules as a shipped game. See [docs/20-adding-a-game.md](../../../docs/20-adding-a-game.md).
