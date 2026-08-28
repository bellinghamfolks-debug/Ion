#!/usr/bin/env python3
"""Verify the recovered EnglishNova 1.0.0 (build 50) release fingerprint.

This guard checks only release facts that were recoverable from the provided
IPA and can be matched deterministically to source.
"""
from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "1.0.0"
EXPECTED_BUILD = "50"
EXPECTED_BUNDLE_ID = "com.englishnova.app"
EXPECTED_FILES = {
    Path("EnglishNova/Resources/Curriculum/curriculum.json"):
        "e43841428127c522a356472a8a6224e49c6b5eb16f647efcfbea934e2b722342",
    Path("EnglishNova/Resources/LocalizationData/translations.json"):
        "aa22188327185049a637a0cd15d024c9408be0e86f9e88cbdcea5c881b8578e3",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"release fingerprint mismatch: {message}")


def verify_source() -> None:
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    build = re.search(r"(?m)^\s*CURRENT_PROJECT_VERSION:\s*([^\s#]+)", project)
    version = re.search(r"(?m)^\s*MARKETING_VERSION:\s*([^\s#]+)", project)
    require(bool(build), "CURRENT_PROJECT_VERSION is missing from project.yml")
    require(bool(version), "MARKETING_VERSION is missing from project.yml")
    require(build.group(1).strip("\"'") == EXPECTED_BUILD,
            f"source build is {build.group(1)}, expected {EXPECTED_BUILD}")
    require(version.group(1).strip("\"'") == EXPECTED_VERSION,
            f"source version is {version.group(1)}, expected {EXPECTED_VERSION}")

    for relative, expected in EXPECTED_FILES.items():
        path = ROOT / relative
        require(path.is_file(), f"missing source resource: {relative}")
        actual = sha256(path)
        require(actual == expected,
                f"{relative} SHA-256 is {actual}, expected {expected}")


def verify_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle does not exist: {app}")
    info_path = app / "Info.plist"
    require(info_path.is_file(), f"missing {info_path}")
    with info_path.open("rb") as file:
        info = plistlib.load(file)

    require(str(info.get("CFBundleIdentifier", "")) == EXPECTED_BUNDLE_ID,
            f"bundle id is {info.get('CFBundleIdentifier')}, expected {EXPECTED_BUNDLE_ID}")
    require(str(info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
            f"bundle version is {info.get('CFBundleShortVersionString')}, expected {EXPECTED_VERSION}")
    require(str(info.get("CFBundleVersion", "")) == EXPECTED_BUILD,
            f"bundle build is {info.get('CFBundleVersion')}, expected {EXPECTED_BUILD}")

    bundle_files = {
        Path("Curriculum/curriculum.json"): EXPECTED_FILES[
            Path("EnglishNova/Resources/Curriculum/curriculum.json")
        ],
        Path("LocalizationData/translations.json"): EXPECTED_FILES[
            Path("EnglishNova/Resources/LocalizationData/translations.json")
        ],
    }
    for relative, expected in bundle_files.items():
        path = app / relative
        require(path.is_file(), f"missing app resource: {relative}")
        actual = sha256(path)
        require(actual == expected,
                f"app {relative} SHA-256 is {actual}, expected {expected}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="also verify a built .app bundle")
    args = parser.parse_args()
    verify_source()
    if args.app:
        verify_app(args.app)
    print("EnglishNova recovery fingerprint OK: 1.0.0 build 50")


if __name__ == "__main__":
    main()
