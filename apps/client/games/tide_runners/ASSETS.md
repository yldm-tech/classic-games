# Assets of `tide_runners`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it, describing this game's own divers, city and machines; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played in the launcher, shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

This game has no other asset files. All in-game art is original pixel art authored in code for this project: the sprites are rows of palette characters and painted shapes in `gfx.gd`, the tiles and backdrops are painted by `scenery.gd`, and both become textures at run time. Every sound effect and all four tunes are original, written as data in `sounds.gd` and synthesised at run time by `games/shared/game_audio.gd`.
