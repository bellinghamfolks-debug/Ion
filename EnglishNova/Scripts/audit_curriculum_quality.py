#!/usr/bin/env python3
"""Pedagogical/data-quality audit for the generated EnglishNova curriculum.

This intentionally does NOT reject a word merely because it reappears in a
later lesson: spaced retrieval across new contexts is useful. It rejects
accidental duplication inside one lesson, placeholder/over-literal glosses,
broken punctuation, malformed assessment choices, empty examples, and the
legacy upper-level function-word fillers that were replaced during the 2.0
curriculum review.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURRICULUM = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"

BAD_ARABIC = {
    "بداية الجملة", "كلمة من المثال", "خاصتي", "خاصتك", "خاصته", "خاصتها",
    "هذا القريب", "ذلك البعيد", "هؤلاء القريبون", "أولئك البعيدون", "هو للأشياء",
}
UPPER_FILLERS = {
    "i", "the", "where", "this", "would", "could", "let", "she", "we", "my",
}
EXPANSION_WORDS = 8
MAX_LESSON_MINUTES = 25
MIN_WORDS = 2448
MIN_EXERCISES = 9700
# Generator filler such as "Your is today's key word." is not English.
PLACEHOLDER_EXAMPLE = re.compile(r"\bis today[’']s key word\b", re.IGNORECASE)
CHOICE_TYPES = {"multipleChoice", "listenAndChoose"}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def broken_final_punctuation(value: object) -> bool:
    text = str(value or "").strip()
    return bool(re.search(r"[!?]\.$|\.\.$", text))


def main() -> int:
    data = json.loads(CURRICULUM.read_text(encoding="utf-8"))
    errors: list[str] = []
    levels = data.get("levels", [])
    lesson_count = word_count = exercise_count = 0

    if [x.get("level") for x in levels] != ["A0", "A1", "A2", "B1", "B2", "C1"]:
        fail(errors, "CEFR levels are missing or out of order.")

    for level in levels:
        code = level.get("level", "")
        lessons = [lesson for unit in level.get("units", []) for lesson in unit.get("lessons", [])]
        if len(lessons) != 60:
            fail(errors, f"{code}: expected 60 lessons, found {len(lessons)}")

        for lesson in lessons:
            lesson_count += 1
            lid = lesson.get("id") or "<missing lesson id>"
            words = lesson.get("vocabulary", [])
            exercises = lesson.get("exercises", [])
            word_count += len(words)
            exercise_count += len(exercises)

            # The 32 new upper-level expansion lessons per level carry eight
            # high-value words: enough for a rich lesson while keeping it near
            # 30 items and 20-25 minutes, like the rest of the course. Older
            # material may have fewer and is reviewed separately rather than
            # padded with filler.
            if code in {"A2", "B1", "B2", "C1"} and re.search(r"-x-u(?:[5-9]|1[0-2])-l\d+$", lid):
                if len(words) != EXPANSION_WORDS:
                    fail(errors, f"{lid}: expansion lesson has {len(words)} words; expected {EXPANSION_WORDS}")
            if lesson.get("estimatedMinutes", 0) > MAX_LESSON_MINUTES:
                fail(errors, f"{lid}: estimated {lesson.get('estimatedMinutes')} minutes; keep lessons at {MAX_LESSON_MINUTES} or less")

            word_keys = [str(w.get("english") or "").strip().lower() for w in words]
            duplicates = [w for w, n in Counter(word_keys).items() if w and n > 1]
            if duplicates:
                fail(errors, f"{lid}: duplicate vocabulary inside lesson: {duplicates}")

            for word in words:
                wid = word.get("id") or f"{lid}:<word>"
                english = str(word.get("english") or "").strip()
                arabic = str(word.get("arabic") or "").strip()
                example = str(word.get("example") or "").strip()
                example_ar = str(word.get("exampleArabic") or "").strip()
                pos = str(word.get("partOfSpeech") or "").strip()

                if not english or not arabic:
                    fail(errors, f"{wid}: missing English or Arabic vocabulary text")
                if arabic in BAD_ARABIC:
                    fail(errors, f"{wid}: placeholder/over-literal Arabic gloss: {arabic!r}")
                if pos == "word":
                    fail(errors, f"{wid}: placeholder partOfSpeech='word'")
                if not example or not example_ar:
                    fail(errors, f"{wid}: missing bilingual example")
                if PLACEHOLDER_EXAMPLE.search(example):
                    fail(errors, f"{wid}: placeholder example sentence: {example!r}")
                if broken_final_punctuation(example):
                    fail(errors, f"{wid}: malformed English example punctuation: {example!r}")
                if code in {"A2", "B1", "B2", "C1"} and english.lower() in UPPER_FILLERS:
                    fail(errors, f"{wid}: low-value standalone function word remains in {code}: {english!r}")

            signatures: set[tuple] = set()
            for exercise in exercises:
                eid = exercise.get("id") or f"{lid}:<exercise>"
                answer = str(exercise.get("answer") or "").strip()
                if not answer:
                    fail(errors, f"{eid}: empty answer")

                for field in ("promptEn", "speechText", "answer"):
                    if broken_final_punctuation(exercise.get(field)):
                        fail(errors, f"{eid}: malformed punctuation in {field}")

                choices = exercise.get("choices")
                if isinstance(choices, list):
                    normalized = [str(x).strip().lower() for x in choices]
                    if len(normalized) != len(set(normalized)):
                        fail(errors, f"{eid}: duplicate choices")
                    if exercise.get("type") in CHOICE_TYPES and answer.lower() not in normalized:
                        fail(errors, f"{eid}: answer is not one of its choices")

                signature = (
                    exercise.get("type"),
                    str(exercise.get("promptAr") or "").strip(),
                    str(exercise.get("promptEn") or "").strip(),
                    answer,
                )
                if signature in signatures:
                    fail(errors, f"{eid}: duplicate exercise content inside {lid}")
                signatures.add(signature)

    if word_count < MIN_WORDS:
        fail(errors, f"Curriculum has {word_count} vocabulary entries; reviewed 2.0 floor is {MIN_WORDS}")
    if exercise_count < MIN_EXERCISES:
        fail(errors, f"Curriculum has {exercise_count} exercises; reviewed 2.0 floor is {MIN_EXERCISES}")

    if errors:
        print("EnglishNova curriculum quality audit: FAILED")
        for item in errors[:250]:
            print(f"- {item}")
        if len(errors) > 250:
            print(f"- ... and {len(errors) - 250} more")
        return 1

    print("EnglishNova curriculum quality audit: PASS")
    print(f"- {lesson_count} lessons / {word_count} vocabulary entries / {exercise_count} exercises")
    print("- Intentional spaced repetition across different lessons is allowed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
