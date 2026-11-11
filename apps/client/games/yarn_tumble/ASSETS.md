# Assets of `yarn_tumble`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website: the two knitters, a rolling ball of yarn, four of the tower's pests and Duchess Dustwing | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for this game; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played by two players in the launcher, shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

All in-game art is pixel art written for this project as palette-indexed rows and procedural drawing code in `sprites.gd`, `backdrop.gd` and `view.gd`. All sound is synthesised at run time by `games/shared/game_audio.gd` from the definitions in `sounds.gd`. There are no audio files.
