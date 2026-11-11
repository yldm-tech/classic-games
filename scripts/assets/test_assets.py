"""Offline tests of the asset tools: nothing here calls the generation API. Run with `make assets-test` (python3 -m unittest discover -s scripts/assets -p 'test_*.py')."""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

import assets  # noqa: E402
import everyapi  # noqa: E402
import imaging  # noqa: E402
import sound  # noqa: E402

HAVE_AUDIO_TOOLS = bool(shutil.which("ffmpeg") and shutil.which("ffprobe") and (shutil.which("sox") or shutil.which("oggenc")))


def subject_on_key(key=(255, 0, 255)) -> Image.Image:
    """A teal disc with a dark outline on a flat key colour, drawn large and scaled down so its edge is a real anti-aliased mix of subject and backdrop."""
    big = Image.new("RGB", (800, 800), key)
    draw = ImageDraw.Draw(big)
    draw.ellipse((200, 200, 600, 600), fill=(40, 170, 150), outline=(20, 40, 50), width=16)
    return big.resize((200, 200), Image.LANCZOS)


class KeyTest(unittest.TestCase):
    def test_background_becomes_transparent_and_subject_stays(self):
        out = imaging.key_out(subject_on_key())
        pixels = np.asarray(out)
        self.assertEqual(out.mode, "RGBA")
        self.assertEqual(int(pixels[2, 2, 3]), 0)
        self.assertEqual(int(pixels[100, 100, 3]), 255)
        self.assertTrue(np.allclose(pixels[100, 100, :3], (40, 170, 150), atol=3))
        left, top, right, bottom = imaging.content_box(out)
        self.assertTrue(48 <= left <= 54 and 146 <= right <= 152 and 48 <= top <= 54 and 146 <= bottom <= 152)

    def test_no_key_colour_is_left_on_the_edge(self):
        pixels = np.asarray(imaging.key_out(subject_on_key())).astype(int)
        visible = pixels[..., 3] > 24
        # Magenta is red and blue well above green. No visible pixel may still look like that.
        magenta = np.minimum(pixels[..., 0], pixels[..., 2]) - pixels[..., 1]
        self.assertLess(int(magenta[visible].max()), 40)

    def test_key_colour_is_read_from_the_border(self):
        self.assertEqual(imaging.border_colour(subject_on_key((10, 240, 30))), (10, 240, 30))
        out = np.asarray(imaging.key_out(subject_on_key((10, 240, 30))))
        self.assertEqual(int(out[0, 0, 3]), 0)
        self.assertEqual(int(out[100, 100, 3]), 255)


class PackTest(unittest.TestCase):
    def frames(self):
        out = []
        for name, box in (("run_0", (30, 20, 70, 100)), ("run_1", (40, 30, 90, 100)), ("idle", (35, 10, 65, 100))):
            picture = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
            ImageDraw.Draw(picture).rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=(200, 80, 40, 255))
            out.append((name, picture))
        return out

    def test_frames_are_trimmed_packed_and_described(self):
        atlas, table = imaging.pack(self.frames(), height=30.0, height_of="idle", fps={"run": 12.0})
        self.assertEqual(table["format"], imaging.ATLAS_FORMAT)
        self.assertEqual(sorted(table["frames"]), ["idle", "run_0", "run_1"])
        self.assertEqual(table["frames"]["run_0"]["rect"][2:], [40, 80])
        self.assertEqual(table["frames"]["idle"]["source"], [30, 90])
        self.assertEqual(table["frames"]["idle"]["pivot"], [15.0, 90.0])
        self.assertAlmostEqual(table["scale"], 30.0 / 90.0, places=5)
        self.assertEqual(table["animations"], {"run": {"frames": ["run_0", "run_1"], "fps": 12.0, "loop": True}})
        pixels = np.asarray(atlas)
        rects = []
        for entry in table["frames"].values():
            x, y, wide, tall = entry["rect"]
            self.assertTrue((pixels[y : y + tall, x : x + wide, 3] == 255).all())
            rects.append((x, y, x + wide, y + tall))
        for index, first in enumerate(rects):
            for second in rects[index + 1 :]:
                self.assertTrue(first[2] <= second[0] or second[2] <= first[0] or first[3] <= second[1] or second[3] <= first[1])
        self.assertEqual(int((pixels[..., 3] == 255).sum()), 40 * 80 + 50 * 70 + 30 * 90)

    def test_frame_anchor_keeps_the_place_in_the_source(self):
        _, table = imaging.pack(self.frames(), scale=0.25, anchor="frame", pivot=(0.5, 0.5))
        self.assertEqual(table["frames"]["run_0"]["source"], [128, 128])
        self.assertEqual(table["frames"]["run_0"]["offset"], [30, 20])
        self.assertEqual(table["frames"]["run_0"]["pivot"], [64.0, 64.0])

    def test_frames_are_scaled_by_one_common_factor(self):
        _, table = imaging.pack(self.frames(), max_frame=64, scale=1.0)
        # Half size, give or take the pixel of soft edge the resampling adds on each side.
        for name, wide, tall in (("idle", 15, 45), ("run_1", 25, 35)):
            source = table["frames"][name]["source"]
            self.assertTrue(wide <= source[0] <= wide + 2 and tall <= source[1] <= tall + 2, source)

    def test_untrimmed_tiles_can_be_extruded(self):
        tile = Image.new("RGBA", (16, 16), (10, 200, 30, 255))
        atlas, table = imaging.pack([("grass", tile)], trim=False, extrude=2, padding=2, scale=1.0)
        x, y, wide, tall = table["frames"]["grass"]["rect"]
        pixels = np.asarray(atlas)
        self.assertEqual((wide, tall), (16, 16))
        self.assertTrue((pixels[y - 2 : y + tall + 2, x - 2 : x + wide + 2, 3] == 255).all())
        self.assertEqual(int(pixels[y - 3, x, 3]), 0)

    def test_an_atlas_is_written_with_its_table(self):
        with tempfile.TemporaryDirectory() as work:
            atlas, table = imaging.pack(self.frames(), scale=0.5)
            image_path, table_path = imaging.write_atlas(atlas, table, os.path.join(work, "art", "hero"))
            with open(table_path, encoding="utf-8") as handle:
                saved = json.load(handle)
            self.assertEqual(saved["image"], "hero.png")
            with Image.open(image_path) as written:
                self.assertEqual(list(written.size), saved["size"])

    def test_too_many_frames_for_the_atlas_is_an_error(self):
        with self.assertRaises(ValueError):
            imaging.pack(self.frames(), max_size=64, scale=1.0)


class PictureTest(unittest.TestCase):
    def test_fit_covers_and_crops(self):
        out = imaging.fit(Image.new("RGB", (400, 400), (9, 9, 9)), (192, 108))
        self.assertEqual(out.size, (192, 108))

    def test_seamless_tile_wraps(self):
        generator = np.random.default_rng(4)
        ramp = np.linspace(0, 255, 128)[None, :, None] * np.ones((128, 1, 3)) * 0.7 + generator.random((128, 128, 3)) * 40
        source = Image.fromarray(ramp.astype(np.uint8), "RGB")
        out = np.asarray(imaging.make_seamless(source)).astype(float)
        before = np.asarray(source).astype(float)
        self.assertEqual(out.shape, before.shape)
        # The jump across the wrap is now no larger than between ordinary neighbours inside the picture.
        self.assertGreater(np.abs(before[:, 0] - before[:, -1]).mean(), 100.0)
        self.assertLess(np.abs(out[:, 0] - out[:, -1]).mean(), 2.0 * np.abs(np.diff(out, axis=1)).mean() + 6.0)


class LoopTest(unittest.TestCase):
    def music(self, seconds=24.0, bpm=120.0):
        """A click on every beat over a held tone whose pitch changes every bar in a four-bar pattern, fading out at the end like a generated piece."""
        rate = sound.RATE
        time = np.arange(int(seconds * rate)) / rate
        beat = 60.0 / bpm
        bar = (time // (beat * 4)).astype(int) % 4
        tone = 0.2 * np.sin(2 * np.pi * np.array([220.0, 277.0, 330.0, 247.0])[bar] * time)
        click = 0.6 * np.exp(-((time % beat) * 40.0)) * np.sin(2 * np.pi * 1000.0 * time)
        mono = (tone + click).astype(np.float32)
        mono[-2 * rate :] *= np.linspace(1.0, 0.0, 2 * rate, dtype=np.float32)
        return np.stack([mono, mono], axis=1)

    def test_the_loop_is_a_whole_number_of_bars(self):
        samples = self.music()
        end = sound.usable_end(samples)
        self.assertTrue(21.0 <= end <= 23.5)
        seconds, score = sound.find_loop(samples, start=0.0, end=end, crossfade=1.0)
        self.assertGreater(score, 0.8)
        bars = seconds / 2.0
        self.assertAlmostEqual(bars, round(bars), delta=0.02)
        self.assertGreaterEqual(seconds, 10.0)

    def test_the_folded_loop_has_no_jump_at_its_seam(self):
        samples = self.music()
        cut = samples[: int(16.0 * sound.RATE)]
        folded = sound.fold_loop(samples, start=0.0, loop_seconds=16.0, crossfade=1.0)
        self.assertEqual(len(folded), len(cut))
        # A plain cut ends on whatever the wave was doing; the fold ends where its own start picks up.
        wrapped = np.concatenate([folded[-2000:], folded[:2000]]).mean(axis=1)
        # Compared with a beat inside the loop: the seam falls on a beat too, and may move as much as any other beat does, no more.
        beat = int(0.5 * sound.RATE)
        inside = folded[4 * beat - 2000 : 4 * beat + 2000].mean(axis=1)
        self.assertLess(np.abs(np.diff(wrapped)).max(), 1.2 * np.abs(np.diff(inside)).max() + 0.01)
        self.assertLess(sound.seam_ratio(folded), 4.0)

    def test_gain_is_constant_and_respects_the_ceiling(self):
        samples = self.music(4.0)
        louder, applied = sound.apply_gain(samples, 40.0)
        self.assertAlmostEqual(sound.peak_db(louder), sound.CEILING_DB, places=2)
        self.assertLess(applied, 40.0)
        quieter, applied = sound.apply_gain(samples, -6.0)
        self.assertAlmostEqual(applied, -6.0)
        self.assertTrue(np.allclose(quieter, samples * 10 ** (-6.0 / 20.0), atol=1e-6))

    def test_silence_is_trimmed(self):
        samples = np.zeros((sound.RATE, 2), dtype=np.float32)
        samples[10000:20000] = 0.5
        trimmed = sound.trim_silence(samples)
        self.assertTrue(10000 <= len(trimmed) <= 10000 + 2 * int(0.005 * sound.RATE) + 2)

    @unittest.skipUnless(HAVE_AUDIO_TOOLS, "ffmpeg, ffprobe and an Ogg Vorbis encoder are needed")
    def test_music_is_looped_levelled_and_encoded(self):
        with tempfile.TemporaryDirectory() as work:
            source = os.path.join(work, "in.wav")
            sound.write_wav(source, self.music())
            report = sound.prepare(source, os.path.join(work, "out", "loop.ogg"), kind="music", loop=True, crossfade=1.0)
            self.assertAlmostEqual(report["lufs"], sound.MUSIC_LUFS, delta=0.3)
            self.assertAlmostEqual(report["loop_seconds"] / 2.0, round(report["loop_seconds"] / 2.0), delta=0.02)
            facts = sound.inspect(report["output"])
            self.assertAlmostEqual(facts["seconds"], report["seconds"], delta=0.01)
            self.assertAlmostEqual(facts["lufs"], sound.MUSIC_LUFS, delta=0.6)
            mono = sound.prepare(source, os.path.join(work, "out", "mono.ogg"), kind="music", loop=True, crossfade=1.0, mono=True)
            self.assertAlmostEqual(sound.inspect(mono["output"])["lufs"], sound.MUSIC_LUFS, delta=0.6)

    @unittest.skipUnless(HAVE_AUDIO_TOOLS, "ffmpeg, ffprobe and an Ogg Vorbis encoder are needed")
    def test_an_effect_is_trimmed_and_peak_normalised(self):
        with tempfile.TemporaryDirectory() as work:
            samples = np.zeros((sound.RATE, 2), dtype=np.float32)
            samples[8000:16000] = (0.2 * np.sin(np.arange(8000) * 0.2))[:, None]
            source = os.path.join(work, "in.wav")
            sound.write_wav(source, samples)
            report = sound.prepare(source, os.path.join(work, "hit.ogg"), kind="sfx", mono=True)
            self.assertAlmostEqual(report["peak_db"], sound.SFX_PEAK_DB, delta=0.1)
            self.assertLess(report["seconds"], 0.25)


class ApiTest(unittest.TestCase):
    def test_the_key_comes_from_the_environment_only_and_is_never_logged(self):
        saved = os.environ.pop("EVERYAPI_KEY", None)
        try:
            with self.assertRaises(everyapi.ApiError):
                everyapi.generate_music("x", 1.0)
            os.environ["EVERYAPI_KEY"] = "secret-value-for-test"
            with tempfile.TemporaryDirectory() as work:
                log = os.path.join(work, "logs", "provenance.jsonl")
                everyapi.log_provenance(log, {"date": "2026-01-02", "kind": "image", "model": "m", "prompt": "p", "output": "o.png"})
                everyapi.log_provenance(log, {"date": "2026-01-02", "kind": "music", "model": "m", "prompt": "q", "output": "o.mp3"})
                with open(log, encoding="utf-8") as handle:
                    text = handle.read()
                self.assertNotIn("secret-value-for-test", text)
                self.assertEqual([json.loads(line)["prompt"] for line in text.splitlines()], ["p", "q"])
        finally:
            os.environ.pop("EVERYAPI_KEY", None)
            if saved is not None:
                os.environ["EVERYAPI_KEY"] = saved

    def test_a_pose_needs_a_transparent_png_reference(self):
        with tempfile.TemporaryDirectory() as work:
            opaque = os.path.join(work, "opaque.png")
            Image.new("RGBA", (8, 8), (1, 2, 3, 255)).save(opaque)
            code = assets.main(["pose", "--reference", opaque, "--pose", "waving", "--out", os.path.join(work, "o.png"), "--log", os.path.join(work, "l.jsonl"), "--date", "2026-01-02"])
            self.assertEqual(code, 2)
            self.assertFalse(os.path.exists(os.path.join(work, "l.jsonl")))

    def test_generation_commands_require_the_log_and_the_date(self):
        parser = assets.build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args(["image", "--prompt", "p", "--out", "o.jpg"])
        args = parser.parse_args(["music", "--prompt", "p", "--out", "o.mp3", "--log", "l.jsonl", "--date", "2026-01-02"])
        self.assertEqual((args.model, args.seconds), (everyapi.MUSIC_MODEL, 60.0))


if __name__ == "__main__":
    unittest.main()
