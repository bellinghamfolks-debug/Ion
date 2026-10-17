#!/usr/bin/env python3
"""Download the Saudi Currency Dataset (CC BY 4.0) and describe what it holds.

Maruf, Basuhail, Adil — King Abdulaziz University, Mendeley Data 7sys44td9c v1.
Writes a report: folders, label names from the Pascal VOC annotations and
how many boxes and images each has, image sizes, and a small contact sheet
per label so the series (fifth or sixth issue, paper or polymer) can be told.
"""

from __future__ import annotations

import collections
import json
import random
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

URL = ("https://data.mendeley.com/public-files/datasets/7sys44td9c/files/"
       "3981303c-074b-4d02-80d9-bee52fff9e6f/file_downloaded")


def download(target: Path) -> None:
    if target.exists() and target.stat().st_size > 6_000_000_000:
        return
    request = urllib.request.Request(URL, headers={"User-Agent": "BasirCurrencyResearch/1.0"})
    with urllib.request.urlopen(request, timeout=600) as response, target.open("wb") as out:
        while chunk := response.read(8 * 1024 * 1024):
            out.write(chunk)


def main() -> None:
    work = Path(sys.argv[1])
    out = Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    archive = work / "saudi_currency.zip"
    download(archive)
    report: dict = {"bytes": archive.stat().st_size}
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        report["entries"] = len(names)
        report["top_folders"] = collections.Counter("/".join(n.split("/")[:2]) for n in names).most_common(40)
        report["extensions"] = collections.Counter(Path(n).suffix.lower() for n in names).most_common()
        labels = collections.Counter()
        images_per_label: dict[str, set] = collections.defaultdict(set)
        sizes = collections.Counter()
        xmls = [n for n in names if n.lower().endswith(".xml")]
        for name in xmls:
            try:
                root = ET.fromstring(zf.read(name))
            except ET.ParseError:
                continue
            size = root.find("size")
            if size is not None:
                sizes[f"{size.findtext('width')}x{size.findtext('height')}"] += 1
            for obj in root.iter("object"):
                label = (obj.findtext("name") or "").strip()
                labels[label] += 1
                images_per_label[label].add(root.findtext("filename") or name)
        report["annotation_files"] = len(xmls)
        report["labels"] = {k: {"boxes": v, "images": len(images_per_label[k])} for k, v in labels.most_common()}
        report["image_sizes"] = sizes.most_common(10)
        report["sample_names"] = random.Random(1).sample(names, min(40, len(names)))

        # One small contact sheet per label, to see which series the photos show.
        from PIL import Image

        jpgs = {Path(n).stem: n for n in names if n.lower().endswith((".jpg", ".jpeg", ".png"))}
        for label, files in images_per_label.items():
            picks = [jpgs.get(Path(f).stem) for f in sorted(files)]
            picks = [p for p in picks if p][:6]
            if not picks:
                continue
            tiles = []
            for pick in picks:
                with zf.open(pick) as handle:
                    image = Image.open(handle).convert("RGB")
                    image.thumbnail((320, 320))
                    tiles.append(image)
            sheet = Image.new("RGB", (320 * len(tiles), 320), "white")
            for index, tile in enumerate(tiles):
                sheet.paste(tile, (index * 320, 0))
            safe = "".join(c if c.isalnum() else "_" for c in label)[:40]
            sheet.save(out / f"sheet_{safe}.jpg", quality=70)
    (out / "dataset_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=1))
    print(json.dumps({k: report[k] for k in ("entries", "annotation_files", "labels")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
