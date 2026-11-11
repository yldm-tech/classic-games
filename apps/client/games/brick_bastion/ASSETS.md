# Assets of `brick_bastion`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played in the launcher, shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

Everything else the game shows or plays is code. The pixel art (rovers, raiders, both bosses, the beacon, supply chips, tiles, ground, panels) is written in `sprites.gd` as rows of palette letters and small painting rules and in `render.gd`, drawn for this project; particles and weather are drawn by `fx.gd`. Every sound effect and the three tunes are synthesised at run time by `games/shared/game_audio.gd` from the specifications in `sounds.gd`, which were composed for this project. There are no audio files and no fonts: text uses the system font.
