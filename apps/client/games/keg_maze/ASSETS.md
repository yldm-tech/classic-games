# Assets of `keg_maze`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website: two mole miners rolling a powder keg in a timbered tunnel, a crystal-clawed cave creature behind them | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played by two players in the launcher, shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

All in-game art is original pixel art written by hand as rows of palette letters in `sprites.gd` (the fire is painted by a routine in the same file) and turned into textures at run time; no sprite comes from an image file. All sound effects and the four music loops are written as note and effect tables in `sounds.gd` and synthesised by `games/shared/game_audio.gd`; the game ships no audio file.
