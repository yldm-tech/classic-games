# scripts/assets

Tools for making the media of a game: pictures and music from a generation service, sprites keyed out of a flat background and packed into an atlas, and audio cut into a seamless loop at one common loudness. The guide for game authors is [docs/20-adding-a-game.md](../../docs/20-adding-a-game.md), section 8; this page is the reference for the commands.

Nothing here is needed to build, run or test the games. The tools are for the people (and agents) who make assets.

## Requirements

- Python 3.10 or newer with Pillow and numpy: `python3 -m pip install -r scripts/assets/requirements.txt`. Everything else is the standard library.
- For `audio` and for `inspect` on audio files: `ffmpeg` and `ffprobe` (decoding and EBU R128 loudness measurement) and one Ogg Vorbis encoder: an `ffmpeg` built with libvorbis, or `sox`, or `oggenc` from vorbis-tools. On macOS: `brew install ffmpeg sox`.
- For `image`, `pose` and `music`: an API key in the environment variable `EVERYAPI_KEY`. Set it for the one command that needs it (`EVERYAPI_KEY=$(everyapi token key <id>) python3 scripts/assets/assets.py image ...`) or export it in the shell session; never write it into a file. The tools send it in the request header and nowhere else: it is not printed, not logged and not stored in the provenance file. `EVERYAPI_BASE` overrides the service address.

## Commands

`python3 scripts/assets/assets.py <command> --help` prints every option.

| Command | What it does |
|---|---|
| `image --prompt P --out FILE --log LOG --date YYYY-MM-DD [--size 1024x1024] [--reference PNG] [--transparent]` | One picture from a prompt (model `doubao-seedream-5.0-pro`). The result is an opaque JPEG whatever the extension of `--out`; name it `.jpg`. Use `1920x1080` for a background |
| `pose --reference REF.png --pose "..." --out FILE.png --log LOG --date D [--subject character] [--view "side view"] [--prompt FULL]` | Another pose of the character in `REF.png`, which must be an RGBA PNG with transparent pixels (the keyed base pose). The result keeps the design and comes back as an RGBA PNG with real transparency |
| `key IN OUT.png [--color auto] [--tolerance 0.10] [--softness 0.10] [--despill 1] [--shrink 1] [--feather 0.6]` | Turns a flat background colour into transparency: the key colour is read from the picture's border, the edge is pulled in and softened, specks are removed, the key colour is taken out of partly transparent pixels and its tint off the rim of the subject |
| `pack FRAMES... --out DIR/NAME [--height H --height-of FRAME \| --scale S] [--max-frame N] [--pivot bottom] [--anchor content\|frame] [--no-trim] [--padding 2] [--extrude 0] [--max-size 2048] [--fps NAME=FPS] [--default-fps 10] [--once NAME]` | Trims frames and packs them into `NAME.png` with the frame table `NAME.json` that `GameSprites.load_atlas` reads. A frame is named after its file; `name_0`, `name_1`, ... become the animation `name` |
| `fit IN OUT [--size WxH] [--mode cover\|stretch] [--quality 88]` | Sizes an opaque picture and saves it by extension: `.jpg`, `.webp` or `.png` |
| `tile IN OUT [--blend 0.15] [--size WxH] [--quality 88]` | Makes a texture repeat seamlessly by cross-fading its opposite edges into each other |
| `music --prompt P --out FILE.mp3 --log LOG --date D [--seconds 60]` | One piece of music from a prompt (model `music_v2_5`), as MP3. Say "instrumental, no vocals" |
| `audio IN OUT.ogg [--kind music\|stinger\|sfx] [--loop] [--start S] [--end S] [--loop-seconds S] [--crossfade 2] [--lufs L] [--quality Q] [--mono]` | The whole path from a generated or recorded file to the Ogg Vorbis a game ships; prints a JSON report |
| `inspect FILES...` | Facts as JSON: for a picture its size, mode, alpha range and content box; for an audio file its length, loudness (LUFS), peak (dBFS) and how clean the jump from its end to its start is |

## Notes on the generation commands

- Every generation appends one JSON line to the file given as `--log`: `date` (the `--date` argument), `kind` (`image`, `pose` or `music`), `model`, the full `prompt`, `output`, the `sha256` of the result, and `size` or `seconds`, plus `reference` when one was used. Keep the log with the raw generations, outside the repository, and write the game's `ASSETS.md` from it.
- Requests that fail with a rate limit or a server error (HTTP 429, 5xx) are retried up to four times with a growing pause, and every retry is announced on stderr. Pose requests are the slow ones and the gateway in front of the model answers 504 when one takes longer than about 80 seconds; when that happens repeatedly, wait and run the command again rather than starting several at once. Run generation commands one after another, never more than three at the same time.
- Look at every generated picture before using it. Regenerate on extra limbs, a changed design, a cropped figure, text or a watermark in the picture, or a fringe of the key colour that `key` could not remove.
- A subject with a glow or a soft halo drags the key colour into itself; say "no glow" in the prompt, and raise `--tolerance` (0.2 to 0.25) when a halo is left.
- Prompts describe the project's own designs only. Never name an existing game, franchise, character, studio or artist, never ask for something that looks or sounds like a specific existing work, and never pass somebody else's picture as `--reference` ([ADR-016](../../docs/decisions.md)).

## What `audio` does

1. Decodes the input to 44.1 kHz stereo. With `--mono` it is mixed down first, so that loudness is measured on what will be heard.
2. `--kind music --loop`: skips a silent lead-in, finds where the ending of the piece begins (a fade-out or a last chord) and uses the music before it, chooses a loop length at which the music after the loop point matches the music at the start (the same notes on the same beats, so a whole number of bars), and fades the two seconds after the loop over the loop's own beginning. `--start`, `--end` and `--loop-seconds` replace each of those choices; `--crossfade` sets the length of the blend. Without `--loop`, and for the other kinds, silence is trimmed from both ends and short fades are applied.
3. Measures integrated loudness (EBU R128, with ffmpeg) and applies one constant gain: to -18 LUFS for music, -16 LUFS for a stinger (`--lufs` overrides), or to a peak of -3 dBFS for `--kind sfx` and for clips too short to measure. The gain is held back where it would push the peak above -1 dBFS; the report says by how much. A constant gain, not a dynamic normaliser, because anything that treats the start of a loop differently from its end brings the seam back.
4. Encodes Ogg Vorbis with libvorbis at VBR quality 5 (about 160 kbit/s in stereo; 4 for `sfx`; `--quality` overrides).

The report: `loop_seconds`, `loop_similarity` (how well the music after the loop point matches the start; near 1 is a repeating phrase, below about 0.3 the piece has none and the loop point should be set by hand), `seam_ratio` (the jump from the last sample to the first, relative to the ordinary movement of the signal; around 1 is inaudible), `lufs`, `peak_db`, `gain_db`, `gain_held_back_db`, `seconds`, `bytes`, `encoder`.

## Tests

`make assets-test` runs `test_assets.py`: keying, packing, the seamless tile, loop finding and folding, gain and loudness, and that the key is read from the environment only. It calls no generation endpoint. The two tests that encode audio are skipped on a machine without ffmpeg and an Ogg Vorbis encoder.
