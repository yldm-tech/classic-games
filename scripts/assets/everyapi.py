"""The two generation endpoints the asset tools call, and the provenance log.

The API key is read from the environment variable EVERYAPI_KEY at the moment of a request. It is sent in the Authorization header and nowhere else: it is never printed, never written to a file and never put in a provenance record.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.environ.get("EVERYAPI_BASE", "https://api.everyapi.ai").rstrip("/")
IMAGE_MODEL = "doubao-seedream-5.0-pro"
MUSIC_MODEL = "music_v2_5"
# The API's edge refuses the default urllib client signature (HTTP 403, error 1010), so the tools name themselves.
USER_AGENT = "classic-games-assets/1.0"
RETRY_STATUS = {408, 425, 429, 500, 502, 503, 504, 520, 522, 524, 529}
ATTEMPTS = 4


class ApiError(RuntimeError):
    pass


def _key() -> str:
    key = os.environ.get("EVERYAPI_KEY", "").strip()
    if not key:
        raise ApiError("EVERYAPI_KEY is not set; the caller's shell does EVERYAPI_KEY=$(everyapi token key <id>) for the command")
    return key


def _post(path: str, payload: dict, timeout: float = 300.0) -> tuple[bytes, str]:
    """POST JSON and return (body, content type). Retries what is worth retrying, with a growing pause."""
    body = json.dumps(payload).encode("utf-8")
    last = "no attempt was made"
    for attempt in range(ATTEMPTS):
        if attempt:
            pause = min(60.0, 4.0 * 2 ** (attempt - 1))
            print("%s: %s; trying again in %.0fs (attempt %d of %d)" % (path, last, pause, attempt + 1, ATTEMPTS), file=sys.stderr, flush=True)
            time.sleep(pause)
        request = urllib.request.Request(BASE_URL + path, data=body, method="POST", headers={"Authorization": "Bearer " + _key(), "Content-Type": "application/json", "Accept": "*/*", "User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read(), response.headers.get("Content-Type", "")
        except urllib.error.HTTPError as error:
            detail = error.read()[:400].decode("utf-8", "replace")
            last = "HTTP %d: %s" % (error.code, detail)
            if error.code not in RETRY_STATUS:
                break
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last = "network: %s" % error
    raise ApiError("%s failed: %s" % (path, last))


def _download(url: str, timeout: float = 300.0) -> bytes:
    last = ""
    for attempt in range(ATTEMPTS):
        if attempt:
            time.sleep(min(30.0, 2.0 * 2 ** (attempt - 1)))
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last = str(error)
    raise ApiError("downloading the result failed: %s" % last)


def data_url(path: str) -> str:
    with open(path, "rb") as handle:
        raw = handle.read()
    kind = "image/png" if raw[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
    return "data:%s;base64,%s" % (kind, base64.b64encode(raw).decode("ascii"))


def generate_image(prompt: str, size: str = "1024x1024", reference: str | None = None, transparent: bool = False, model: str = IMAGE_MODEL) -> bytes:
    """One picture. With `reference` (a file) the model keeps the design it shows; `transparent` asks for an RGBA PNG, which the model only returns when the reference is itself a PNG with transparent pixels."""
    payload: dict = {"model": model, "prompt": prompt, "size": size, "watermark": False}
    if reference:
        payload["image"] = data_url(reference)
    if transparent:
        payload["background"] = "transparent"
        payload["output_format"] = "png"
    body, _ = _post("/v1/images/generations", payload)
    try:
        entry = json.loads(body)["data"][0]
    except (ValueError, KeyError, IndexError, TypeError) as error:
        raise ApiError("the image endpoint returned something unexpected: %s" % body[:200].decode("utf-8", "replace")) from error
    if entry.get("b64_json"):
        return base64.b64decode(entry["b64_json"])
    if entry.get("url"):
        return _download(entry["url"])
    raise ApiError("the image endpoint returned neither a URL nor image data")


def generate_music(prompt: str, seconds: float, model: str = MUSIC_MODEL) -> bytes:
    """One piece of music as MP3 bytes."""
    body, content_type = _post("/v1/music", {"model": model, "prompt": prompt, "music_length_ms": int(round(seconds * 1000))})
    if "json" in content_type or body[:1] == b"{":
        raise ApiError("the music endpoint returned no audio: %s" % body[:300].decode("utf-8", "replace"))
    return body


def log_provenance(log_path: str, record: dict) -> None:
    """Append one generation to a JSON-lines file, so a game's ASSETS.md can say truthfully where each file came from."""
    directory = os.path.dirname(os.path.abspath(log_path))
    os.makedirs(directory, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
