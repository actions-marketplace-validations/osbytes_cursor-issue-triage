#!/usr/bin/env python3
"""Read an issue body file; emit a JSON array for Cursor Cloud Agents API v0 prompt.images."""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

MAX_IMAGES = 5
MAX_BYTES = 15 * 1024 * 1024


def extract_https_image_urls(text: str) -> list[str]:
    """Markdown ![...](https://...) first (body order), then HTML <img src=\"https://...\"> (body order), deduped."""
    md = re.findall(r"!\[[^\]]*\]\((https://[^)]+)\)", text)
    html = re.findall(r"<img[^>]+src=[\"']?(https://[^\"'>\s]+)", text, flags=re.I)
    seen: set[str] = set()
    out: list[str] = []
    for url in md + html:
        if url in seen:
            continue
        seen.add(url)
        out.append(url)
        if len(out) >= MAX_IMAGES:
            break
    return out


def dims_for_file(path: str) -> tuple[int | None, int | None]:
    try:
        out = subprocess.check_output(["file", "-b", path], text=True)
    except (subprocess.CalledProcessError, OSError):
        return None, None
    m = re.search(r"(\d+)\s*x\s*(\d+)", out)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def fetch_image(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "github-issue-ai-triage/1.0 (encode-cursor-issue-images)",
        },
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        chunk = resp.read(MAX_BYTES + 1)
    if len(chunk) > MAX_BYTES:
        raise ValueError("image too large")
    return chunk


def main() -> None:
    if len(sys.argv) != 2:
        print("[]", end="")
        return
    path = sys.argv[1]
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        print("[]", end="")
        return

    images: list[dict] = []
    for url in extract_https_image_urls(text):
        try:
            raw = fetch_image(url)
        except (urllib.error.URLError, urllib.error.HTTPError, ValueError, TimeoutError, OSError):
            continue

        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(raw)
            tmp_path = tmp.name

        try:
            width, height = dims_for_file(tmp_path)
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

        item: dict = {"data": base64.standard_b64encode(raw).decode("ascii")}
        if width is not None and height is not None:
            item["dimension"] = {"width": width, "height": height}
        images.append(item)

    json.dump(images, sys.stdout)


if __name__ == "__main__":
    main()
