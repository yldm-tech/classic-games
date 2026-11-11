# Assets of `survivor`

Every file in this directory that is not code or the manifest, with where it came from and the licence it is distributed under.

| File | What it is | Source | Licence |
|---|---|---|---|
| `key_art.jpg` | 16:9 key art (1920x1080) shown by the launcher and the website | Generated for this project with the image model `doubao-seedream-5.0-pro` from a prompt written for it; an original composition that depicts no character or artwork of any existing game | Distributed with the project under Apache-2.0. AI-generated images may not be protected by copyright in some jurisdictions; judge for yourself before reusing it |
| `site_screenshot.png` | A 1920x1080 capture of this game being played in the launcher, shown on the website. It is not shipped in the game: the export presets exclude it | Captured from this project's own launcher with `scripts/run-launcher-shot.sh` | Apache-2.0, with the project |

This game has no audio files and no other bundled assets. It runs on the built-in `survivor` DSL runtime (`apps/client/runtime/survivor/`), which draws with code.
