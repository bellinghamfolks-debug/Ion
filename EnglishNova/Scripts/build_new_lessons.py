#!/usr/bin/env python3
"""Inject newly authored seed lessons into the upper CEFR levels.

The A2–C1 levels shipped with only 8 lessons each — a stub compared with the
60-lesson A0/A1 foundations. New lessons are authored as compact *seeds*
(title, objective, model sentence + its Arabic, and a vocabulary list) under
Scripts/new_lessons/<level>_partN.json; this script slots them into
curriculum.json as proper units/lessons. expand_curriculum.py then turns each
seed into the same full ~27-exercise arc the rest of the course uses, so the
new lessons are structurally identical to the hand-built ones.

Run order:  build_new_lessons.py  ->  expand_curriculum.py

Idempotent: every run first drops any previously injected '<prefix>-x-*' units
before re-adding them, so re-authoring and re-running is safe.

Seed file schema (per file):
{
  "level": "A2",
  "units": [
    { "id": "a2-x-u1", "titleAr": "...", "titleEn": "...",
      "descriptionAr": "...", "icon": "<SF Symbol>",
      "lessons": [
        { "id": "a2-x-u1-l1", "titleAr": "...", "titleEn": "...",
          "objectiveAr": "...", "modelSentence": "...",
          "modelSentenceArabic": "...",
          "vocabulary": [ {english,arabic,example,exampleArabic,partOfSpeech,phonetic}, ... ] },
        ...
      ] },
    ...
  ]
}
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"
SEED_DIR = ROOT / "Scripts/new_lessons"

PREFIX = {"A2": "a2", "B1": "b1", "B2": "b2", "C1": "c1"}


def load_seeds():
    """level code -> list of authored unit dicts (merged across part files)."""
    by_level: dict[str, list] = {}
    if not SEED_DIR.is_dir():
        return by_level
    for f in sorted(SEED_DIR.glob("*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        code = data["level"]
        by_level.setdefault(code, []).extend(data.get("units", []))
    return by_level


def build_unit(code, unit, start_order):
    uid = unit["id"]
    out = {
        "id": uid,
        "order": start_order,
        "titleAr": unit["titleAr"],
        "titleEn": unit["titleEn"],
        "descriptionAr": unit.get("descriptionAr", ""),
        "icon": unit.get("icon", "sparkles"),
        "lessons": [],
    }
    for li, lesson in enumerate(unit["lessons"], start=1):
        lid = lesson["id"]
        vocab = []
        for wi, w in enumerate(lesson["vocabulary"], start=1):
            vocab.append({
                "id": f"{lid}-w{wi}",
                "english": w["english"].strip(),
                "arabic": w["arabic"].strip(),
                "example": (w.get("example") or "").strip(),
                "exampleArabic": (w.get("exampleArabic") or "").strip(),
                "partOfSpeech": (w.get("partOfSpeech") or "").strip(),
                "phonetic": w.get("phonetic") or None,
            })
        out["lessons"].append({
            "id": lid,
            "order": li,
            "titleAr": lesson["titleAr"],
            "titleEn": lesson["titleEn"],
            "objectiveAr": lesson["objectiveAr"],
            "estimatedMinutes": 10,   # recomputed by expand_curriculum.py
            "points": 10,             # recomputed by expand_curriculum.py
            "vocabulary": vocab,
            "exercises": [],          # filled by expand_curriculum.py
            "modelSentence": lesson["modelSentence"].strip(),
            "modelSentenceArabic": lesson["modelSentenceArabic"].strip(),
        })
    return out


def main():
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    seeds = load_seeds()
    if not seeds:
        print("No seed files found in Scripts/new_lessons/; nothing to inject.")
        return

    added_units = added_lessons = 0
    for code, units in seeds.items():
        level = next(l for l in catalog["levels"] if l["level"] == code)
        prefix = PREFIX[code]
        marker = re.compile(rf"^{prefix}-x-u\d+$")
        # drop previously injected units (idempotency)
        level["units"] = [u for u in level["units"] if not marker.match(u.get("id", ""))]
        next_order = max((u.get("order", 0) for u in level["units"]), default=0) + 1
        for unit in sorted(units, key=lambda u: u["id"]):
            level["units"].append(build_unit(code, unit, next_order))
            next_order += 1
            added_units += 1
            added_lessons += len(unit["lessons"])

    # integrity: unique ids everywhere
    luids, leids, lwids = [], [], []
    for lv in catalog["levels"]:
        for u in lv["units"]:
            luids.append(u["id"])
            for l in u["lessons"]:
                leids.append(l["id"])
                for w in l["vocabulary"]:
                    lwids.append(w["id"])
    for name, ids in (("unit", luids), ("lesson", leids), ("vocab", lwids)):
        dupes = {i for i in ids if ids.count(i) > 1}
        if dupes:
            raise SystemExit(f"Duplicate {name} ids after injection: {sorted(dupes)}")

    PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    print(f"Injected {added_units} units / {added_lessons} lessons. "
          f"Now run expand_curriculum.py to generate their exercises.")


if __name__ == "__main__":
    main()
