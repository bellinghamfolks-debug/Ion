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
  * exactly eight words per lesson (WORDS_PER_LESSON), which keeps a lesson
    near 30 items and 20-25 minutes, like the rest of the course;
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
WORDS_PER_LESSON = 8
SPACED_RETRIEVAL = ROOT / "Scripts/spaced_retrieval.json"


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
                          "descriptionAr": parts[4], "icon": parts[5], "descriptionEn": parts[6],
                          "lessons": [], "_source_line": number})
        elif kind == "L":
            if len(parts) != 7:
                raise SystemExit(f"{path.name}:{number}: lesson needs 7 fields")
            unit = units[-1]
            unit["lessons"].append({
                "id": f"{unit['id']}-l{len(unit['lessons']) + 1}",
                "titleAr": parts[1], "titleEn": parts[2], "objectiveAr": parts[3],
                "modelSentence": parts[4], "modelSentenceArabic": parts[5], "objectiveEn": parts[6],
                "vocabulary": [], "_source_line": number})
        elif kind == "W":
            if len(parts) != 6:
                raise SystemExit(f"{path.name}:{number}: word needs 6 fields")
            units[-1]["lessons"][-1]["vocabulary"].append({
                "english": parts[1], "arabic": parts[2], "example": parts[3],
                "exampleArabic": parts[4], "partOfSpeech": parts[5], "phonetic": None,
                "_source_line": number})
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


def clean_source_metadata(value):
    """Return JSON-ready seed data without parser-only source locations."""
    if isinstance(value, dict):
        return {k: clean_source_metadata(v) for k, v in value.items() if not k.startswith("_source_")}
    if isinstance(value, list):
        return [clean_source_metadata(v) for v in value]
    return value


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

    retrieval = json.loads(SPACED_RETRIEVAL.read_text(encoding="utf-8"))
    used_retrieval = set()
    failures, notes = [], []
    pending_outputs: list[tuple[Path, dict]] = []
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
                lesson_line = lesson.get("_source_line", "?")
                lesson_at = f"{path.name}:{lesson_line}: {lid}"
                if len(vocab) != WORDS_PER_LESSON:
                    failures.append(f"{lesson_at}: {len(vocab)} words (need {WORDS_PER_LESSON})")
                if not any(re.search(rf"\b{re.escape(w['english'])}\b", lesson["modelSentence"], re.I) for w in vocab):
                    failures.append(f"{lesson_at}: model sentence contains none of its words")
                for wi, w in enumerate(vocab, start=1):
                    key = w["english"].lower()
                    word_line = w.get("_source_line", lesson_line)
                    word_at = f"{path.name}:{word_line}: {lid}"
                    if key in seen:
                        failures.append(f"{word_at}: '{w['english']}' repeats inside {level}")
                    seen.add(key)
                    wid = f"{lid}-w{wi}"
                    repeat = retrieval.get(wid, {})
                    allowed_repeat = repeat.get("english") == key and bool(repeat.get("reason"))
                    if allowed_repeat:
                        used_retrieval.add(wid)
                    if key in taught.get(level, set()) and not allowed_repeat:
                        failures.append(f"{word_at}: '{w['english']}' is already taught in {level}")
                    elif any(key in words for code, words in taught.items() if code != level):
                        notes.append(f"{word_at}: '{w['english']}' also appears in another level")
                    if not stem_present(w["english"], w["example"]):
                        failures.append(f"{word_at}: example for '{w['english']}' does not use it: {w['example']}")
                    if "|" in w["arabic"] or not w["arabic"]:
                        failures.append(f"{word_at}: bad Arabic for '{w['english']}'")
        code = level.lower()
        halves = [units[:4], units[4:]]
        for index, chunk in enumerate(halves, start=3):
            if not chunk:
                continue
            target = OUT / f"{code}_part{index}.json"
            pending_outputs.append((target, {"level": level, "units": chunk}))
        print(f"{path.name}: {level} {len(units)} units, {sum(len(u['lessons']) for u in units)} lessons")

    if set(retrieval) - used_retrieval:
        failures.append(f"Stale spaced-retrieval entries: {sorted(set(retrieval) - used_retrieval)}")
    for note in notes:
        print(f"  note: {note}")
    if not failures:
        # Write generated files only after every source file has passed. This
        # avoids leaving a partially regenerated course after a later failure.
        for target, payload in pending_outputs:
            cleaned = clean_source_metadata(payload)
            target.write_text(json.dumps(cleaned, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

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
