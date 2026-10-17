#!/usr/bin/env python3
"""Builds test images that look like what the reader's camera sees.

The first measurement tested photos from the same notes on the same
backgrounds the model was trained on, so it could not see that the model had
learned the backgrounds. These tests take that away:

- field/<label>: each note cut out tightly and placed on a background from a
  *different* denomination's photos (or a generated one), in a portrait
  720x1280 frame like the iPhone's, filling 60-110% of its width (so the
  centre square the model looks at may cut it), at any of four orientations,
  with lighting, blur and fingers.
- field/none: the same frames with no note, including paper with prices
  printed on it ("50", "SAR 100"), which a reader that trusts digits alone
  would call a note.
- photos/<label>: the dataset's own photos, unchanged apart from size, for
  reading the printed number.

usage: make_field_tests.py <work dir with the dataset zip> <out dir>
"""

from __future__ import annotations

import collections
import io
import json
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_dataset as base  # noqa: E402

rng = base.rng
PER_LABEL = 60
W, H = 720, 1280
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def scene(note: Image.Image, background: Image.Image) -> tuple[Image.Image, str]:
    frame = ImageOps.fit(background, (W, H), Image.LANCZOS)
    if note.height > note.width:
        note = note.rotate(90, expand=True)
    pose = rng.choice(["horizontal", "horizontal", "horizontal_flipped", "vertical", "vertical_flipped"])
    if pose.startswith("horizontal"):
        width = int(W * rng.uniform(0.6, 1.1))
        note = note.resize((width, int(note.height * width / note.width)), Image.LANCZOS)
        if pose.endswith("flipped"):
            note = note.rotate(180)
    else:
        height = int(H * rng.uniform(0.45, 0.85))
        note = note.rotate(90 if pose == "vertical" else 270, expand=True)
        scale = height / note.height
        note = note.resize((int(note.width * scale), height), Image.LANCZOS)
    note = note.convert("RGBA").rotate(rng.uniform(-12, 12), expand=True, resample=Image.BICUBIC)
    x = (W - note.width) // 2 + int(W * rng.uniform(-0.1, 0.1))
    y = (H - note.height) // 2 + int(H * rng.uniform(-0.12, 0.12))
    out = frame.convert("RGBA")
    out.paste(note, (x, y), note)
    return finish(out.convert("RGB")), pose


def finish(out: Image.Image) -> Image.Image:
    if rng.random() < 0.4:
        base.finger(ImageDraw.Draw(out), W)
    out = ImageEnhance.Brightness(out).enhance(rng.uniform(0.55, 1.25))
    out = ImageEnhance.Contrast(out).enhance(rng.uniform(0.8, 1.2))
    if rng.random() < 0.4:
        out = out.filter(ImageFilter.GaussianBlur(rng.uniform(0.3, 1.6)))
    buffer = io.BytesIO()
    out.save(buffer, "JPEG", quality=rng.randint(60, 90))
    return Image.open(io.BytesIO(buffer.getvalue())).convert("RGB")


def price_paper(background: Image.Image) -> Image.Image:
    """Paper with a denomination-like number on it: a receipt, a price tag."""

    frame = ImageOps.fit(background, (W, H), Image.LANCZOS)
    paper = Image.new("RGB", (int(W * rng.uniform(0.5, 0.9)), int(H * rng.uniform(0.2, 0.5))),
                      tuple(rng.randint(225, 255) for _ in range(3)))
    draw = ImageDraw.Draw(paper)
    value = rng.choice(["5", "10", "20", "50", "100", "200", "500"])
    text = rng.choice([value, f"SAR {value}", f"{value}.00", f"Total {value}"])
    try:
        font = ImageFont.truetype(FONT, rng.randint(40, 110))
    except OSError:
        font = ImageFont.load_default()
    draw.text((20, 20), text, fill=(20, 20, 20), font=font)
    frame.paste(paper, ((W - paper.width) // 2, (H - paper.height) // 2))
    return finish(frame)


def main() -> None:
    work, out = Path(sys.argv[1]), Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)
    archive = work / "saudi_currency.zip"
    base.download(archive)
    stats: dict[str, int] = collections.Counter()
    poses: dict[str, str] = {}
    with zipfile.ZipFile(archive) as zf:
        names = set(zf.namelist())
        records = collections.defaultdict(list)
        for name in sorted(n for n in names if n.lower().endswith(".xml")):
            root = ET.fromstring(zf.read(name))
            obj = root.find("object")
            label = base.LABELS.get(((obj.findtext("name") if obj is not None else "") or "").strip().lower())
            image_name = str(Path(name).with_suffix(".jpg"))
            box = obj.find("bndbox") if obj is not None else None
            if label and box is not None and image_name in names:
                records[label].append((image_name, [int(float(box.findtext(k))) for k in ("xmin", "ymin", "xmax", "ymax")]))

        # Spread over sessions, not one burst.
        chosen = {label: sorted(items)[:: max(1, len(items) // PER_LABEL)][:PER_LABEL] for label, items in records.items()}
        notes, backgrounds = {}, collections.defaultdict(list)
        for label, items in chosen.items():
            for image_name, box in items:
                with zf.open(image_name) as handle:
                    photo = Image.open(handle).convert("RGB")
                stored = photo.width
                photo.thumbnail((1280, 1280), Image.LANCZOS)
                f = photo.width / stored
                x0, y0, x1, y1 = [int(v * f) for v in box]
                x0, x1 = sorted((max(0, x0), min(photo.width, x1)))
                y0, y1 = sorted((max(0, y0), min(photo.height, y1)))
                if x1 - x0 < 60 or y1 - y0 < 60:
                    continue
                stem = Path(image_name).stem
                folder = out / "photos" / label
                folder.mkdir(parents=True, exist_ok=True)
                photo.save(folder / f"{stem}.jpg", quality=90)
                stats[f"photos/{label}"] += 1
                notes[(label, stem)] = photo.crop((x0, y0, x1, y1))
                # A background strip beside the note, for other labels' scenes.
                side = min(photo.width, photo.height) // 2
                for bx, by in ((0, 0), (photo.width - side, photo.height - side)):
                    if bx + side < x0 or bx > x1 or by + side < y0 or by > y1:
                        backgrounds[label].append(photo.crop((bx, by, bx + side, by + side)))

        for (label, stem), note in notes.items():
            others = [b for other, items in backgrounds.items() if other != label for b in items]
            background = rng.choice(others) if others and rng.random() < 0.7 else base.procedural_background(900)
            image, pose = scene(note, background)
            folder = out / "field" / label
            folder.mkdir(parents=True, exist_ok=True)
            image.save(folder / f"{stem}.jpg", quality=90)
            poses[f"{label}/{stem}"] = pose
            stats[f"field/{label}"] += 1

        everything = [b for items in backgrounds.values() for b in items]
        folder = out / "field" / "none"
        folder.mkdir(parents=True, exist_ok=True)
        for k in range(160):
            if k % 2 == 0:
                image = price_paper(rng.choice(everything) if everything else base.procedural_background(900))
            else:
                image = finish(ImageOps.fit(rng.choice(everything) if everything and k % 4 == 1
                                            else base.document_like(900), (W, H)))
            image.save(folder / f"none_{k}.jpg", quality=90)
            stats["field/none"] += 1

    (out / "poses.json").write_text(json.dumps(poses, indent=0))
    (out / "stats.json").write_text(json.dumps(dict(sorted(stats.items())), indent=1))
    print(json.dumps(dict(sorted(stats.items()))))


if __name__ == "__main__":
    main()
