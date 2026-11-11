"""Picture processing for the asset tools: keying a flat background out to alpha, trimming, packing frames into an atlas with the frame table GameSprites reads, and fitting opaque pictures to a size."""

from __future__ import annotations

import json
import os
import re

import numpy as np
from PIL import Image, ImageFilter

ATLAS_FORMAT = 1
# Alpha at or below this counts as empty when a frame is trimmed.
TRIM_ALPHA = 8


# ---- keying ----


def _chroma(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    luma = 0.299 * red + 0.587 * green + 0.114 * blue
    return luma, (blue - luma) * 0.564, (red - luma) * 0.713


def border_colour(image: Image.Image) -> tuple[int, int, int]:
    """The background colour of a picture: the median of its outer frame."""
    rgb = np.asarray(image.convert("RGB"))
    band = max(2, min(rgb.shape[0], rgb.shape[1]) // 64)
    edge = np.concatenate([rgb[:band].reshape(-1, 3), rgb[-band:].reshape(-1, 3), rgb[:, :band].reshape(-1, 3), rgb[:, -band:].reshape(-1, 3)])
    return tuple(int(value) for value in np.median(edge, axis=0))


def key_out(image: Image.Image, colour: tuple[int, int, int] | None = None, tolerance: float = 0.10, softness: float = 0.10, despill: float = 1.0, shrink: int = 1, feather: float = 0.6) -> Image.Image:
    """Turn a flat background colour into transparency.

    A pixel is transparent when its colour is within `tolerance` of the key (a distance in a colour space that weighs hue far above brightness, so shading on the backdrop still keys), opaque beyond `tolerance + softness`, and partly transparent in between. Then the edge is cleaned: the mask is pulled in by `shrink` pixels and softened by `feather`, specks are removed, the key colour is taken back out of partly transparent pixels (they were a mix of subject and backdrop) and the key's tint is removed from the rim of the subject (`despill`, 0 .. 1).
    """
    source = np.asarray(image.convert("RGB")).astype(np.float32) / 255.0
    key = np.array(colour if colour is not None else border_colour(image), dtype=np.float32) / 255.0
    luma, blue_diff, red_diff = _chroma(source)
    key_luma, key_blue, key_red = _chroma(key.reshape(1, 1, 3))
    distance = np.sqrt((blue_diff - key_blue) ** 2 + (red_diff - key_red) ** 2 + 0.08 * (luma - key_luma) ** 2)
    alpha = np.clip((distance - tolerance) / max(softness, 1e-4), 0.0, 1.0)

    mask = Image.fromarray((alpha * 255.0 + 0.5).astype(np.uint8), "L")
    # Opening removes isolated specks of backdrop noise that survived; the minimum filter then pulls the edge in, off the contaminated rim.
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    for _ in range(max(0, shrink)):
        mask = mask.filter(ImageFilter.MinFilter(3))
    if feather > 0.0:
        soft = mask.filter(ImageFilter.GaussianBlur(feather))
        # Feathering may only take away: a pixel never becomes more opaque than the mask said.
        mask = Image.fromarray(np.minimum(np.asarray(mask), np.asarray(soft)), "L")
    alpha = np.asarray(mask).astype(np.float32) / 255.0

    colourful = source.copy()
    partial = (alpha > 0.0) & (alpha < 1.0)
    if partial.any():
        # observed = alpha * subject + (1 - alpha) * key, solved for the subject.
        safe = np.maximum(alpha[partial], 0.15)[:, None]
        colourful[partial] = np.clip((source[partial] - (1.0 - safe) * key) / safe, 0.0, 1.0)
    if despill > 0.0:
        # The rim of the subject: everything within a few pixels of transparency.
        near = np.asarray(Image.fromarray(((alpha < 0.999) * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255.0
        tint = key - key.mean()
        length = float(np.linalg.norm(tint))
        if length > 1e-3:
            tint /= length
            grey = colourful.mean(axis=2, keepdims=True)
            along = np.maximum(0.0, ((colourful - grey) * tint).sum(axis=2))
            colourful = np.clip(colourful - (along * near * despill)[..., None] * tint, 0.0, 1.0)
    colourful[alpha <= 0.0] = 0.0
    out = np.dstack([colourful, alpha])
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


# ---- frames ----


def content_box(image: Image.Image) -> tuple[int, int, int, int] | None:
    """Bounding box (left, top, right, bottom) of everything that is not empty, or None for an empty picture."""
    alpha = np.asarray(image.convert("RGBA"))[..., 3] > TRIM_ALPHA
    rows = np.flatnonzero(alpha.any(axis=1))
    columns = np.flatnonzero(alpha.any(axis=0))
    if rows.size == 0:
        return None
    return int(columns[0]), int(rows[0]), int(columns[-1]) + 1, int(rows[-1]) + 1


def resize_rgba(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize with alpha handled properly: colours are weighted by their opacity, so transparent pixels never bleed a dark or coloured fringe into the edge."""
    if image.size == size:
        return image
    return image.convert("RGBA").convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def parse_pivot(text: str) -> tuple[float, float]:
    named = {"center": (0.5, 0.5), "centre": (0.5, 0.5), "bottom": (0.5, 1.0), "top": (0.5, 0.0), "left": (0.0, 0.5), "right": (1.0, 0.5), "topleft": (0.0, 0.0)}
    if text in named:
        return named[text]
    parts = text.split(",")
    if len(parts) != 2:
        raise ValueError("a pivot is center, bottom, top, left, right, topleft or two fractions like 0.5,0.9")
    return float(parts[0]), float(parts[1])


def _shelves(sizes: list[tuple[int, int]], width: int, padding: int) -> tuple[list[tuple[int, int]], int] | None:
    """Place rectangles on shelves, tallest first. Returns their positions (in the order given) and the height used, or None when one is wider than the atlas."""
    order = sorted(range(len(sizes)), key=lambda index: (-sizes[index][1], -sizes[index][0], index))
    places: list[tuple[int, int]] = [(0, 0)] * len(sizes)
    x = y = padding
    shelf = 0
    for index in order:
        wide, tall = sizes[index]
        if wide + 2 * padding > width:
            return None
        if x + wide + padding > width:
            x = padding
            y += shelf + padding
            shelf = 0
        places[index] = (x, y)
        x += wide + padding
        shelf = max(shelf, tall)
    return places, y + shelf + padding


def pack(frames: list[tuple[str, Image.Image]], scale: float | None = None, height: float | None = None, height_of: str | None = None, max_frame: int = 0, pivot: tuple[float, float] = (0.5, 1.0), anchor: str = "content", trim: bool = True, padding: int = 2, extrude: int = 0, max_size: int = 2048, fps: dict[str, float] | None = None, default_fps: float = 10.0, once: set[str] | None = None) -> tuple[Image.Image, dict]:
    """Pack named RGBA frames into one atlas and build its frame table.

    max_frame   every frame is first scaled by one common factor so that the largest side of any frame is at most this many pixels (0 keeps the sources as they are)
    trim        cut the empty margin off each frame; the table remembers where the cut part sat
    anchor      "content": the pivot is a point of the trimmed content (bottom means the lowest drawn pixel, the feet), which keeps poses that were generated separately standing on the same ground; "frame": a point of the whole source picture, for frames that were drawn to line up
    scale       stage pixels per atlas pixel; or `height`: the stage height of the content of frame `height_of` (default the first frame), from which the scale follows
    extrude     repeat each frame's edge pixels this far into the padding, for tiles that are drawn edge to edge
    """
    if not frames:
        raise ValueError("nothing to pack")
    names = [name for name, _ in frames]
    if len(set(names)) != len(names):
        raise ValueError("two frames have the same name")
    pictures = [picture.convert("RGBA") for _, picture in frames]
    if max_frame > 0:
        largest = max(max(picture.size) for picture in pictures)
        if largest > max_frame:
            factor = max_frame / largest
            pictures = [resize_rgba(picture, (max(1, round(picture.width * factor)), max(1, round(picture.height * factor)))) for picture in pictures]
    parts: list[Image.Image] = []
    entries: list[dict] = []
    for name, picture in zip(names, pictures):
        box = content_box(picture) if trim else (0, 0, picture.width, picture.height)
        if box is None:
            raise ValueError("frame %s is empty" % name)
        left, top, right, bottom = box
        part = picture.crop(box)
        if anchor == "content":
            source = (right - left, bottom - top)
            offset = (0, 0)
        else:
            source = picture.size
            offset = (left, top)
        entries.append({"source": [source[0], source[1]], "offset": [offset[0], offset[1]], "pivot": [round(source[0] * pivot[0], 2), round(source[1] * pivot[1], 2)]})
        parts.append(part)
    sizes = [(part.width + 2 * extrude, part.height + 2 * extrude) for part in parts]
    best: tuple[int, int, list[tuple[int, int]]] | None = None
    width = 64
    while width <= max_size:
        placed = _shelves(sizes, width, padding)
        if placed is not None and placed[1] <= max_size:
            tall = placed[1] + (-placed[1]) % 4
            if best is None or width * tall < best[0] * best[1]:
                best = (width, tall, placed[0])
        width *= 2
    if best is None:
        raise ValueError("the frames do not fit an atlas of %d x %d; lower --max-frame or split the set" % (max_size, max_size))
    atlas = Image.new("RGBA", (best[0], best[1]), (0, 0, 0, 0))
    table_frames: dict[str, dict] = {}
    for name, part, entry, place in zip(names, parts, entries, best[2]):
        x, y = place[0] + extrude, place[1] + extrude
        if extrude > 0:
            pixels = np.asarray(part)
            padded = np.pad(pixels, ((extrude, extrude), (extrude, extrude), (0, 0)), mode="edge")
            atlas.paste(Image.fromarray(padded, "RGBA"), (place[0], place[1]))
        else:
            atlas.paste(part, (x, y))
        table_frames[name] = {"rect": [x, y, part.width, part.height], **entry}
    if scale is None:
        if height is None:
            scale = 1.0
        else:
            reference = height_of if height_of is not None else names[0]
            if reference not in table_frames:
                raise ValueError("--height-of names a frame that is not in the set: %s" % reference)
            scale = height / table_frames[reference]["source"][1]
    animations: dict[str, dict] = {}
    groups: dict[str, list[tuple[int, str]]] = {}
    for name in names:
        match = re.fullmatch(r"(.+?)_(\d+)", name)
        if match:
            groups.setdefault(match.group(1), []).append((int(match.group(2)), name))
    for base, members in groups.items():
        animations[base] = {"frames": [name for _, name in sorted(members)], "fps": (fps or {}).get(base, default_fps), "loop": base not in (once or set())}
    table = {"format": ATLAS_FORMAT, "image": "", "size": [atlas.width, atlas.height], "scale": round(scale, 6), "frames": table_frames, "animations": animations}
    return atlas, table


def write_atlas(atlas: Image.Image, table: dict, out_base: str) -> tuple[str, str]:
    """Write <out_base>.png and <out_base>.json."""
    os.makedirs(os.path.dirname(os.path.abspath(out_base)), exist_ok=True)
    image_path = out_base + ".png"
    table_path = out_base + ".json"
    atlas.save(image_path, optimize=True)
    table = dict(table)
    table["image"] = os.path.basename(image_path)
    with open(table_path, "w", encoding="utf-8") as handle:
        json.dump(table, handle, indent=1, sort_keys=True)
        handle.write("\n")
    return image_path, table_path


# ---- opaque pictures ----


def fit(image: Image.Image, size: tuple[int, int], mode: str = "cover") -> Image.Image:
    """Bring a picture to exactly `size`: "cover" fills it and crops the overflow around the centre, "stretch" ignores the aspect ratio."""
    if mode == "stretch":
        return image.resize(size, Image.LANCZOS)
    factor = max(size[0] / image.width, size[1] / image.height)
    scaled = image.resize((max(size[0], round(image.width * factor)), max(size[1], round(image.height * factor))), Image.LANCZOS)
    left = (scaled.width - size[0]) // 2
    top = (scaled.height - size[1]) // 2
    return scaled.crop((left, top, left + size[0], top + size[1]))


def make_seamless(image: Image.Image, blend: float = 0.15) -> Image.Image:
    """Make a texture repeat without a visible seam. A band along the right edge (`blend` of the width) is cross-faded over the left edge and cut off, so the new right edge runs straight on into the new left edge; the same is then done top to bottom. The result is smaller by the two bands and is scaled back to the size it had."""
    pixels = np.asarray(image.convert("RGB")).astype(np.float32)
    for axis in (1, 0):
        length = pixels.shape[axis]
        band = int(length * blend)
        if band < 1:
            continue
        pixels = np.moveaxis(pixels, axis, 0)
        ramp = np.linspace(0.0, 1.0, band, dtype=np.float32).reshape((band,) + (1,) * (pixels.ndim - 1))
        ramp = ramp * ramp * (3.0 - 2.0 * ramp)
        folded = pixels[: length - band].copy()
        folded[:band] = pixels[:band] * ramp + pixels[length - band :] * (1.0 - ramp)
        pixels = np.moveaxis(folded, 0, axis)
    out = Image.fromarray(np.clip(pixels + 0.5, 0, 255).astype(np.uint8), "RGB")
    return out.resize(image.size, Image.LANCZOS)


def save_picture(image: Image.Image, path: str, quality: int = 88) -> None:
    """Save by extension: .png (lossless, keeps alpha), .jpg / .jpeg and .webp (lossy, for opaque pictures; WebP keeps alpha)."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    extension = os.path.splitext(path)[1].lower()
    if extension in (".jpg", ".jpeg"):
        image.convert("RGB").save(path, quality=quality, optimize=True, progressive=True, subsampling=0 if quality >= 90 else 2)
    elif extension == ".webp":
        image.save(path, quality=quality, method=6)
    elif extension == ".png":
        image.save(path, optimize=True)
    else:
        raise ValueError("pictures are saved as .png, .jpg or .webp")
