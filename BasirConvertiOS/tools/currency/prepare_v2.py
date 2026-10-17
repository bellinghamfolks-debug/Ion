#!/usr/bin/env python3
"""Builds the second training set, so the model learns the notes, not the photos.

What went wrong with the first model: the photo set has one face of each
note, one physical note per denomination, and one background per
denomination, and the test shared all three. The model learned backgrounds
and scored 99% on a test that could not catch it; on a real phone it named
wrong values.

This set:
- Draws notes from clean images of both faces of each design whose licence
  is open (references/, credited in references/CREDITS.md; the reader is
  free and non-commercial), plus the photo set's notes cut out tightly with
  no background.
- Places every note on a background that says nothing about its value
  (generated surfaces, paper, and backgrounds from all denominations' photos
  mixed), in a portrait frame like the iPhone's, in any orientation, often
  cut by the frame, bent, shaded, blurred and partly covered by fingers, then
  takes the centre square exactly as the app does.
- Tests on photo-set notes from held-out sessions on foreign backgrounds
  (real photos the model never saw), and on new scenes of each design drawn
  apart from the training scenes.

usage: prepare_v2.py <work dir> <out dir>
Output: <out>/train/<label>, <out>/test_scans/<label>,
        <out>/test_photos_field/<label>, stats.json
"""

from __future__ import annotations

import collections
import io
import json
import math
import random
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare_dataset as base  # noqa: E402

rng = random.Random(20261018)
base.rng = rng
W, H = 720, 1280
SIZE = 448
PER_SCAN = 180          # training scenes per clean face image
PER_PHOTO_NOTE = 3      # training scenes per photo-set cut-out
TEST_PER_SCAN = 30
NONE_TRAIN, NONE_TEST = 2400, 300
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"


def fetch_references(folder: Path) -> list[dict]:
    folder.mkdir(parents=True, exist_ok=True)
    entries = json.loads((HERE / "references.json").read_text())
    ok = []
    for entry in entries:
        if entry.get("use") != "train":
            continue
        target = folder / entry["file"]
        # The openly licensed images are kept in the repository (references/,
        # with their credits); the source site refuses downloads from CI.
        local = HERE / "references" / entry["file"]
        if local.exists() and not target.exists():
            target.write_bytes(local.read_bytes())
        if not target.exists():
            for attempt in range(4):
                try:
                    request = urllib.request.Request(entry["url"], headers={"User-Agent": AGENT, "Referer": entry["source"]})
                    with urllib.request.urlopen(request, timeout=120) as response:
                        target.write_bytes(response.read())
                    break
                except Exception as error:  # noqa: BLE001
                    print("fetch failed", entry["file"], error, flush=True)
                    time.sleep(3 * (attempt + 1))
        if target.exists():
            try:
                with Image.open(target) as image:
                    entry["got"] = list(image.size)
                ok.append(entry)
            except Exception as error:  # noqa: BLE001
                print("unreadable", entry["file"], error)
    return ok


# MARK: Making a flat image look photographed

def worn(note: Image.Image) -> Image.Image:
    """A scan is cleaner than any note in a hand: soften it, age it, light it unevenly."""

    note = note.convert("RGB")
    long_side = rng.randint(500, 1100)
    note.thumbnail((long_side, long_side), Image.LANCZOS)
    note = ImageEnhance.Contrast(note).enhance(rng.uniform(0.7, 1.05))
    note = ImageEnhance.Color(note).enhance(rng.uniform(0.75, 1.15))
    if rng.random() < 0.6:
        paper = Image.effect_noise(note.size, rng.uniform(15, 45)).convert("RGB")
        note = Image.blend(note, paper, rng.uniform(0.03, 0.10))
    if rng.random() < 0.5:   # uneven light across the note
        w, h = note.size
        mask = Image.linear_gradient("L").resize((w, h)).rotate(rng.choice([0, 90, 180, 270]), expand=False).resize((w, h))
        dark = ImageEnhance.Brightness(note).enhance(rng.uniform(0.55, 0.85))
        note = Image.composite(note, dark, mask)
    return note


def bend(note: Image.Image) -> Image.Image:
    """A gentle wave along the long side, as a held note curves."""

    if rng.random() < 0.45:
        return note
    w, h = note.size
    amplitude = rng.uniform(0.01, 0.05) * h
    period = rng.uniform(0.8, 2.0) * w
    phase = rng.uniform(0, math.tau)
    strips = max(8, w // 24)
    out = Image.new("RGBA", (w, int(h + 2 * amplitude) + 2), (0, 0, 0, 0))
    rgba = note.convert("RGBA")
    for i in range(strips):
        x0, x1 = i * w // strips, (i + 1) * w // strips
        dy = amplitude * (1 + math.sin(phase + math.tau * x0 / period))
        out.paste(rgba.crop((x0, 0, x1, h)), (x0, int(dy)))
    return out


def place(note: Image.Image, background: Image.Image) -> Image.Image:
    frame = ImageOps.fit(background.convert("RGB"), (W, H), Image.LANCZOS)
    if note.height > note.width:
        note = note.rotate(90, expand=True)
    note = bend(note).convert("RGBA")
    pose = rng.random()
    if pose < 0.6:            # held across the phone, either way up
        width = int(W * rng.uniform(0.5, 1.2))
        note = note.resize((width, max(1, int(note.height * width / note.width))), Image.LANCZOS)
        if rng.random() < 0.5:
            note = note.rotate(180)
    else:                     # held along the phone
        height = int(H * rng.uniform(0.4, 0.9))
        note = note.rotate(rng.choice([90, 270]), expand=True)
        note = note.resize((max(1, int(note.width * height / note.height)), height), Image.LANCZOS)
    # Perspective.
    w, h = note.size
    d = lambda: rng.uniform(0, 0.1)  # noqa: E731
    quad = (w * d(), h * d(), w * d(), h * (1 - d()), w * (1 - d()), h * (1 - d()), w * (1 - d()), h * d())
    note = note.transform((w, h), Image.QUAD, quad, Image.BICUBIC)
    note = note.rotate(rng.uniform(-18, 18), expand=True, resample=Image.BICUBIC)
    if rng.random() < 0.3:    # a fold shadow
        shade = Image.new("RGBA", note.size, (0, 0, 0, 0))
        ImageDraw.Draw(shade).rectangle([0, 0, note.width // 2, note.height], fill=(0, 0, 0, rng.randint(15, 55)))
        note = Image.alpha_composite(note, shade)
    x = (W - note.width) // 2 + int(W * rng.uniform(-0.15, 0.15))
    y = (H - note.height) // 2 + int(H * rng.uniform(-0.15, 0.15))
    frame = frame.convert("RGBA")
    frame.paste(note, (x, y), note)
    return frame.convert("RGB")


def camera(frame: Image.Image) -> Image.Image:
    """Phone camera effects, then the centre square the app's model sees."""

    if rng.random() < 0.5:
        base.finger(ImageDraw.Draw(frame), W)
    frame = ImageEnhance.Brightness(frame).enhance(rng.uniform(0.45, 1.3))
    frame = ImageEnhance.Contrast(frame).enhance(rng.uniform(0.75, 1.25))
    if rng.random() < 0.35:
        tint = Image.new("RGB", frame.size, rng.choice([(255, 196, 130), (170, 200, 255), (255, 240, 205)]))
        frame = Image.blend(frame, tint, rng.uniform(0.05, 0.22))
    if rng.random() < 0.5:
        frame = frame.filter(ImageFilter.GaussianBlur(rng.uniform(0.4, 2.4)))
    if rng.random() < 0.4:
        noise = Image.effect_noise(frame.size, rng.uniform(10, 40)).convert("RGB")
        frame = Image.blend(frame, noise, rng.uniform(0.03, 0.12))
    square = ImageOps.fit(frame, (W, W), Image.LANCZOS).resize((SIZE, SIZE), Image.LANCZOS)
    buffer = io.BytesIO()
    square.save(buffer, "JPEG", quality=rng.randint(55, 90))
    return Image.open(io.BytesIO(buffer.getvalue())).convert("RGB")


def nothing(backgrounds: list[Image.Image]) -> Image.Image:
    """A frame with no riyal note: surfaces, paper, receipts with prices."""

    roll = rng.random()
    bg = rng.choice(backgrounds) if backgrounds and roll < 0.4 else base.procedural_background(900)
    frame = ImageOps.fit(bg, (W, H), Image.LANCZOS)
    if roll > 0.55:
        paper = Image.new("RGB", (int(W * rng.uniform(0.4, 0.95)), int(H * rng.uniform(0.15, 0.5))),
                          tuple(rng.randint(200, 255) for _ in range(3)))
        draw = ImageDraw.Draw(paper)
        try:
            font = ImageFont.truetype(FONT, rng.randint(30, 100))
        except OSError:
            font = ImageFont.load_default()
        if rng.random() < 0.6:
            draw.text((16, 16), rng.choice(["5", "10", "50", "100", "200", "500", "SAR 50", "Total 100"]),
                      fill=(20, 20, 20), font=font)
        for yy in range(int(paper.height * 0.5), paper.height - 10, 14):
            draw.line([(16, yy), (paper.width - rng.randint(16, 120), yy)], fill=(70, 70, 70), width=2)
        paper = paper.rotate(rng.uniform(-30, 30), expand=True, fillcolor=None)
        frame.paste(paper, ((W - paper.width) // 2, (H - paper.height) // 2))
    return camera(frame)


def main() -> None:
    work, out = Path(sys.argv[1]), Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)
    stats: dict[str, int] = collections.Counter()

    references = fetch_references(work / "references")
    print("references fetched:", len(references), "of", len(json.loads((HERE / "references.json").read_text())), flush=True)
    stats["references_fetched"] = len(references)

    # The photo set: tight cut-outs, and backgrounds from every denomination mixed.
    archive = work / "saudi_currency.zip"
    base.download(archive)
    photo_notes: dict[str, list[tuple[str, Image.Image]]] = collections.defaultdict(list)
    backgrounds: list[Image.Image] = []
    with zipfile.ZipFile(archive) as zf:
        names = set(zf.namelist())
        records = []
        for name in sorted(n for n in names if n.lower().endswith(".xml")):
            root = ET.fromstring(zf.read(name))
            obj = root.find("object")
            label = base.LABELS.get(((obj.findtext("name") if obj is not None else "") or "").strip().lower())
            box = obj.find("bndbox") if obj is not None else None
            image_name = str(Path(name).with_suffix(".jpg"))
            if label and box is not None and image_name in names:
                records.append((label, base.session(image_name), image_name,
                                [int(float(box.findtext(k))) for k in ("xmin", "ymin", "xmax", "ymax")]))
        # Every 4th photo is enough: they come in bursts of near twins.
        records = records[::4]
        sessions = collections.defaultdict(set)
        for label, session, _, _ in records:
            sessions[label].add(session)
        held_out = {(label, s) for label, ss in sessions.items() for s in sorted(ss)[::5]}
        for label, session, image_name, box in records:
            with zf.open(image_name) as handle:
                photo = Image.open(handle).convert("RGB")
            stored = photo.width
            photo.thumbnail((1200, 1200), Image.LANCZOS)
            f = photo.width / stored
            x0, y0, x1, y1 = [int(v * f) for v in box]
            x0, x1 = sorted((max(0, x0), min(photo.width, x1)))
            y0, y1 = sorted((max(0, y0), min(photo.height, y1)))
            if x1 - x0 < 60 or y1 - y0 < 60:
                continue
            # Inset a little so no background is left at the edges.
            ix, iy = int((x1 - x0) * 0.03), int((y1 - y0) * 0.03)
            note = photo.crop((x0 + ix, y0 + iy, x1 - ix, y1 - iy))
            split = "test" if (label, session) in held_out else "train"
            photo_notes[split].append((label, note))
            side = min(photo.width, photo.height) // 2
            for bx, by in ((0, 0), (photo.width - side, photo.height - side)):
                if (bx + side < x0 or bx > x1 or by + side < y0 or by > y1) and len(backgrounds) < 600:
                    backgrounds.append(photo.crop((bx, by, bx + side, by + side)))
    print("photo notes:", {k: len(v) for k, v in photo_notes.items()}, "backgrounds:", len(backgrounds), flush=True)

    def background() -> Image.Image:
        roll = rng.random()
        if roll < 0.35 and backgrounds:
            return rng.choice(backgrounds)
        if roll < 0.5:
            return base.document_like(900)
        return base.procedural_background(900)

    def save(split: str, label: str, image: Image.Image, stem: str) -> None:
        folder = out / split / label
        folder.mkdir(parents=True, exist_ok=True)
        image.save(folder / f"{stem}.jpg", quality=88)
        stats[f"{split}/{label}"] += 1

    for entry in references:
        label = str(entry["value"])
        with Image.open(work / "references" / entry["file"]) as raw:
            scan = raw.convert("RGB")
            scan.thumbnail((1600, 1600), Image.LANCZOS)
        stem = Path(entry["file"]).stem
        for k in range(PER_SCAN):
            save("train", label, camera(place(worn(scan), background())), f"{stem}_{k}")
        for k in range(TEST_PER_SCAN):
            save("test_scans", label, camera(place(worn(scan), background())), f"{stem}_{k}")
        print("scan", entry["file"], entry["use"], flush=True)

    for split, items in photo_notes.items():
        for index, (label, note) in enumerate(items):
            if split == "train":
                for k in range(PER_PHOTO_NOTE):
                    save("train", label, camera(place(note, background())), f"photo{index}_{k}")
            else:
                save("test_photos_field", label, camera(place(note, background())), f"photo{index}")

    for k in range(NONE_TRAIN):
        save("train", "none", nothing(backgrounds), f"none{k}")
    for split in ("test_scans", "test_photos_field"):
        for k in range(NONE_TEST // 2):
            save(split, "none", nothing(backgrounds), f"none{k}")

    (out / "stats.json").write_text(json.dumps(dict(sorted(stats.items())), indent=1))
    print(json.dumps(dict(sorted(stats.items()))))


if __name__ == "__main__":
    main()
