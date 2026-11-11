#!/usr/bin/env python3
"""Asset tools for game media: generate pictures and music, key and pack sprites, prepare audio. See README.md in this directory.

  assets.py image   make a picture from a prompt
  assets.py pose    make another pose of a character from its transparent reference picture
  assets.py key     turn a flat background colour into transparency
  assets.py pack    trim frames and pack them into an atlas with a frame table
  assets.py fit     size an opaque picture (background, key art) and save it as JPEG, WebP or PNG
  assets.py tile    make a texture repeat seamlessly
  assets.py music   make a piece of music from a prompt
  assets.py audio   turn a generated or recorded file into the Ogg Vorbis a game ships (loop, loudness)
  assets.py inspect print facts about a picture or an audio file
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import everyapi  # noqa: E402

POSE_PROMPT = "The same {subject} from the reference image, identical design, colours and proportions, same art style, now {pose}. Full body, {view}, isolated on a transparent background, no shadow, no text"
AUDIO_EXTENSIONS = (".ogg", ".mp3", ".wav", ".flac", ".m4a")


def _write(path: str, data: bytes) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


def _size(text: str) -> tuple[int, int]:
    parts = text.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("a size is WIDTHxHEIGHT, like 1920x1080")
    return int(parts[0]), int(parts[1])


def _generated(args: argparse.Namespace, kind: str, prompt: str, data: bytes, extra: dict) -> None:
    _write(args.out, data)
    record = {"date": args.date, "kind": kind, "model": args.model, "prompt": prompt, "output": args.out, "sha256": everyapi.sha256(data), **extra}
    everyapi.log_provenance(args.log, record)
    print("wrote %s (%d bytes); logged to %s" % (args.out, len(data), args.log))


def cmd_image(args: argparse.Namespace) -> int:
    data = everyapi.generate_image(args.prompt, size=args.size, reference=args.reference, transparent=args.transparent, model=args.model)
    extra = {"size": args.size}
    if args.reference:
        extra["reference"] = os.path.basename(args.reference)
    _generated(args, "image", args.prompt, data, extra)
    return 0


def cmd_pose(args: argparse.Namespace) -> int:
    from PIL import Image

    with Image.open(args.reference) as reference:
        if reference.format != "PNG" or "A" not in reference.getbands() or reference.getchannel("A").getextrema()[0] != 0:
            print("pose: the reference must be a PNG with transparent pixels (run `assets.py key` on the base pose first); the model only returns transparency for such a reference", file=sys.stderr)
            return 2
    prompt = args.prompt or POSE_PROMPT.format(subject=args.subject, pose=args.pose, view=args.view)
    data = everyapi.generate_image(prompt, size=args.size, reference=args.reference, transparent=True, model=args.model)
    _generated(args, "pose", prompt, data, {"size": args.size, "reference": os.path.basename(args.reference)})
    return 0


def cmd_key(args: argparse.Namespace) -> int:
    from PIL import Image, ImageColor

    import imaging

    with Image.open(args.input) as source:
        colour = None if args.color == "auto" else ImageColor.getrgb(args.color)[:3]
        used = colour if colour is not None else imaging.border_colour(source)
        out = imaging.key_out(source, colour=colour, tolerance=args.tolerance, softness=args.softness, despill=args.despill, shrink=args.shrink, feather=args.feather)
    imaging.save_picture(out, args.output)
    box = imaging.content_box(out)
    print("wrote %s: key colour #%02x%02x%02x, content box %s of %dx%d" % (args.output, used[0], used[1], used[2], box, out.width, out.height))
    return 0


def cmd_pack(args: argparse.Namespace) -> int:
    from PIL import Image

    import imaging

    frames = []
    for path in args.frames:
        with Image.open(path) as picture:
            frames.append((os.path.splitext(os.path.basename(path))[0], picture.convert("RGBA")))
    fps = {}
    for item in args.fps or []:
        name, _, value = item.partition("=")
        fps[name] = float(value)
    atlas, table = imaging.pack(frames, scale=args.scale, height=args.height, height_of=args.height_of, max_frame=args.max_frame, pivot=imaging.parse_pivot(args.pivot), anchor=args.anchor, trim=not args.no_trim, padding=args.padding, extrude=args.extrude, max_size=args.max_size, fps=fps, default_fps=args.default_fps, once=set(args.once or []))
    image_path, table_path = imaging.write_atlas(atlas, table, args.out)
    print("wrote %s (%dx%d, %d bytes) and %s: %d frames, %d animations, scale %s" % (image_path, atlas.width, atlas.height, os.path.getsize(image_path), table_path, len(table["frames"]), len(table["animations"]), table["scale"]))
    return 0


def cmd_fit(args: argparse.Namespace) -> int:
    from PIL import Image

    import imaging

    with Image.open(args.input) as source:
        out = imaging.fit(source.convert("RGBA" if "A" in source.getbands() else "RGB"), args.size, args.mode) if args.size else source.copy()
    imaging.save_picture(out, args.output, quality=args.quality)
    print("wrote %s (%dx%d, %d bytes)" % (args.output, out.width, out.height, os.path.getsize(args.output)))
    return 0


def cmd_tile(args: argparse.Namespace) -> int:
    from PIL import Image

    import imaging

    with Image.open(args.input) as source:
        out = imaging.make_seamless(source, blend=args.blend)
    if args.size:
        out = imaging.fit(out, args.size, "stretch")
    imaging.save_picture(out, args.output, quality=args.quality)
    print("wrote %s (%dx%d, %d bytes)" % (args.output, out.width, out.height, os.path.getsize(args.output)))
    return 0


def cmd_music(args: argparse.Namespace) -> int:
    data = everyapi.generate_music(args.prompt, args.seconds, model=args.model)
    _generated(args, "music", args.prompt, data, {"seconds": args.seconds})
    return 0


def cmd_audio(args: argparse.Namespace) -> int:
    import sound

    report = sound.prepare(args.input, args.output, kind=args.kind, loop=args.loop, start=args.start, end=args.end, loop_seconds=args.loop_seconds, crossfade=args.crossfade, lufs=args.lufs, quality=args.quality, mono=args.mono)
    print(json.dumps(report, indent=1, sort_keys=True))
    return 0


def cmd_inspect(args: argparse.Namespace) -> int:
    for path in args.files:
        if path.lower().endswith(AUDIO_EXTENSIONS):
            import sound

            print(json.dumps(sound.inspect(path), sort_keys=True))
        else:
            from PIL import Image

            import imaging

            with Image.open(path) as picture:
                facts = {"file": path, "format": picture.format, "size": list(picture.size), "mode": picture.mode, "bytes": os.path.getsize(path)}
                if "A" in picture.getbands():
                    low, high = picture.getchannel("A").getextrema()
                    facts["alpha_range"] = [low, high]
                    facts["content_box"] = imaging.content_box(picture)
            print(json.dumps(facts, sort_keys=True))
    return 0


def _generation(parser: argparse.ArgumentParser, model: str) -> None:
    parser.add_argument("--out", required=True, help="file to write")
    parser.add_argument("--log", required=True, help="JSON-lines provenance file to append to")
    parser.add_argument("--date", required=True, help="today's date, YYYY-MM-DD, recorded in the provenance log")
    parser.add_argument("--model", default=model)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    image = commands.add_parser("image", help="make a picture from a prompt")
    image.add_argument("--prompt", required=True)
    image.add_argument("--size", default="1024x1024", help="WIDTHxHEIGHT (default 1024x1024; 1920x1080 for a background)")
    image.add_argument("--reference", help="a picture whose design the result should keep")
    image.add_argument("--transparent", action="store_true", help="ask for an RGBA PNG (needs --reference to be a PNG with transparent pixels)")
    _generation(image, everyapi.IMAGE_MODEL)
    image.set_defaults(run=cmd_image)

    pose = commands.add_parser("pose", help="make another pose of a character from its transparent reference")
    pose.add_argument("--reference", required=True, help="RGBA PNG of the character (the keyed base pose)")
    pose.add_argument("--pose", default="standing", help="what the character is doing now, e.g. \"running, left leg forward\"")
    pose.add_argument("--subject", default="character", help="what the reference shows (default: character)")
    pose.add_argument("--view", default="side view", help="camera (default: side view)")
    pose.add_argument("--prompt", help="replace the whole prompt")
    pose.add_argument("--size", default="1024x1024")
    _generation(pose, everyapi.IMAGE_MODEL)
    pose.set_defaults(run=cmd_pose)

    key = commands.add_parser("key", help="turn a flat background colour into transparency")
    key.add_argument("input")
    key.add_argument("output", help="RGBA .png to write")
    key.add_argument("--color", default="auto", help="the background colour, e.g. #ff00ff (default: read from the picture's border)")
    key.add_argument("--tolerance", type=float, default=0.10, help="colour distance that is fully transparent (default 0.10)")
    key.add_argument("--softness", type=float, default=0.10, help="width of the partly transparent band beyond it (default 0.10)")
    key.add_argument("--despill", type=float, default=1.0, help="how much of the key's tint to remove from the subject's rim, 0 .. 1 (default 1)")
    key.add_argument("--shrink", type=int, default=1, help="pixels to pull the edge in (default 1)")
    key.add_argument("--feather", type=float, default=0.6, help="edge softening radius in pixels (default 0.6)")
    key.set_defaults(run=cmd_key)

    pack = commands.add_parser("pack", help="trim frames and pack them into an atlas with a frame table")
    pack.add_argument("frames", nargs="+", help="RGBA pictures; the file name without extension is the frame name, and name_0, name_1, ... become the animation \"name\"")
    pack.add_argument("--out", required=True, help="output path without extension: writes <out>.png and <out>.json")
    pack.add_argument("--scale", type=float, help="stage pixels per atlas pixel")
    pack.add_argument("--height", type=float, help="stage pixels the content of the reference frame is tall (instead of --scale)")
    pack.add_argument("--height-of", help="the reference frame of --height (default: the first)")
    pack.add_argument("--max-frame", type=int, default=0, help="scale all frames by one factor so the largest side of any is at most this many pixels")
    pack.add_argument("--pivot", default="bottom", help="center, bottom, top, left, right, topleft or fractions like 0.5,0.9 (default bottom)")
    pack.add_argument("--anchor", choices=["content", "frame"], default="content", help="what the pivot is a point of: the trimmed content (default) or the whole source picture")
    pack.add_argument("--no-trim", action="store_true", help="keep the empty margins (tiles)")
    pack.add_argument("--padding", type=int, default=2)
    pack.add_argument("--extrude", type=int, default=0, help="repeat edge pixels this far outward (tiles drawn edge to edge: 2)")
    pack.add_argument("--max-size", type=int, default=2048, help="largest atlas side (default 2048; never above 4096)")
    pack.add_argument("--fps", action="append", metavar="NAME=FPS", help="frames per second of one animation")
    pack.add_argument("--default-fps", type=float, default=10.0)
    pack.add_argument("--once", action="append", metavar="NAME", help="an animation that holds its last frame instead of repeating")
    pack.set_defaults(run=cmd_pack)

    fit = commands.add_parser("fit", help="size an opaque picture and save it as JPEG, WebP or PNG")
    fit.add_argument("input")
    fit.add_argument("output")
    fit.add_argument("--size", type=_size, help="WIDTHxHEIGHT")
    fit.add_argument("--mode", choices=["cover", "stretch"], default="cover")
    fit.add_argument("--quality", type=int, default=88)
    fit.set_defaults(run=cmd_fit)

    tile = commands.add_parser("tile", help="make a texture repeat seamlessly")
    tile.add_argument("input")
    tile.add_argument("output")
    tile.add_argument("--blend", type=float, default=0.15, help="part of each side that is cross-faded (default 0.15)")
    tile.add_argument("--size", type=_size, help="WIDTHxHEIGHT of the result (a power of two such as 512x512 is a good tile)")
    tile.add_argument("--quality", type=int, default=88)
    tile.set_defaults(run=cmd_tile)

    music = commands.add_parser("music", help="make a piece of music from a prompt")
    music.add_argument("--prompt", required=True, help="say instrumental, no vocals")
    music.add_argument("--seconds", type=float, default=60.0)
    _generation(music, everyapi.MUSIC_MODEL)
    music.set_defaults(run=cmd_music)

    audio = commands.add_parser("audio", help="turn a generated or recorded file into the Ogg Vorbis a game ships")
    audio.add_argument("input")
    audio.add_argument("output", help=".ogg to write")
    audio.add_argument("--kind", choices=["music", "stinger", "sfx"], default="music")
    audio.add_argument("--loop", action="store_true", help="cut a seamless loop (music)")
    audio.add_argument("--start", type=float, help="seconds where the loop begins (default: the first sound)")
    audio.add_argument("--end", type=float, help="seconds up to which the clip may be used (default: before its ending)")
    audio.add_argument("--loop-seconds", type=float, help="length of the loop (default: found by matching the beat)")
    audio.add_argument("--crossfade", type=float, default=2.0, help="seconds blended across the loop point (default 2)")
    audio.add_argument("--lufs", type=float, help="loudness target (default -18 music, -16 stinger)")
    audio.add_argument("--quality", type=float, help="Vorbis quality (default 5; sfx 4)")
    audio.add_argument("--mono", action="store_true")
    audio.set_defaults(run=cmd_audio)

    inspect = commands.add_parser("inspect", help="print facts about pictures and audio files")
    inspect.add_argument("files", nargs="+")
    inspect.set_defaults(run=cmd_inspect)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if getattr(args, "max_size", 0) > 4096:
        print("pack: --max-size cannot exceed 4096", file=sys.stderr)
        return 2
    try:
        return args.run(args)
    except (everyapi.ApiError, ValueError, OSError) as error:
        print("%s: %s" % (args.command, error), file=sys.stderr)
        return 1
    except RuntimeError as error:
        print("%s: %s" % (args.command, error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
