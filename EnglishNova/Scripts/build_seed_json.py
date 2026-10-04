#!/usr/bin/env python3
"""Convert compact lesson sources into seed JSON for build_new_lessons.py.

Sources live in Scripts/new_lessons_src/<level>_expansion.txt, one record per
line, fields separated by "|":

    LEVEL|A2
    U|<unit id>|<titleAr>|<titleEn>|<descriptionAr>|<SF Symbol>|<descriptionEn>
    L|<titleAr>|<titleEn>|<objectiveAr>|<modelSentence>|<modelSentenceArabic>|<objectiveEn>
    W|<english>|<arabic>|<example>|<exampleArabic>|<partOfSpeech>

Lesson ids are "<unit id>-l<n>". Units are split into two seed files
(<level>_part3.json, <level>_part4.json) of four units each.

Quality gates (the script fails on any of them):
  * exactly six words per lesson;
  * the model sentence contains one of the lesson's words (it becomes the
    fill-in-the-blank item);
  * every example sentence contains its word (or a close inflection);
  * no word repeats inside the new material of one level;
  * no new word duplicates a word already taught in the same level.
Words that already appear in *another* level are only reported.

English mode: unit titles and descriptions, lesson titles, objectives and the
translation prompt are merged into Resources/LocalizationData/translations.json
(the same coverage the rest of the curriculum has). The manifest fingerprint
of that file must be refreshed afterwards (verify_release_recovery.py says so).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Scripts/new_lessons_src"
OUT = ROOT / "Scripts/new_lessons"
CURRICULUM = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"
TRANSLATIONS = ROOT / "EnglishNova/Resources/LocalizationData/translations.json"


def parse(path: Path):
    level, units = None, []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split("|")]
        kind = parts[0]
        if kind == "LEVEL":
            level = parts[1]
        elif kind == "U":
            if len(parts) != 7:
                raise SystemExit(f"{path.name}:{number}: unit needs 7 fields")
            units.append({"id": parts[1], "titleAr": parts[2], "titleEn": parts[3],
                          "descriptionAr": parts[4], "icon": parts[5], "descriptionEn": parts[6], "lessons": []})
        elif kind == "L":
            if len(parts) != 7:
                raise SystemExit(f"{path.name}:{number}: lesson needs 7 fields")
            unit = units[-1]
            unit["lessons"].append({
                "id": f"{unit['id']}-l{len(unit['lessons']) + 1}",
                "titleAr": parts[1], "titleEn": parts[2], "objectiveAr": parts[3],
                "modelSentence": parts[4], "modelSentenceArabic": parts[5], "objectiveEn": parts[6],
                "vocabulary": []})
        elif kind == "W":
            if len(parts) != 6:
                raise SystemExit(f"{path.name}:{number}: word needs 6 fields")
            units[-1]["lessons"][-1]["vocabulary"].append({
                "english": parts[1], "arabic": parts[2], "example": parts[3],
                "exampleArabic": parts[4], "partOfSpeech": parts[5], "phonetic": None})
        else:
            raise SystemExit(f"{path.name}:{number}: unknown record {kind!r}")
    return level, units


def stem_present(word: str, sentence: str) -> bool:
    """True when the word, or a regular inflection of each of its parts, is in the sentence."""
    text = sentence.lower()
    if re.search(rf"\b{re.escape(word.lower())}\b", text):
        return True
    for part in re.findall(r"[a-z']+", word.lower()):
        if len(part) <= 3:
            continue
        root = part[:-1] if part.endswith("e") else part
        root = root[:-1] if root.endswith("y") else root
        if not re.search(rf"\b{re.escape(root[:max(4, len(root) - 2)])}", text):
            return False
    return True


def main() -> int:
    catalog = json.loads(CURRICULUM.read_text(encoding="utf-8"))
    taught: dict[str, set[str]] = {}
    for level in catalog["levels"]:
        words = set()
        for unit in level["units"]:
            if re.search(r"-x-u(\d+)$", unit["id"]) and int(re.search(r"(\d+)$", unit["id"]).group(1)) >= 5:
                continue  # previously generated expansion units are rebuilt from source
            for lesson in unit["lessons"]:
                words.update(w["english"].strip().lower() for w in lesson["vocabulary"])
        taught[level["level"]] = words

    failures, notes = [], []
    english: dict[str, str] = {}
    for path in sorted(SRC.glob("*_expansion.txt")):
        level, units = parse(path)
        for unit in units:
            english[unit["titleAr"]] = unit["titleEn"]
            english[unit["descriptionAr"]] = unit.pop("descriptionEn")
            for lesson in unit["lessons"]:
                english[lesson["titleAr"]] = lesson["titleEn"]
                english[lesson["objectiveAr"]] = lesson.pop("objectiveEn")
                english[f"ترجم إلى الإنجليزية: {lesson['modelSentenceArabic']}"] = (
                    f"Translate to English: {lesson['modelSentenceArabic']}")
        seen: set[str] = set()
        for unit in units:
            for lesson in unit["lessons"]:
                vocab = lesson["vocabulary"]
                lid = lesson["id"]
                if len(vocab) != 6:
                    failures.append(f"{lid}: {len(vocab)} words (need 6)")
                if not any(re.search(rf"\b{re.escape(w['english'])}\b", lesson["modelSentence"], re.I) for w in vocab):
                    failures.append(f"{lid}: model sentence contains none of its words")
                for w in vocab:
                    key = w["english"].lower()
                    if key in seen:
                        failures.append(f"{lid}: '{w['english']}' repeats inside {level}")
                    seen.add(key)
                    if key in taught.get(level, set()):
                        failures.append(f"{lid}: '{w['english']}' is already taught in {level}")
                    elif any(key in words for code, words in taught.items() if code != level):
                        notes.append(f"{lid}: '{w['english']}' also appears in another level")
                    if not stem_present(w["english"], w["example"]):
                        failures.append(f"{lid}: example for '{w['english']}' does not use it: {w['example']}")
                    if "|" in w["arabic"] or not w["arabic"]:
                        failures.append(f"{lid}: bad Arabic for '{w['english']}'")
        code = level.lower()
        halves = [units[:4], units[4:]]
        for index, chunk in enumerate(halves, start=3):
            if not chunk:
                continue
            target = OUT / f"{code}_part{index}.json"
            target.write_text(json.dumps({"level": level, "units": chunk}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{path.name}: {level} {len(units)} units, {sum(len(u['lessons']) for u in units)} lessons")

    for note in notes:
        print(f"  note: {note}")
    if not failures:
        translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
        changed = {k: v for k, v in english.items() if translations.get(k) != v}
        if changed:
            translations.update(changed)
            # Same compact format the file already uses.
            TRANSLATIONS.write_text(json.dumps(translations, ensure_ascii=False), encoding="utf-8")
        print(f"English entries: {len(english)} ({len(changed)} added or changed in translations.json)")
    if failures:
        print("Seed quality check failed:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("Seed quality check: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
