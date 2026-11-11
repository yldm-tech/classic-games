"""Audio processing for the asset tools: decoding, cutting a seamless loop, bringing everything to one loudness, and encoding Ogg Vorbis.

Decoding and loudness measurement use ffmpeg; the Ogg Vorbis encoder is libvorbis, through whichever of ffmpeg (when built with libvorbis), sox or oggenc is installed. The samples in between are handled here with numpy, because the one thing a loop must never get is a filter that treats its start differently from its end.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
# Integrated loudness targets in LUFS. Music sits lowest, so effects and stingers are heard over it without the bus clipping.
MUSIC_LUFS = -18.0
STINGER_LUFS = -16.0
# Peak of a file sound effect, in dBFS, and the ceiling nothing may exceed.
SFX_PEAK_DB = -3.0
CEILING_DB = -1.0
SILENCE_DB = -50.0


class AudioError(RuntimeError):
    pass


def _tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise AudioError("%s is not installed (see scripts/assets/README.md)" % name)
    return path


def decode(path: str, rate: int = RATE) -> np.ndarray:
    """Any audio file as float samples, shape (frames, 2), at `rate`. A mono file comes back with the same signal in both columns at full level, which is how a game plays it (ffmpeg's own mono-to-stereo conversion would turn it down by 3 dB)."""
    probe = subprocess.run([_tool("ffprobe"), "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0", path], capture_output=True, check=False)
    channels = 1 if probe.stdout.strip() == b"1" else 2
    result = subprocess.run([_tool("ffmpeg"), "-v", "error", "-i", path, "-f", "f32le", "-ac", str(channels), "-ar", str(rate), "-"], capture_output=True, check=False)
    if result.returncode != 0 or not result.stdout:
        raise AudioError("ffmpeg could not decode %s: %s" % (path, result.stderr.decode("utf-8", "replace")[:300]))
    samples = np.frombuffer(result.stdout, dtype="<f4").reshape(-1, channels).astype(np.float32)
    return np.repeat(samples, 2, axis=1) if channels == 1 else samples


def write_wav(path: str, samples: np.ndarray, rate: int = RATE) -> None:
    """16-bit PCM with triangular dither, so quiet fades do not turn into steps."""
    generator = np.random.default_rng(1)
    dither = (generator.random(samples.shape, dtype=np.float32) - generator.random(samples.shape, dtype=np.float32)) / 32768.0
    data = np.clip(np.round((samples + dither) * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(samples.shape[1] if samples.ndim == 2 else 1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(data.tobytes())


def loudness(samples: np.ndarray, rate: int = RATE) -> float | None:
    """Integrated loudness in LUFS (EBU R128, measured by ffmpeg), or None when the clip is too short or too quiet to measure."""
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "measure.wav")
        write_wav(path, samples, rate)
        result = subprocess.run([_tool("ffmpeg"), "-hide_banner", "-nostats", "-i", path, "-af", "loudnorm=print_format=json", "-f", "null", "-"], capture_output=True, check=False)
    text = result.stderr.decode("utf-8", "replace")
    start = text.rfind("{")
    end = text.rfind("}")
    if result.returncode != 0 or start < 0 or end < start:
        raise AudioError("ffmpeg could not measure loudness: %s" % text[-300:])
    try:
        value = float(json.loads(text[start : end + 1])["input_i"])
    except (ValueError, KeyError):
        return None
    return value if np.isfinite(value) and value > -70.0 else None


def peak_db(samples: np.ndarray) -> float:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    return 20.0 * np.log10(peak) if peak > 0.0 else -120.0


def trim_silence(samples: np.ndarray, rate: int = RATE, threshold_db: float = SILENCE_DB, lead: bool = True, tail: bool = True, keep: float = 0.005) -> np.ndarray:
    """Cut silence off the ends, keeping `keep` seconds of it so an attack is not shaved."""
    level = np.max(np.abs(samples), axis=1)
    loud = np.flatnonzero(level > 10.0 ** (threshold_db / 20.0))
    if loud.size == 0:
        return samples
    margin = int(keep * rate)
    first = max(0, int(loud[0]) - margin) if lead else 0
    last = min(len(samples), int(loud[-1]) + 1 + margin) if tail else len(samples)
    return samples[first:last]


def fade_ends(samples: np.ndarray, rate: int = RATE, fade_in: float = 0.004, fade_out: float = 0.03) -> np.ndarray:
    out = samples.copy()
    head = min(len(out) // 2, int(fade_in * rate))
    tail = min(len(out) // 2, int(fade_out * rate))
    if head > 0:
        out[:head] *= np.linspace(0.0, 1.0, head, dtype=np.float32)[:, None]
    if tail > 0:
        out[-tail:] *= np.linspace(1.0, 0.0, tail, dtype=np.float32)[:, None]
    return out


def apply_gain(samples: np.ndarray, gain_db: float, ceiling_db: float = CEILING_DB) -> tuple[np.ndarray, float]:
    """Apply one constant gain to the whole clip, held back as far as needed to keep its peak under the ceiling. Returns the samples and the gain that was applied. A constant gain is the only kind that leaves a loop seamless."""
    allowed = ceiling_db - peak_db(samples)
    applied = min(gain_db, allowed)
    return samples * np.float32(10.0 ** (applied / 20.0)), applied


# ---- loops ----


def _envelope(mono: np.ndarray, hop: int) -> np.ndarray:
    """Onset strength: how much the energy rises from one hop to the next."""
    frames = len(mono) // hop
    energy = np.sqrt(np.mean(mono[: frames * hop].reshape(frames, hop) ** 2, axis=1) + 1e-12)
    rise = np.diff(np.log(energy + 1e-4), prepend=np.log(energy[0] + 1e-4))
    return np.maximum(rise, 0.0)


def _similarity(first: np.ndarray, second: np.ndarray) -> float:
    first = first - first.mean(axis=0)
    second = second - second.mean(axis=0)
    denominator = float(np.linalg.norm(first) * np.linalg.norm(second))
    return float(np.sum(first * second) / denominator) if denominator > 1e-9 else 0.0


def _bands(mono: np.ndarray, rate: int, hop: int, bands: int = 24) -> np.ndarray:
    """What the music sounds like over time: the level in `bands` pitch bands, one row per hop. Two stretches of music with similar rows have the same notes on the same beats, which a comparison of rhythm alone cannot tell."""
    window = hop * 4
    count = (len(mono) - window) // hop
    if count < 1:
        return np.zeros((0, bands), dtype=np.float32)
    edges = np.geomspace(60.0, min(8000.0, rate * 0.45), bands + 1)
    bins = np.fft.rfftfreq(window, 1.0 / rate)
    taper = np.hanning(window).astype(np.float32)
    out = np.zeros((count, bands), dtype=np.float32)
    # In blocks, so a long piece does not need its whole spectrogram in memory at once.
    for begin in range(0, count, 512):
        rows = np.arange(begin, min(count, begin + 512))
        frames = mono[rows[:, None] * hop + np.arange(window)[None, :]] * taper
        power = np.abs(np.fft.rfft(frames, axis=1)) ** 2
        for band in range(bands):
            chosen = (bins >= edges[band]) & (bins < edges[band + 1])
            if chosen.any():
                out[rows, band] = power[:, chosen].sum(axis=1)
    return np.log1p(out * 100.0)


def usable_end(samples: np.ndarray, rate: int = RATE) -> float:
    """Seconds into the clip where its ending (a fade-out or a last ringing chord) begins: the last moment at which a one-second window is still at least half as loud as the piece usually is."""
    mono = samples.mean(axis=1)
    window = rate
    count = len(mono) // window
    if count < 4:
        return len(mono) / rate
    levels = np.sqrt(np.mean(mono[: count * window].reshape(count, window) ** 2, axis=1))
    typical = float(np.median(levels))
    strong = np.flatnonzero(levels >= 0.5 * typical)
    return float(strong[-1] + 1) * window / rate if strong.size else len(mono) / rate


def find_loop(samples: np.ndarray, rate: int = RATE, start: float = 0.0, end: float | None = None, crossfade: float = 2.0, shortest: float = 0.5) -> tuple[float, float]:
    """Choose the loop length for a piece of music: (loop_seconds, similarity).

    The loop begins at `start` and may use the clip up to `end`. Its length is chosen so that the music right after the loop point resembles the music at the start (the same notes on the same beats), which is what makes a cross-faded loop keep its beat and its phrase; the answer is then refined to a few milliseconds on the note onsets. Lengths between `shortest` of the available span and all of it are tried.
    """
    mono = samples.mean(axis=1)
    limit = len(mono) / rate if end is None else min(end, len(mono) / rate)
    available = limit - start - crossfade
    if available <= 4.0:
        raise AudioError("too little music between --start and --end to cut a loop from")
    coarse_hop = 1024
    envelope = _bands(mono, rate, coarse_hop)
    per_second = rate / coarse_hop
    compare = int(min(8.0, max(2.0, crossfade * 2.0)) * per_second)
    origin = int(start * per_second)
    head = envelope[origin : origin + compare]
    scores: list[tuple[int, float]] = []
    for lag in range(int(available * shortest * per_second), int(available * per_second) + 1):
        tail = envelope[origin + lag : origin + lag + compare]
        if len(tail) < len(head):
            break
        scores.append((lag, _similarity(head, tail)))
    best_score = max((score for _, score in scores), default=0.0)
    # Among candidates that line up about as well as the best, the longest loop wins: it repeats least often.
    best_lag = max((lag for lag, score in scores if score > 0.0 and score >= best_score - 0.03), default=0)
    if best_lag == 0:
        return available, 0.0
    # Refine to a few milliseconds on a finer envelope around the coarse answer.
    fine_hop = 64
    fine = _envelope(mono, fine_hop)[:, None]
    fine_per_second = rate / fine_hop
    fine_origin = int(start * fine_per_second)
    fine_compare = int(compare / per_second * fine_per_second)
    centre = int(best_lag / per_second * fine_per_second)
    spread = int(0.04 * fine_per_second)
    fine_head = fine[fine_origin : fine_origin + fine_compare]
    best_fine = centre
    best_fine_score = -2.0
    for lag in range(max(1, centre - spread), centre + spread + 1):
        tail = fine[fine_origin + lag : fine_origin + lag + fine_compare]
        if len(tail) < len(fine_head):
            break
        score = _similarity(fine_head, tail)
        if score > best_fine_score:
            best_fine_score = score
            best_fine = lag
    return min(available, best_fine / fine_per_second), best_score


def fold_loop(samples: np.ndarray, rate: int = RATE, start: float = 0.0, loop_seconds: float = 0.0, crossfade: float = 2.0) -> np.ndarray:
    """Cut a loop of `loop_seconds` beginning at `start`. The `crossfade` seconds of music that follow the loop are faded out over the loop's own beginning, which fades in: played end to start, the result runs straight on with no cut."""
    first = int(start * rate)
    length = int(loop_seconds * rate)
    blend = int(crossfade * rate)
    if length <= 0 or first + length + blend > len(samples):
        raise AudioError("the loop (%.2fs from %.2fs, plus %.2fs of cross-fade) does not fit the clip of %.2fs" % (loop_seconds, start, crossfade, len(samples) / rate))
    blend = min(blend, length)
    out = samples[first : first + length].copy()
    if blend > 0:
        position = np.linspace(0.0, np.pi / 2.0, blend, dtype=np.float32)[:, None]
        out[:blend] = out[:blend] * np.sin(position) + samples[first + length : first + length + blend] * np.cos(position)
    return out


def seam_ratio(samples: np.ndarray) -> float:
    """How abrupt the jump from the last sample back to the first is, relative to the ordinary sample-to-sample movement of the clip. Around 1 is inaudible; a hard cut in loud music is 10 and more."""
    mono = samples.mean(axis=1)
    if len(mono) < 4:
        return 0.0
    steps = np.abs(np.diff(mono))
    typical = float(np.sqrt(np.mean(steps**2))) + 1e-9
    return float(abs(mono[0] - mono[-1])) / typical


# ---- encoding ----


def _has_libvorbis(ffmpeg: str) -> bool:
    result = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, check=False)
    return b"libvorbis" in result.stdout


def encode_ogg(samples: np.ndarray, out_path: str, rate: int = RATE, quality: float = 5.0, mono: bool = False) -> str:
    """Encode Ogg Vorbis with libvorbis at a VBR quality (-1 .. 10; 5 is about 160 kbit/s in stereo). Returns the name of the encoder that was used."""
    if mono:
        samples = samples.mean(axis=1, keepdims=True)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        wav_path = os.path.join(work, "in.wav")
        write_wav(wav_path, samples, rate)
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg and _has_libvorbis(ffmpeg):
            command = [ffmpeg, "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", out_path]
            used = "ffmpeg libvorbis"
        elif shutil.which("sox"):
            command = [shutil.which("sox"), wav_path, "-C", str(quality), "--comment", "", out_path]
            used = "sox libvorbis"
        elif shutil.which("oggenc"):
            command = [shutil.which("oggenc"), "-Q", "-q", str(quality), "-o", out_path, wav_path]
            used = "oggenc"
        else:
            raise AudioError("no Ogg Vorbis encoder found: install sox, vorbis-tools, or an ffmpeg built with libvorbis")
        result = subprocess.run(command, capture_output=True, check=False)
        if result.returncode != 0 or not os.path.isfile(out_path) or os.path.getsize(out_path) == 0:
            raise AudioError("%s failed: %s" % (used, result.stderr.decode("utf-8", "replace")[:300]))
    return used


def prepare(in_path: str, out_path: str, kind: str = "music", loop: bool = False, start: float | None = None, end: float | None = None, loop_seconds: float | None = None, crossfade: float = 2.0, lufs: float | None = None, quality: float | None = None, mono: bool = False) -> dict:
    """The whole path from a generated or recorded file to the Ogg Vorbis file a game ships. Returns a report of what was done.

    kind "music": optional loop cut, then one constant gain to MUSIC_LUFS. kind "stinger": silence trimmed, short fades, gain to STINGER_LUFS. kind "sfx": silence trimmed, short fades, peak brought to SFX_PEAK_DB.
    """
    if kind not in ("music", "stinger", "sfx"):
        raise AudioError("kind is music, stinger or sfx")
    samples = decode(in_path)
    if mono:
        # Mixed down first, so that the loudness is measured on what will be heard: the same signal from both speakers.
        samples = np.repeat(samples.mean(axis=1, keepdims=True), 2, axis=1)
    report: dict = {"input": in_path, "output": out_path, "kind": kind, "input_seconds": round(len(samples) / RATE, 3)}
    if loop:
        if kind != "music":
            raise AudioError("only music is looped")
        begin = 0.0 if start is None else start
        if start is None:
            # Skip a silent lead-in; the loop starts on sound.
            begin = (len(samples) - len(trim_silence(samples, tail=False, keep=0.0))) / RATE
        limit = usable_end(samples) if end is None else end
        score = None
        if loop_seconds is None:
            loop_seconds, score = find_loop(samples, start=begin, end=limit, crossfade=crossfade)
        samples = fold_loop(samples, start=begin, loop_seconds=loop_seconds, crossfade=crossfade)
        report.update({"loop_start": round(begin, 3), "loop_seconds": round(loop_seconds, 3), "crossfade": crossfade, "usable_end": round(limit, 3), "seam_ratio": round(seam_ratio(samples), 2)})
        if score is not None:
            report["loop_similarity"] = round(score, 3)
    else:
        samples = trim_silence(samples, lead=True, tail=True)
        samples = fade_ends(samples, fade_in=0.003 if kind == "sfx" else 0.008, fade_out=0.02 if kind == "sfx" else 0.06)
    measured = loudness(samples)
    report["input_lufs"] = None if measured is None else round(measured, 2)
    report["input_peak_db"] = round(peak_db(samples), 2)
    if kind == "sfx" or measured is None:
        wanted = (SFX_PEAK_DB if kind == "sfx" else CEILING_DB - 2.0) - peak_db(samples)
    else:
        target = lufs if lufs is not None else (MUSIC_LUFS if kind == "music" else STINGER_LUFS)
        wanted = target - measured
        report["target_lufs"] = target
    samples, applied = apply_gain(samples, wanted)
    report["gain_db"] = round(applied, 2)
    report["gain_held_back_db"] = round(wanted - applied, 2)
    report["peak_db"] = round(peak_db(samples), 2)
    after = loudness(samples)
    report["lufs"] = None if after is None else round(after, 2)
    report["seconds"] = round(len(samples) / RATE, 3)
    report["encoder"] = encode_ogg(samples, out_path, quality=quality if quality is not None else (5.0 if kind != "sfx" else 4.0), mono=mono)
    report["bytes"] = os.path.getsize(out_path)
    return report


def inspect(path: str) -> dict:
    """Facts about an audio file: length, loudness, peak, and how clean its end-to-start seam is."""
    samples = decode(path)
    measured = loudness(samples)
    return {"file": path, "seconds": round(len(samples) / RATE, 3), "lufs": None if measured is None else round(measured, 2), "peak_db": round(peak_db(samples), 2), "seam_ratio": round(seam_ratio(samples), 2), "bytes": os.path.getsize(path)}
