#!/usr/bin/env python3
"""Compatibility entry point for durable curriculum vocabulary corrections.

Historically this script only replaced placeholder Arabic glosses. The reviewed
corrections now live in curriculum_quality_fixes.json and include both Arabic
gloss repairs and full replacements for low-value legacy vocabulary. Keeping
this script as a thin compatibility pass ensures old build instructions cannot
reintroduce weaker content.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"
FIXES = ROOT / "Scripts/curriculum_quality_fixes.json"


def normalize_sentence(text: str) -> str:
    value = (text or "").strip()
    value = re.sub(r"([!?])\.+$", r"\1", value)
    value = re.sub(r"\.{2,}$", ".", value)
    return value


def main():
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    data = json.loads(FIXES.read_text(encoding="utf-8"))
    replacements = data.get("vocabularyById", {})
    glosses = data.get("arabicGlossById", {})
    seen = set()
    replaced = gloss_fixed = punctuation_fixed = 0

    for level in catalog.get("levels", []):
        for unit in level.get("units", []):
            for lesson in unit.get("lessons", []):
                if lesson.get("modelSentence"):
                    before = lesson["modelSentence"]
                    lesson["modelSentence"] = normalize_sentence(before)
                    punctuation_fixed += before != lesson["modelSentence"]
                for word in lesson.get("vocabulary", []):
                    wid = word.get("id")
                    if not wid:
                        continue
                    seen.add(wid)
                    if wid in replacements:
                        word.update(replacements[wid])
                        replaced += 1
                    elif wid in glosses:
                        word["arabic"] = glosses[wid]
                        gloss_fixed += 1

    missing = sorted((set(replacements) | set(glosses)) - seen)
    if missing:
        raise SystemExit(f"Correction ids not found in curriculum: {missing}")

    PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    print(f"Applied {replaced} vocabulary replacements, {gloss_fixed} Arabic gloss fixes, "
          f"and {punctuation_fixed} model-sentence punctuation fixes.")


if __name__ == "__main__":
    main()
