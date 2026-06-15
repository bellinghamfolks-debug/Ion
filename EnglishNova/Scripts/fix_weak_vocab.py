#!/usr/bin/env python3
"""Correct the weak original A2–C1 vocabulary entries.

The A2–C1 levels shipped with vocabulary rows whose Arabic field was a
placeholder note rather than a translation — "بداية الجملة" (the sentence's
first word) and "كلمة من المثال" (a word taken from the example) — with
partOfSpeech set to the literal string "word" and no phonetic. The English
word and the example sentence were fine; only the gloss was missing.

This fills in an accurate Modern Standard Arabic gloss, a real part of
speech and an IPA transcription for each affected word. It edits the
vocabulary in place; expand_curriculum.py preserves these rows on
subsequent runs and regenerates the exercises (flashcards, meaning
multiple-choice, etc.) from the corrected glosses, so run this BEFORE
expand_curriculum.py.

Idempotent: it only touches rows whose Arabic is still a placeholder.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"

PLACEHOLDERS = {"بداية الجملة", "كلمة من المثال"}

# english -> (arabic gloss, part of speech, IPA)
FIXES = {
    # function / sentence-initial words
    "I": ("أنا", "pronoun", "/aɪ/"),
    "Where": ("أين", "adverb", "/weər/"),
    "This": ("هذا", "determiner", "/ðɪs/"),
    "Would": ("صيغة مهذّبة للطلب", "modal verb", "/wʊd/"),
    "My": ("خاصتي", "determiner", "/maɪ/"),
    "In": ("في", "preposition", "/ɪn/"),
    "First,": ("أولًا", "adverb", "/fɜːrst/"),
    "We": ("نحن", "pronoun", "/wiː/"),
    "The": ("أداة التعريف (الـ)", "article", "/ðə/"),
    "Could": ("صيغة مهذّبة للطلب (هل يمكن)", "modal verb", "/kʊd/"),
    "If": ("إذا / لو", "conjunction", "/ɪf/"),
    "Let": ("دع / لِـ", "verb", "/let/"),
    "She": ("هي", "pronoun", "/ʃiː/"),
    "While": ("بينما", "conjunction", "/waɪl/"),
    # content words
    "late": ("متأخر", "adjective", "/leɪt/"),
    "week": ("أسبوع", "noun", "/wiːk/"),
    "tonight": ("الليلة", "adverb", "/təˈnaɪt/"),
    "gate": ("بوابة", "noun", "/ɡeɪt/"),
    "headache": ("صداع", "noun", "/ˈhedeɪk/"),
    "one": ("واحد (بدلًا من اسم)", "pronoun", "/wʌn/"),
    "us": ("نا (ضمير مفعول: نحن)", "pronoun", "/ʌs/"),
    "today": ("اليوم", "adverb", "/təˈdeɪ/"),
    "hours": ("ساعات", "noun", "/ˈaʊərz/"),
    "assignment": ("واجب / مهمة", "noun", "/əˈsaɪnmənt/"),
    "useful": ("مفيد", "adjective", "/ˈjuːsfəl/"),
    "started": ("بدأ", "verb", "/ˈstɑːrtɪd/"),
    "schedule": ("جدول مواعيد", "noun", "/ˈskedʒuːl/"),
    "increased": ("ازداد", "verb", "/ɪnˈkriːst/"),
    "point": ("نقطة", "noun", "/pɔɪnt/"),
    "appointment": ("موعد", "noun", "/əˈpɔɪntmənt/"),
    "issue": ("مسألة / مشكلة", "noun", "/ˈɪʃuː/"),
    "effective": ("فعّال", "adjective", "/ɪˈfektɪv/"),
    "course": ("دورة تدريبية", "noun", "/kɔːrs/"),
    "yesterday": ("أمس", "adverb", "/ˈjestərdeɪ/"),
    "busy": ("مشغول", "adjective", "/ˈbɪzi/"),
    "section": ("قسم", "noun", "/ˈsekʃn/"),
    "deadline": ("موعد نهائي", "noun", "/ˈdedlaɪn/"),
    "perspective": ("منظور / وجهة نظر", "noun", "/pərˈspektɪv/"),
    "precision": ("دقة", "noun", "/prɪˈsɪʒn/"),
    "principle": ("مبدأ", "noun", "/ˈprɪnsəpl/"),
    "change": ("تغيّر", "noun", "/tʃeɪndʒ/"),
    "limited": ("محدود", "adjective", "/ˈlɪmɪtɪd/"),
    "consequences": ("عواقب", "noun", "/ˈkɒnsɪkwənsɪz/"),
    "regulations": ("لوائح / أنظمة", "noun", "/ˌreɡjuˈleɪʃnz/"),
    "interpretation": ("تفسير", "noun", "/ɪnˌtɜːprɪˈteɪʃn/"),
    "challenges": ("تحديات", "noun", "/ˈtʃælɪndʒɪz/"),
}


def main():
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    fixed = 0
    missing = set()
    for level in catalog.get("levels", []):
        for unit in level.get("units", []):
            for lesson in unit.get("lessons", []):
                for w in lesson.get("vocabulary", []):
                    if w.get("arabic", "").strip() not in PLACEHOLDERS:
                        continue
                    en = w.get("english", "")
                    if en not in FIXES:
                        missing.add(en)
                        continue
                    ar, pos, ipa = FIXES[en]
                    w["arabic"] = ar
                    w["partOfSpeech"] = pos
                    w["phonetic"] = ipa
                    fixed += 1

    if missing:
        raise SystemExit(f"No correction defined for: {sorted(missing)}")

    PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Corrected {fixed} weak vocabulary entries.")


if __name__ == "__main__":
    main()
