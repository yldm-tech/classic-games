# Assets of `crate_crew`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it that describes this game's own two robots and workshop; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |

Everything else the game shows is pixel art drawn by its own code: sprites are built at start-up from palette-indexed rows of characters and from small drawing routines in `sprites.gd`, and backgrounds are generated in `backdrops.gd`. All of it was authored for this project and is Apache-2.0 with the project. The game has no audio files: effects and music are synthesised at run time by `games/shared/game_audio.gd` from the note and effect tables in `sounds.gd`, which were written for this project.
