# Assets of `ember_trail`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it, describing this game's own lamplighter, ashhorn ram and volcanic highlands; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played in the launcher (the fight with the slag toad), shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

Nothing else here is an asset file. Every in-game picture (the lamplighter, the ashhorn, the creatures, both guardians, tiles, props and backdrops) is built at run time by `art.gd` from the 28 colours in `palette.gd`: the small sprites from rows of palette characters written by hand for this project in `sprite_data.gd`, the rest painted by code. Every sound effect and all four tunes are synthesised at run time by `games/shared/game_audio.gd` from the specs written for this project in `sounds.gd`. All of that is source code under Apache-2.0, with the project.
