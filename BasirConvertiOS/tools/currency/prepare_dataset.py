#!/usr/bin/env python3
"""Builds the currency reader's training and test images.

Source: Saudi Currency Dataset (Maruf, Basuhail, Adil; King Abdulaziz
University; Mendeley Data 7sys44td9c v1; CC BY 4.0): 2,000 phone photos, one
note each, with its box.

What the raw photos cannot teach on their own, this adds:

- Each denomination was photographed mostly on one background (a red carpet,
  a wooden table, a white wall). A model trained on them as they are learns
  the background. So every note is cut out by its box and placed on many
  other backgrounds, at other angles, lighting, blur, folds and with fingers
  over it.
- Photos come in bursts of near-identical frames. Test photos are chosen by
  whole capture session, never by frame, so the test never contains a twin
  of a training photo and its score means what it says.
- A "none" class (backgrounds, paper, receipts, cards) so the reader can say
  "this is not a riyal" instead of guessing.

Output: <out>/train/<label>/*.jpg, <out>/test/<label>/*.jpg and stats.json.
"""

from __future__ import annotations

import collections
import io
import json
import math
import random
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

URL = ("https://data.mendeley.com/public-files/datasets/7sys44td9c/files/"
       "3981303c-074b-4d02-80d9-bee52fff9e6f/file_downloaded")
LABELS = {
    "one riyal": "1", "five riyal": "5", "ten riyal": "10", "twenty riyal": "20", "fifty riyal": "50",
    "one hundred riyal": "100", "two hundred riyal": "200", "five hundred riyal": "500",
}
SIZE = 448                 # what the classifier sees; Vision scales to 299 or 360 anyway
SYNTHETIC_PER_NOTE = 5     # composites made from each training cut-out
TEST_FRACTION = 0.18
rng = random.Random(20261017)


def download(target: Path) -> None:
    if target.exists() and target.stat().st_size > 6_000_000_000:
        return
    request = urllib.request.Request(URL, headers={"User-Agent": "BasirCurrencyResearch/1.0"})
    with urllib.request.urlopen(request, timeout=900) as response, target.open("wb") as out:
        while chunk := response.read(8 * 1024 * 1024):
            out.write(chunk)


def session(name: str) -> str:
    """Photos taken in the same moment share a session: a burst, or the same minute."""

    stem = Path(name).stem
    burst = re.match(r"(IMG\d{14})_BURST", stem)
    if burst:
        return burst.group(1)
    plain = re.match(r"IMG_(\d{8})_(\d{4})", stem)
    if plain:
        return plain.group(1) + plain.group(2)
    return stem[:16]


def fit(image: Image.Image, size: int = SIZE) -> Image.Image:
    image = image.copy()
    image.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGB", (size, size), tuple(int(c) for c in image.resize((1, 1)).getpixel((0, 0))))
    canvas.paste(image, ((size - image.width) // 2, (size - image.height) // 2))
    return canvas


def center_crop(image: Image.Image, size: int = SIZE) -> Image.Image:
    return ImageOps.fit(image, (size, size), Image.LANCZOS)


# MARK: Backgrounds and non-currency things

def procedural_background(size: int) -> Image.Image:
    kind = rng.choice(["flat", "gradient", "noise", "wood", "fabric", "tiles"])
    base = tuple(rng.randint(20, 235) for _ in range(3))
    image = Image.new("RGB", (size, size), base)
    draw = ImageDraw.Draw(image)
    if kind == "gradient":
        other = tuple(rng.randint(20, 235) for _ in range(3))
        for y in range(size):
            t = y / size
            draw.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(base, other)))
    elif kind == "noise":
        noise = Image.effect_noise((size, size), rng.uniform(20, 70)).convert("RGB")
        image = Image.blend(image, noise, rng.uniform(0.2, 0.5))
    elif kind == "wood":
        for x in range(0, size, rng.randint(3, 9)):
            shade = tuple(max(0, min(255, c + rng.randint(-25, 25))) for c in base)
            draw.line([(x + rng.randint(-4, 4), 0), (x, size)], fill=shade, width=rng.randint(1, 4))
    elif kind == "fabric":
        step = rng.randint(8, 30)
        accent = tuple(rng.randint(0, 255) for _ in range(3))
        for y in range(0, size, step):
            for x in range(0, size, step):
                if rng.random() < 0.5:
                    draw.ellipse([x, y, x + step // 3, y + step // 3], fill=accent)
    elif kind == "tiles":
        step = rng.randint(40, 120)
        for i in range(0, size, step):
            draw.line([(i, 0), (i, size)], fill=(90, 90, 90), width=2)
            draw.line([(0, i), (size, i)], fill=(90, 90, 90), width=2)
    return image.filter(ImageFilter.GaussianBlur(rng.uniform(0, 1.5)))


def document_like(size: int) -> Image.Image:
    """Paper, receipts and cards: the things most often mistaken for a note."""

    paper = tuple(rng.randint(215, 255) for _ in range(3))
    image = procedural_background(size)
    w, h = int(size * rng.uniform(0.5, 0.95)), int(size * rng.uniform(0.3, 0.9))
    card = Image.new("RGB", (w, h), paper)
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default()
    for y in range(8, h - 8, rng.randint(9, 16)):
        x = 8
        while x < w - 30:
            word = rng.randint(10, 60)
            draw.line([(x, y), (min(w - 8, x + word), y)], fill=tuple(rng.randint(0, 90) for _ in range(3)),
                      width=rng.randint(1, 3))
            x += word + rng.randint(5, 12)
    if rng.random() < 0.4:
        draw.text((10, 10), str(rng.randint(1, 999)), fill=(0, 0, 0), font=font)
    card = card.rotate(rng.uniform(-35, 35), expand=True, fillcolor=None)
    image.paste(card, (rng.randint(0, max(0, size - card.width)), rng.randint(0, max(0, size - card.height))))
    return image


# MARK: Composites

def finger(draw: ImageDraw.ImageDraw, size: int) -> None:
    skin = rng.choice([(224, 172, 140), (198, 134, 96), (141, 85, 54), (241, 194, 162)])
    x, y = rng.randint(0, size), rng.choice([rng.randint(-size // 4, size // 6), rng.randint(size * 5 // 6, size)])
    w, h = rng.randint(size // 10, size // 5), rng.randint(size // 4, size // 2)
    draw.ellipse([x, y, x + w, y + h], fill=skin)


def composite(note: Image.Image, background: Image.Image) -> Image.Image:
    size = background.width
    scale = rng.uniform(0.55, 1.15)
    target = int(size * scale)
    note = note.copy()
    note.thumbnail((target, target), Image.LANCZOS)
    # Perspective: a note held at an angle.
    w, h = note.size
    d = lambda: rng.uniform(0, 0.12)  # noqa: E731
    quad = (w * d(), h * d(), w * d(), h * (1 - d()), w * (1 - d()), h * (1 - d()), w * (1 - d()), h * d())
    note = note.convert("RGBA").transform((w, h), Image.QUAD, quad, Image.BICUBIC)
    note = note.rotate(rng.choice([0, 90, 180, 270]) + rng.uniform(-25, 25), expand=True, resample=Image.BICUBIC)
    # A fold: one half a little darker.
    if rng.random() < 0.3:
        shade = Image.new("RGBA", note.size, (0, 0, 0, 0))
        ImageDraw.Draw(shade).rectangle([0, 0, note.width // 2, note.height], fill=(0, 0, 0, rng.randint(20, 60)))
        note = Image.alpha_composite(note, shade)
    out = background.convert("RGBA")
    # Partly out of frame sometimes, as when held too close.
    x = rng.randint(-note.width // 5, max(-note.width // 5 + 1, size - note.width * 4 // 5))
    y = rng.randint(-note.height // 5, max(-note.height // 5 + 1, size - note.height * 4 // 5))
    out.paste(note, (x, y), note)
    out = out.convert("RGB")
    if rng.random() < 0.5:
        finger(ImageDraw.Draw(out), size)
    out = ImageEnhance.Brightness(out).enhance(rng.uniform(0.45, 1.35))
    out = ImageEnhance.Contrast(out).enhance(rng.uniform(0.7, 1.3))
    out = ImageEnhance.Color(out).enhance(rng.uniform(0.6, 1.3))
    if rng.random() < 0.35:
        tint = Image.new("RGB", out.size, rng.choice([(255, 200, 140), (170, 200, 255), (255, 240, 200)]))
        out = Image.blend(out, tint, rng.uniform(0.05, 0.2))
    if rng.random() < 0.5:
        out = out.filter(ImageFilter.GaussianBlur(rng.uniform(0.3, 2.2)))
    if rng.random() < 0.4:
        noise = Image.effect_noise(out.size, rng.uniform(10, 40)).convert("RGB")
        out = Image.blend(out, noise, rng.uniform(0.03, 0.12))
    buffer = io.BytesIO()
    out.save(buffer, "JPEG", quality=rng.randint(45, 90))
    return Image.open(io.BytesIO(buffer.getvalue())).convert("RGB")


def main() -> None:
    work, out = Path(sys.argv[1]), Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)
    archive = work / "saudi_currency.zip"
    download(archive)

    with zipfile.ZipFile(archive) as zf:
        names = set(zf.namelist())
        records = []
        for name in sorted(n for n in names if n.lower().endswith(".xml")):
            root = ET.fromstring(zf.read(name))
            obj = root.find("object")
            if obj is None:
                continue
            label = LABELS.get((obj.findtext("name") or "").strip().lower())
            box = obj.find("bndbox")
            image_name = str(Path(name).with_suffix(".jpg"))
            if label is None or box is None or image_name not in names:
                continue
            records.append({"image": image_name, "label": label, "session": session(image_name),
                            "box": [int(float(box.findtext(k))) for k in ("xmin", "ymin", "xmax", "ymax")]})

        # Whole sessions go to the test set, per label.
        by_label: dict[str, dict[str, list]] = collections.defaultdict(lambda: collections.defaultdict(list))
        for record in records:
            by_label[record["label"]][record["session"]].append(record)
        test_sessions = set()
        for label, sessions in by_label.items():
            keys = sorted(sessions)
            rng.shuffle(keys)
            target = TEST_FRACTION * sum(len(v) for v in sessions.values())
            taken, chosen = 0, 0
            for key in keys:
                # Always leave most sessions, and at least one, for training.
                if taken >= target or chosen >= len(keys) - 1:
                    break
                test_sessions.add((label, key))
                taken += len(sessions[key])
                chosen += 1

        stats = collections.Counter()
        backgrounds: list[Image.Image] = []
        for index, record in enumerate(records):
            split = "test" if (record["label"], record["session"]) in test_sessions else "train"
            # Boxes are in the stored pixel orientation, so the photo is not rotated by
            # its EXIF tag; orientation does not matter, composites use all four.
            with zf.open(record["image"]) as handle:
                photo = Image.open(handle).convert("RGB")
            stored_width = photo.width
            photo.thumbnail((1400, 1400), Image.LANCZOS)
            factor = photo.width / stored_width
            x0, y0, x1, y1 = [int(v * factor) for v in record["box"]]
            # Some annotations were drawn on the unrotated photo; keep the box inside.
            x0, x1 = sorted((max(0, x0), min(photo.width, x1)))
            y0, y1 = sorted((max(0, y0), min(photo.height, y1)))
            if x1 - x0 < 40 or y1 - y0 < 40:
                continue
            margin = 0.06
            mx, my = int((x1 - x0) * margin), int((y1 - y0) * margin)
            note = photo.crop((max(0, x0 - mx), max(0, y0 - my), min(photo.width, x1 + mx), min(photo.height, y1 + my)))
            folder = out / split / record["label"]
            folder.mkdir(parents=True, exist_ok=True)
            stem = Path(record["image"]).stem
            # The note as the reader sees it when it fills the screen, and the whole photo.
            fit(note).save(folder / f"{stem}_note.jpg", quality=88)
            center_crop(photo).save(folder / f"{stem}_photo.jpg", quality=85)
            stats[f"{split}/{record['label']}"] += 2
            if split == "train":
                for k in range(SYNTHETIC_PER_NOTE):
                    composite(note, procedural_background(SIZE)).save(folder / f"{stem}_syn{k}.jpg", quality=88)
                    stats[f"{split}/{record['label']}"] += 1
            # Background patches away from the note, for "none".
            for _ in range(2):
                side = min(photo.width, photo.height) // 3
                bx, by = rng.randint(0, photo.width - side), rng.randint(0, photo.height - side)
                if bx + side < x0 or bx > x1 or by + side < y0 or by > y1:
                    patch = photo.crop((bx, by, bx + side, by + side)).resize((SIZE, SIZE))
                    (out / split / "none").mkdir(parents=True, exist_ok=True)
                    patch.save(out / split / "none" / f"{stem}_bg{_}.jpg", quality=85)
                    stats[f"{split}/none"] += 1
                    if len(backgrounds) < 300:
                        backgrounds.append(patch)
            if index % 200 == 0:
                print(f"{index}/{len(records)}", dict(stats), flush=True)

        # More "none": paper, receipts, cards, plain surfaces.
        for split, count in (("train", 1600), ("test", 250)):
            folder = out / split / "none"
            folder.mkdir(parents=True, exist_ok=True)
            for k in range(count):
                image = document_like(SIZE) if rng.random() < 0.6 else procedural_background(SIZE)
                image.save(folder / f"other_{k}.jpg", quality=85)
                stats[f"{split}/none"] += 1

    summary = {
        "source": "Saudi Currency Dataset, Maruf, Basuhail, Adil (King Abdulaziz University), "
                  "Mendeley Data 7sys44td9c v1, CC BY 4.0",
        "records": len(records), "test_sessions": len(test_sessions),
        "sessions_per_label": {label: len(s) for label, s in by_label.items()},
        "images": dict(sorted(stats.items())),
    }
    (out / "stats.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1))
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
