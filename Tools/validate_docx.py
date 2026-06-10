#!/usr/bin/env python3
"""Validates basic DOCX ZIP integrity and parses every XML part."""

from __future__ import annotations

import argparse
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

REQUIRED = {
    "[Content_Types].xml",
    "_rels/.rels",
    "word/document.xml",
    "word/_rels/document.xml.rels",
    "word/styles.xml",
}


def validate(path: Path) -> None:
    if not path.is_file():
        raise ValueError(f"File not found: {path}")

    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"CRC failure in: {bad}")

        names = set(archive.namelist())
        missing = REQUIRED - names
        if missing:
            raise ValueError(f"Missing required DOCX entries: {sorted(missing)}")

        for name in sorted(names):
            if name.endswith((".xml", ".rels")) or name == "[Content_Types].xml":
                try:
                    ET.fromstring(archive.read(name))
                except ET.ParseError as exc:
                    raise ValueError(f"Invalid XML in {name}: {exc}") from exc

        media = [name for name in names if name.startswith("word/media/")]
        print(f"Valid DOCX package: {path.name}")
        print(f"Entries: {len(names)}")
        print(f"Embedded media files: {len(media)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    args = parser.parse_args()
    try:
        validate(args.docx)
    except (ValueError, zipfile.BadZipFile) as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
