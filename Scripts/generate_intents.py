#!/usr/bin/env python3
"""Regenerates the DrinkChoice enum in CoffeeIntents.swift from BeverageID.

App Intents reads display names at build time, so they must be literals.
Run after adding or renaming a drink; --check fails if the file is stale.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRINGS = ROOT / "CoffeeAccess/Core/Localization/Strings.swift"
BEVERAGE = ROOT / "CoffeeAccess/Core/Model/Beverage.swift"
INTENTS = ROOT / "CoffeeAccess/Intents/CoffeeIntents.swift"


def build() -> str:
    names = dict(re.findall(r'"drink\.(\w+)\.name": \("([^"]+)"', STRINGS.read_text(encoding="utf-8")))
    body = re.search(r"enum BeverageID\b[^{]*\{(.*?)\n    var id", BEVERAGE.read_text(encoding="utf-8"), re.S).group(1)
    cases = [c.strip() for line in body.splitlines() if line.strip().startswith("case ")
             for c in line.strip()[5:].split(",") if c.strip()]
    missing = [c for c in cases if c not in names]
    if missing:
        raise SystemExit(f"drinks without an Arabic name: {missing}")
    case_lines = ["    case " + ", ".join(cases[i:i + 6]) for i in range(0, len(cases), 6)]
    reps = ",\n".join(f'        .{c}: "{names[c]}"' for c in cases)
    return (
        "/// Drinks as a Siri / Shortcuts parameter. Generated from BeverageID by\n"
        "/// Scripts/generate_intents.py; App Intents needs literal display names.\n"
        "enum DrinkChoice: String, AppEnum {\n"
        + "\n".join(case_lines)
        + '\n\n    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Drink"\n\n'
        "    static var caseDisplayRepresentations: [DrinkChoice: DisplayRepresentation] = [\n"
        + reps
        + ",\n    ]\n\n    var beverage: BeverageID { BeverageID(rawValue: rawValue) ?? .coffee }\n}\n\n"
    )


def main() -> int:
    source = INTENTS.read_text(encoding="utf-8")
    start = source.index("/// Drinks as a Siri / Shortcuts parameter.")
    end = source.index("enum StrengthChoice")
    updated = source[:start] + build() + source[end:]
    if "--check" in sys.argv:
        if updated != source:
            print("CoffeeIntents.swift is out of date; run Scripts/generate_intents.py")
            return 1
        print("Intents drink list: PASS")
        return 0
    INTENTS.write_text(updated, encoding="utf-8")
    print("Intents drink list regenerated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
