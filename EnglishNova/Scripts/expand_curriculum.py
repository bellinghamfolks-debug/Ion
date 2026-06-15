#!/usr/bin/env python3
"""Expand every lesson in curriculum.json into a fuller learning arc.

The original curriculum is pedagogically thin: each lesson is three
vocabulary words and 5–6 exercises built around a single model sentence,
with a one-line "explanation". Learners reported the lessons feel far too
short.

This script keeps the existing structure, ids of levels/units/lessons and
all vocabulary, but rebuilds each lesson's *exercise* list into a richer,
coherent sequence that practises every word in several modalities. It does
NOT invent facts: every new exercise is generated from the lesson's own
real data (its vocabulary and its model sentence). Distractors for the
multiple-choice / listening items are pulled from genuine sibling
vocabulary in the same unit, so they are plausible and on-topic.

Expanded lesson shape (per lesson):
  1. explanation  – teaching intro: objective, model sentence + its Arabic,
                    and the new-word list.
  for each vocabulary word:
     a. flashcard       – the word, with meaning + example shown as feedback.
     b. multipleChoice  – meaning of the word (Arabic), sibling distractors.
     c. listenAndChoose – hear the word, pick it, sibling distractors.
  N. arrangeWords  – reorder the model sentence.
  N. fillBlank     – complete the model sentence (a key word removed).
  N. translation   – translate the Arabic sentence to English.
  N. speak         – say the model sentence aloud.
  N. explanation   – review/recap of the lesson's words and sentence.

Run from anywhere; it rewrites EnglishNova/Resources/Curriculum/curriculum.json
in place. Re-running is idempotent (it always rebuilds from the preserved
fields, and is robust to already-expanded input).
"""
from __future__ import annotations

import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "EnglishNova/Resources/Curriculum/curriculum.json"

TRANSLATE_PREFIXES = ("ترجم إلى الإنجليزية:", "ترجم الجملة إلى الإنجليزية:")
ARRANGE_PREFIXES = ("رتب الكلمات لتكوين الجملة:", "رتب كلمات الجملة:")


def strip_prefix(text: str, prefixes) -> str | None:
    for p in prefixes:
        if text.strip().startswith(p):
            return text.strip()[len(p):].strip()
    return None


def find(exercises, etype):
    for e in exercises:
        if e.get("type") == etype:
            return e
    return None


def model_sentence(lesson) -> str:
    """English model sentence for the lesson."""
    exs = lesson["exercises"]
    for t in ("speak", "explanation", "translation", "arrangeWords"):
        e = find(exs, t)
        if e:
            for key in ("speechText", "promptEn", "answer"):
                v = e.get(key)
                if v and v.strip():
                    return v.strip().rstrip(".") + "." if not v.strip().endswith(".") else v.strip()
    return ""


def model_sentence_arabic(lesson) -> str:
    """Arabic of the model sentence, recovered from the translate/arrange prompt."""
    exs = lesson["exercises"]
    tr = find(exs, "translation")
    if tr:
        s = strip_prefix(tr.get("promptAr", ""), TRANSLATE_PREFIXES)
        if s:
            return s
    ar = find(exs, "arrangeWords")
    if ar:
        s = strip_prefix(ar.get("promptAr", ""), ARRANGE_PREFIXES)
        if s:
            return s
    return ""


def tokens_for(sentence: str) -> list[str]:
    """Word tokens for the arrange-words exercise (keep trailing punctuation off)."""
    cleaned = sentence.strip().rstrip(".!?")
    return [t for t in re.split(r"\s+", cleaned) if t]


def pick_distractors(rng, pool, exclude, n=2):
    """Pick up to n items from pool that are not in `exclude` (set), de-duplicated."""
    seen = set(x.lower() for x in exclude)
    candidates = []
    for x in pool:
        if x.lower() in seen:
            continue
        seen.add(x.lower())
        candidates.append(x)
    rng.shuffle(candidates)
    return candidates[:n]


def shuffled(rng, items):
    out = list(items)
    rng.shuffle(out)
    return out


def expand_lesson(lesson, unit_eng_pool, unit_ar_pool):
    lid = lesson["id"]
    vocab = lesson.get("vocabulary", [])
    sentence = model_sentence(lesson)
    sentence_ar = model_sentence_arabic(lesson)
    objective = lesson.get("objectiveAr", "").strip()

    new_ex = []
    counter = 0

    def add(ex):
        nonlocal counter
        counter += 1
        ex["id"] = f"{lid}-e{counter}"
        # Every exercise carries an accessibility hint and (where relevant)
        # speech text; fill sane defaults so the UI/VoiceOver always works.
        ex.setdefault("promptEn", None)
        ex.setdefault("choices", None)
        ex.setdefault("tokens", None)
        ex.setdefault("speechText", None)
        ex.setdefault("acceptableAnswers", None)
        new_ex.append(ex)

    # 1) Teaching intro --------------------------------------------------
    word_lines = "\n".join(
        f"• {w['english']} = {w['arabic']}" for w in vocab
    )
    intro_lines = []
    if objective:
        intro_lines.append(f"الهدف: {objective}")
    if sentence:
        line = f"الجملة النموذجية: {sentence}"
        if sentence_ar:
            line += f"\nالمعنى: {sentence_ar}"
        intro_lines.append(line)
    if word_lines:
        intro_lines.append("الكلمات الجديدة:\n" + word_lines)
    intro_lines.append("استمع إلى النموذج وكرّره بصوتٍ واضح، ثم انتقل إلى التمارين لتثبيت الكلمات.")
    add({
        "type": "explanation",
        "promptAr": "تمهيد الدرس والمفردات",
        "promptEn": sentence or None,
        "answer": sentence or objective or "",
        "explanationAr": "\n\n".join(intro_lines),
        "accessibilityHint": "استمع إلى الشرح والنموذج ثم انتقل إلى التمرين التالي",
        "speechText": sentence or None,
    })

    # 2) Per-word practice ----------------------------------------------
    for w in vocab:
        en = w["english"]
        ar = w["arabic"]
        pos = w.get("partOfSpeech", "")
        example = (w.get("example") or "").strip()
        example_ar = (w.get("exampleArabic") or "").strip()
        rng = random.Random(f"{lid}:{en}")

        # a) flashcard
        card_lines = [f"{en} = {ar}" + (f" ({pos})" if pos else "")]
        if example:
            line = f"مثال: {example}"
            if example_ar:
                line += f" — {example_ar}"
            card_lines.append(line)
        add({
            "type": "flashcard",
            "promptAr": "تعرّف على الكلمة الجديدة، واستمع إلى نطقها.",
            "answer": en,
            "explanationAr": "\n".join(card_lines),
            "accessibilityHint": "استمع إلى الكلمة ثم اضغط متابعة",
            "speechText": en,
        })

        # b) multipleChoice – Arabic meaning
        ar_distractors = pick_distractors(rng, unit_ar_pool, exclude={ar}, n=2)
        mc_choices = shuffled(rng, [ar] + ar_distractors)
        add({
            "type": "multipleChoice",
            "promptAr": f"ما معنى {en}؟",
            "promptEn": en,
            "answer": ar,
            "choices": mc_choices,
            "explanationAr": f"{en} تعني {ar}." + (f"\nمثال: {example}" if example else ""),
            "accessibilityHint": "اختر المعنى العربي الصحيح",
            "speechText": en,
        })

        # c) listenAndChoose – hear the word, pick it
        en_distractors = pick_distractors(rng, unit_eng_pool, exclude={en}, n=2)
        lc_choices = shuffled(rng, [en] + en_distractors)
        add({
            "type": "listenAndChoose",
            "promptAr": "استمع ثم اختر الكلمة التي سمعتها.",
            "answer": en,
            "choices": lc_choices,
            "explanationAr": f"الكلمة التي سمعتها هي {en} ({ar}).",
            "accessibilityHint": "شغّل الصوت ثم اختر إجابة واحدة",
            "speechText": en,
        })

    # 3) Sentence work ---------------------------------------------------
    if sentence:
        toks = tokens_for(sentence)
        rng = random.Random(f"{lid}:arrange")
        add({
            "type": "arrangeWords",
            "promptAr": f"رتب الكلمات لتكوين الجملة: {sentence_ar}" if sentence_ar
                        else "رتب الكلمات لتكوين الجملة النموذجية.",
            "answer": " ".join(toks),
            "tokens": shuffled(rng, toks),
            "explanationAr": f"الترتيب الصحيح: {sentence}",
            "accessibilityHint": "اختر الكلمات بالترتيب الصحيح، ويمكنك التراجع عن آخر كلمة",
            "speechText": sentence,
            "acceptableAnswers": [sentence, " ".join(toks)],
        })

        # fillBlank – remove a key word that actually appears in the sentence
        blank = None
        for w in vocab:
            en = w["english"]
            pat = re.compile(rf"\b{re.escape(en)}\b", re.IGNORECASE)
            if pat.search(sentence):
                blank = (en, pat)
                break
        if blank:
            en, pat = blank
            gapped = pat.sub("_____", sentence, count=1)
            add({
                "type": "fillBlank",
                "promptAr": "أكمل الفراغ بالكلمة المناسبة.",
                "promptEn": gapped,
                "answer": en,
                "explanationAr": f"الكلمة الناقصة هي {en}.\nالجملة كاملة: {sentence}",
                "accessibilityHint": "اكتب الكلمة الناقصة ثم اضغط تحقق",
                "speechText": sentence,
                "acceptableAnswers": [en.lower(), en.capitalize()],
            })

        # translation
        if sentence_ar:
            add({
                "type": "translation",
                "promptAr": f"ترجم إلى الإنجليزية: {sentence_ar}",
                "answer": sentence.rstrip("."),
                "explanationAr": f"الترجمة النموذجية: {sentence}",
                "accessibilityHint": "اكتب الترجمة الإنجليزية ثم اضغط تحقق",
                "speechText": sentence,
                "acceptableAnswers": [sentence, sentence.rstrip(".")],
            })

        # speak
        add({
            "type": "speak",
            "promptAr": "انطق الجملة التالية بوضوح.",
            "promptEn": sentence,
            "answer": sentence.rstrip("."),
            "explanationAr": "ركّز على وضوح الكلمات والإيقاع، ولا تقلق من اختلاف اللهجة.",
            "accessibilityHint": "استمع للنموذج ثم ابدأ التسجيل وانطق الجملة",
            "speechText": sentence,
            "acceptableAnswers": [sentence, sentence.rstrip(".")],
        })

    # 4) Review ----------------------------------------------------------
    words_inline = "، ".join(w["english"] for w in vocab)
    review_lines = []
    if words_inline:
        review_lines.append(f"راجعنا في هذا الدرس: {words_inline}.")
    if sentence:
        s = f"وتدرّبنا على الجملة: {sentence}"
        if sentence_ar:
            s += f" ({sentence_ar})"
        review_lines.append(s + ".")
    review_lines.append("أعد التمرين متى احتجت، وحاول أن تستخدم الكلمات في جملةٍ من عندك.")
    add({
        "type": "explanation",
        "promptAr": "مراجعة الدرس",
        "answer": sentence or words_inline,
        "explanationAr": "\n".join(review_lines),
        "accessibilityHint": "اقرأ المراجعة ثم أنهِ الدرس",
        "speechText": sentence or None,
    })

    lesson["exercises"] = new_ex
    # Reflect the heavier workload in time/points estimates.
    lesson["estimatedMinutes"] = max(10, round(len(new_ex) * 0.8))
    lesson["points"] = max(int(lesson.get("points", 0)), len(new_ex) * 8)
    return lesson


def main():
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    total_before = total_after = lessons = 0
    for level in catalog.get("levels", []):
        for unit in level.get("units", []):
            unit_lessons = unit.get("lessons", [])
            eng_pool, ar_pool = [], []
            for ls in unit_lessons:
                for w in ls.get("vocabulary", []):
                    eng_pool.append(w["english"])
                    ar_pool.append(w["arabic"])
            for ls in unit_lessons:
                total_before += len(ls.get("exercises", []))
                expand_lesson(ls, eng_pool, ar_pool)
                total_after += len(ls["exercises"])
                lessons += 1

    PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Expanded {lessons} lessons.")
    print(f"Exercises: {total_before} -> {total_after} "
          f"(avg {total_before/lessons:.1f} -> {total_after/lessons:.1f} per lesson).")


if __name__ == "__main__":
    main()
