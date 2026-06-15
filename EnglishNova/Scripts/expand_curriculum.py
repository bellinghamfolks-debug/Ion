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
ENRICH_DIR = ROOT / "Scripts/enrichment"


def load_enrichment():
    """Merge all hand-authored enrichment files (Scripts/enrichment/*.json).

    Each file maps lesson id -> {extraVocabulary:[...], extraExamples:{vocabId:[...]}}.
    The `specs/` subfolder holds inputs for the authors and is ignored here.
    Returns {} when no enrichment is present (script still works standalone).
    """
    merged = {}
    if not ENRICH_DIR.is_dir():
        return merged
    for f in sorted(ENRICH_DIR.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as exc:  # pragma: no cover - defensive
            print(f"  ! skipping unreadable enrichment {f.name}: {exc}")
            continue
        for lid, payload in data.get("lessons", {}).items():
            merged[lid] = payload
    return merged


def merge_new_vocabulary(lesson, payload):
    """Append authored extra words to the lesson's vocabulary (idempotent).

    New words get ids of the form "<lessonId>-xv<n>" so re-running the script
    first strips the previous batch instead of duplicating it. Words already
    present (by English form) are skipped.
    """
    lid = lesson["id"]
    base = [w for w in lesson.get("vocabulary", [])
            if not re.match(rf"^{re.escape(lid)}-xv\d+$", w.get("id", ""))]
    have = {w["english"].strip().lower() for w in base}
    added = []
    for entry in payload.get("extraVocabulary", []):
        en = (entry.get("english") or "").strip()
        ar = (entry.get("arabic") or "").strip()
        if not en or not ar or en.lower() in have:
            continue
        have.add(en.lower())
        added.append({
            "id": f"{lid}-xv{len(added) + 1}",
            "english": en,
            "arabic": ar,
            "example": (entry.get("example") or "").strip(),
            "exampleArabic": (entry.get("exampleArabic") or "").strip(),
            "partOfSpeech": (entry.get("partOfSpeech") or "").strip(),
            "phonetic": (entry.get("phonetic") or None),
        })
    lesson["vocabulary"] = base + added
    return len(added)

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
    explicit = (lesson.get("modelSentence") or "").strip()
    if explicit:
        return explicit if explicit.endswith((".", "!", "?")) else explicit + "."
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
    """Arabic of the model sentence, recovered from the arrange/translate prompt.

    arrangeWords is unique per lesson and always carries the model sentence, so
    it is preferred — after expansion there are several translation exercises
    (one per extra example) and the first is no longer the model sentence.
    """
    explicit = (lesson.get("modelSentenceArabic") or "").strip()
    if explicit:
        return explicit
    exs = lesson["exercises"]
    ar = find(exs, "arrangeWords")
    if ar:
        s = strip_prefix(ar.get("promptAr", ""), ARRANGE_PREFIXES)
        if s:
            return s
    tr = find(exs, "translation")
    if tr:
        s = strip_prefix(tr.get("promptAr", ""), TRANSLATE_PREFIXES)
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


def arabic_policy(level: str) -> str:
    """How much Arabic (L1) scaffolding a level gets.

    Grounded in the comprehensible-input / graded-L1-withdrawal approach: the
    target language is the medium, and L1 support is a scaffold that shrinks as
    proficiency rises.
      full    – beginners (A0, A1): Arabic instructions, glosses, translations.
      reduced – A2, B1: English instructions; Arabic kept for word meanings and
                one sentence translation; redundant Arabic dropped.
      minimal – B2, C1: English-first. Arabic only as a short word gloss and the
                lesson objective; meaning is checked in English (context), and
                translation drills are replaced by English-only tasks.
    """
    return {"A0": "full", "A1": "full",
            "A2": "reduced", "B1": "reduced",
            "B2": "minimal", "C1": "minimal"}.get(level, "full")


def expand_lesson(lesson, unit_eng_pool, unit_ar_pool, extra_examples=None, policy="full"):
    extra_examples = extra_examples or {}
    lid = lesson["id"]
    vocab = lesson.get("vocabulary", [])
    sentence = model_sentence(lesson)
    sentence_ar = model_sentence_arabic(lesson)
    objective = lesson.get("objectiveAr", "").strip()

    full = policy == "full"
    minimal = policy == "minimal"
    en_instructions = policy != "full"   # reduced + minimal use English prompts

    new_ex = []
    counter = 0

    def add(ex):
        nonlocal counter
        counter += 1
        ex["id"] = f"{lid}-e{counter}"
        ex.setdefault("promptEn", None)
        ex.setdefault("choices", None)
        ex.setdefault("tokens", None)
        ex.setdefault("speechText", None)
        ex.setdefault("acceptableAnswers", None)
        new_ex.append(ex)

    # 1) Teaching intro --------------------------------------------------
    if full:
        word_lines = "\n".join(f"• {w['english']} = {w['arabic']}" for w in vocab)
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
        intro_prompt = "تمهيد الدرس والمفردات"
        intro_hint = "استمع إلى الشرح والنموذج ثم انتقل إلى التمرين التالي"
    else:
        # English-led intro; a single Arabic objective line is the only L1.
        word_lines = "\n".join(f"• {w['english']} — {w['arabic']}" for w in vocab)
        intro_lines = []
        if objective:
            intro_lines.append(f"الهدف: {objective}")
        if sentence:
            intro_lines.append(f"Model sentence: {sentence}")
        if word_lines:
            intro_lines.append("New words:\n" + word_lines)
        intro_lines.append("Listen to the model, then practise the words in the exercises.")
        intro_prompt = "Lesson intro & key words"
        intro_hint = "Listen to the model sentence, then continue"
    add({
        "type": "explanation",
        "promptAr": intro_prompt,
        "promptEn": sentence or None,
        "answer": sentence or objective or "",
        "explanationAr": "\n\n".join(intro_lines),
        "accessibilityHint": intro_hint,
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
        word_extras = extra_examples.get(w.get("id"), [])

        # a) flashcard
        if full:
            card_lines = [f"{en} = {ar}" + (f" ({pos})" if pos else "")]
            if example:
                card_lines.append(f"مثال: {example}" + (f" — {example_ar}" if example_ar else ""))
            for ex in word_extras:
                ex_en = (ex.get("example") or "").strip()
                ex_ar = (ex.get("exampleArabic") or "").strip()
                if ex_en:
                    card_lines.append(f"مثال آخر: {ex_en}" + (f" — {ex_ar}" if ex_ar else ""))
            card_prompt = "تعرّف على الكلمة الجديدة، واستمع إلى نطقها."
            card_hint = "استمع إلى الكلمة ثم اضغط متابعة"
        else:
            # English example is the headline; Arabic is a short gloss only.
            card_lines = [f"{en}" + (f" ({pos})" if pos else "")]
            if example:
                card_lines.append(f"e.g., {example}")
            for ex in word_extras:
                ex_en = (ex.get("example") or "").strip()
                if ex_en:
                    card_lines.append(f"e.g., {ex_en}")
            card_lines.append(f"بالعربية: {ar}")
            card_prompt = "New word — listen and learn it from the example."
            card_hint = "Listen to the word, then continue"
        add({
            "type": "flashcard",
            "promptAr": card_prompt,
            "answer": en,
            "explanationAr": "\n".join(card_lines),
            "accessibilityHint": card_hint,
            "speechText": en,
        })

        # b) meaning check
        example_has_word = bool(example) and re.search(rf"\b{re.escape(en)}\b", example, re.IGNORECASE)
        if minimal and example_has_word:
            # English, context-based: complete the example sentence.
            gapped = re.sub(rf"\b{re.escape(en)}\b", "_____", example, count=1, flags=re.IGNORECASE)
            en_distractors = pick_distractors(rng, unit_eng_pool, exclude={en}, n=2)
            add({
                "type": "multipleChoice",
                "promptAr": "Choose the word that completes the sentence:",
                "promptEn": gapped,
                "answer": en,
                "choices": shuffled(rng, [en] + en_distractors),
                "explanationAr": f"{en}: {example}",
                "accessibilityHint": "Pick the word that fits the sentence",
                "speechText": example,
            })
        else:
            # Arabic meaning (kept for full + reduced; minimal fallback).
            ar_distractors = pick_distractors(rng, unit_ar_pool, exclude={ar}, n=2)
            add({
                "type": "multipleChoice",
                "promptAr": f"ما معنى {en}؟" if full else f"What does “{en}” mean?",
                "promptEn": en,
                "answer": ar,
                "choices": shuffled(rng, [ar] + ar_distractors),
                "explanationAr": (f"{en} تعني {ar}." if full else f"{en} = {ar}")
                                 + (f"\ne.g., {example}" if example and not full else
                                    (f"\nمثال: {example}" if example else "")),
                "accessibilityHint": "اختر المعنى العربي الصحيح" if full else "Choose the correct meaning",
                "speechText": en,
            })

        # c) listenAndChoose
        en_distractors = pick_distractors(rng, unit_eng_pool, exclude={en}, n=2)
        add({
            "type": "listenAndChoose",
            "promptAr": "استمع ثم اختر الكلمة التي سمعتها." if full else "Listen and choose the word you hear.",
            "answer": en,
            "choices": shuffled(rng, [en] + en_distractors),
            "explanationAr": (f"الكلمة التي سمعتها هي {en} ({ar})." if full else f"You heard: {en}."),
            "accessibilityHint": "شغّل الصوت ثم اختر إجابة واحدة" if full else "Play the audio, then choose one",
            "speechText": en,
        })

        # d) translate the extra example(s) — full only (redundant L1 otherwise)
        if full:
            for ex in word_extras:
                ex_en = (ex.get("example") or "").strip()
                ex_ar = (ex.get("exampleArabic") or "").strip()
                if not ex_en or not ex_ar:
                    continue
                add({
                    "type": "translation",
                    "promptAr": f"ترجم إلى الإنجليزية: {ex_ar}",
                    "answer": ex_en.rstrip("."),
                    "explanationAr": f"الترجمة النموذجية: {ex_en}\nلاحظ استخدام الكلمة {en}.",
                    "accessibilityHint": "اكتب الترجمة الإنجليزية ثم اضغط تحقق",
                    "speechText": ex_en,
                    "acceptableAnswers": [ex_en, ex_en.rstrip(".")],
                })

    # 3) Sentence work ---------------------------------------------------
    if sentence:
        toks = tokens_for(sentence)
        rng = random.Random(f"{lid}:arrange")
        if full:
            arrange_prompt = (f"رتب الكلمات لتكوين الجملة: {sentence_ar}" if sentence_ar
                              else "رتب الكلمات لتكوين الجملة النموذجية.")
        elif sentence_ar and not minimal:
            arrange_prompt = f"Arrange the words to form the sentence: {sentence_ar}"
        else:
            arrange_prompt = "Arrange the words to form the model sentence."
        add({
            "type": "arrangeWords",
            "promptAr": arrange_prompt,
            "answer": " ".join(toks),
            "tokens": shuffled(rng, toks),
            "explanationAr": (f"الترتيب الصحيح: {sentence}" if full else f"Correct order: {sentence}"),
            "accessibilityHint": ("اختر الكلمات بالترتيب الصحيح، ويمكنك التراجع عن آخر كلمة" if full
                                  else "Tap the words in the correct order; you can undo the last one"),
            "speechText": sentence,
            "acceptableAnswers": [sentence, " ".join(toks)],
        })

        # fillBlank
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
                "promptAr": "أكمل الفراغ بالكلمة المناسبة." if full else "Fill in the blank.",
                "promptEn": gapped,
                "answer": en,
                "explanationAr": (f"الكلمة الناقصة هي {en}.\nالجملة كاملة: {sentence}" if full
                                  else f"Missing word: {en}.\nFull sentence: {sentence}"),
                "accessibilityHint": "اكتب الكلمة الناقصة ثم اضغط تحقق" if full else "Type the missing word, then check",
                "speechText": sentence,
                "acceptableAnswers": [en.lower(), en.capitalize()],
            })

        # translation (full + reduced; dropped at minimal)
        if sentence_ar and not minimal:
            add({
                "type": "translation",
                "promptAr": f"ترجم إلى الإنجليزية: {sentence_ar}",
                "answer": sentence.rstrip("."),
                "explanationAr": (f"الترجمة النموذجية: {sentence}" if full else f"Model answer: {sentence}"),
                "accessibilityHint": "اكتب الترجمة الإنجليزية ثم اضغط تحقق" if full else "Write the English translation, then check",
                "speechText": sentence,
                "acceptableAnswers": [sentence, sentence.rstrip(".")],
            })

        # speak
        add({
            "type": "speak",
            "promptAr": "انطق الجملة التالية بوضوح." if full else "Say the sentence aloud, clearly.",
            "promptEn": sentence,
            "answer": sentence.rstrip("."),
            "explanationAr": ("ركّز على وضوح الكلمات والإيقاع، ولا تقلق من اختلاف اللهجة." if full
                              else "Focus on clear words and rhythm; don't worry about your accent."),
            "accessibilityHint": "استمع للنموذج ثم ابدأ التسجيل وانطق الجملة" if full else "Listen to the model, then record yourself",
            "speechText": sentence,
            "acceptableAnswers": [sentence, sentence.rstrip(".")],
        })

    # 4) Review ----------------------------------------------------------
    words_inline = "، ".join(w["english"] for w in vocab) if full else ", ".join(w["english"] for w in vocab)
    review_lines = []
    if full:
        if words_inline:
            review_lines.append(f"راجعنا في هذا الدرس: {words_inline}.")
        if sentence:
            s = f"وتدرّبنا على الجملة: {sentence}"
            if sentence_ar:
                s += f" ({sentence_ar})"
            review_lines.append(s + ".")
        review_lines.append("أعد التمرين متى احتجت، وحاول أن تستخدم الكلمات في جملةٍ من عندك.")
        review_prompt, review_hint = "مراجعة الدرس", "اقرأ المراجعة ثم أنهِ الدرس"
    else:
        if words_inline:
            review_lines.append(f"You practised: {words_inline}.")
        if sentence:
            review_lines.append(f"Key sentence: {sentence}.")
        review_lines.append("Try to use these words in a sentence of your own.")
        review_prompt, review_hint = "Lesson review", "Read the review, then finish the lesson"
    add({
        "type": "explanation",
        "promptAr": review_prompt,
        "answer": sentence or words_inline,
        "explanationAr": "\n".join(review_lines),
        "accessibilityHint": review_hint,
        "speechText": sentence or None,
    })

    lesson["exercises"] = new_ex
    lesson["estimatedMinutes"] = max(10, round(len(new_ex) * 0.8))
    lesson["points"] = max(int(lesson.get("points", 0)), len(new_ex) * 8)
    return lesson


def main():
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    enrichment = load_enrichment()
    words_before = words_added = 0

    # Merge authored extra vocabulary into every lesson first, so the new
    # words feed both the per-word exercise generation and the distractor
    # pools below.
    for level in catalog.get("levels", []):
        for unit in level.get("units", []):
            for ls in unit.get("lessons", []):
                words_before += len([w for w in ls.get("vocabulary", [])
                                     if not re.match(rf"^{re.escape(ls['id'])}-xv\d+$",
                                                     w.get("id", ""))])
                payload = enrichment.get(ls["id"], {})
                if payload:
                    words_added += merge_new_vocabulary(ls, payload)

    total_before = total_after = lessons = 0
    for level in catalog.get("levels", []):
        policy = arabic_policy(level.get("level", ""))
        for unit in level.get("units", []):
            unit_lessons = unit.get("lessons", [])
            eng_pool, ar_pool = [], []
            for ls in unit_lessons:
                for w in ls.get("vocabulary", []):
                    eng_pool.append(w["english"])
                    ar_pool.append(w["arabic"])
            for ls in unit_lessons:
                total_before += len(ls.get("exercises", []))
                extra = enrichment.get(ls["id"], {}).get("extraExamples", {})
                expand_lesson(ls, eng_pool, ar_pool, extra_examples=extra, policy=policy)
                total_after += len(ls["exercises"])
                lessons += 1

    PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Expanded {lessons} lessons.")
    print(f"Vocabulary: {words_before} base words + {words_added} authored "
          f"= {words_before + words_added} total.")
    print(f"Exercises: {total_before} -> {total_after} "
          f"(avg {total_before/lessons:.1f} -> {total_after/lessons:.1f} per lesson).")


if __name__ == "__main__":
    main()
