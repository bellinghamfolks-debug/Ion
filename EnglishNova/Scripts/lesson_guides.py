"""Load the hand-reviewed teaching guides used by expand_curriculum.py.

Guides supplement the existing vocabulary sources; they never replace a lesson
or its stable id. Bilingual copy is also registered for the app's English mode.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUIDES = ROOT / "Scripts/lesson_guides"
TRANSLATIONS = ROOT / "EnglishNova/Resources/LocalizationData/translations.json"


def load_guides():
    result = {}
    for path in sorted(GUIDES.glob("*.json")):
        for lid, guide in json.loads(path.read_text(encoding="utf-8")).items():
            if lid in result:
                raise ValueError(f"Duplicate teaching guide: {lid}")
            result[lid] = guide
    return result


def validate_guides(guides, catalog, require_complete=False):
    lessons = {ls["id"]: ls for lv in catalog["levels"] for u in lv["units"] for ls in u["lessons"]}
    errors = []
    if set(guides) - set(lessons):
        errors.append(f"Unknown guide ids: {sorted(set(guides) - set(lessons))}")
    if require_complete and set(lessons) - set(guides):
        errors.append(f"Lessons without reviewed guides: {sorted(set(lessons) - set(guides))}")
    for lid, guide in guides.items():
        for field in ("focusAr", "focusEn", "taskAr", "taskEn", "exampleEn", "exampleAr"):
            if not isinstance(guide.get(field), str) or not guide[field].strip():
                errors.append(f"{lid}: missing {field}")
        check = guide.get("check", {})
        for field in ("promptEn", "answer", "explanationAr", "explanationEn"):
            if not isinstance(check.get(field), str) or not check[field].strip():
                errors.append(f"{lid}: missing check.{field}")
        choices = check.get("choices", [])
        if len(choices) != 3 or len({v.casefold() for v in choices}) != 3 or check.get("answer") not in choices:
            errors.append(f"{lid}: check needs three distinct choices including its answer")
    if errors:
        raise ValueError("\n".join(errors))


def apply_lesson_updates(catalog, guides):
    allowed = {"titleAr", "titleEn", "objectiveAr", "modelSentence", "modelSentenceArabic"}
    for level in catalog["levels"]:
        for unit in level["units"]:
            for lesson in unit["lessons"]:
                updates = guides.get(lesson["id"], {}).get("lessonUpdates", {})
                unexpected = set(updates) - allowed - {"objectiveEn"}
                if unexpected:
                    raise ValueError(f"{lesson['id']}: unsupported lesson updates: {unexpected}")
                lesson.update({k: v for k, v in updates.items() if k in allowed})


def save_guide_translations(guides, catalog=None, enrichment=None):
    translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    translations.update({
        "لاحظ طريقة الاستخدام:": "Notice how the language works:",
        "طبّق ما تعلمته:": "Use what you learned:",
        "إجابة ممكنة:": "One possible answer:",
        "اقرأ الموقف ثم اختر الإجابة المناسبة.": "Read the situation and choose the appropriate answer.",
        "اختر إجابة واحدة اعتمادًا على المعنى أو القاعدة المشروحة": "Choose one answer using the meaning or rule explained",
    })
    # Metadata from hand-authored JSON seeds is not carried in the app schema.
    for path in sorted((ROOT / "Scripts/new_lessons").glob("*.json")):
        for unit in json.loads(path.read_text())["units"]:
            for item in [unit] + unit["lessons"]:
                for ar, en in (("titleAr", "titleEn"), ("descriptionAr", "descriptionEn"), ("objectiveAr", "objectiveEn")):
                    if item.get(ar) and item.get(en):
                        translations[item[ar]] = item[en]
    for guide in guides.values():
        for ar, en in (("focusAr", "focusEn"), ("taskAr", "taskEn"), ("exampleAr", "exampleEn")):
            translations[guide[ar]] = guide[en]
        check = guide["check"]
        translations[check["explanationAr"]] = check["explanationEn"]
        updates = guide.get("lessonUpdates", {})
        for ar, en in (("objectiveAr", "objectiveEn"), ("titleAr", "titleEn")):
            if ar in updates and en in updates:
                translations[updates[ar]] = updates[en]
    if catalog:
        register_generated_translations(translations, catalog, guides, enrichment or {})
    register_polished_aliases(translations)
    TRANSLATIONS.write_text(json.dumps(translations, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def register_generated_translations(translations, catalog, guides, enrichment):
    """Register whole rendered paragraphs: Localizer performs exact lookup.

    Arabic vocabulary glosses and translation source sentences remain learning
    content even with English interface instructions. No machine translation is
    used; objectives and teaching text come from authored bilingual sources.
    """
    for level in catalog["levels"]:
        for unit in level["units"]:
            for lesson in unit["lessons"]:
                guide = guides[lesson["id"]]
                words = lesson["vocabulary"]
                sentence = lesson["modelSentence"]
                objective = lesson["objectiveAr"]
                objective_en = translations.get(objective)
                if not objective_en or objective_en == objective:
                    raise ValueError(f"{lesson['id']}: missing English objective: {objective}")
                intro = "\n\n".join([
                    "Objective: " + objective_en,
                    "Model sentence: " + sentence,
                    "New words:\n" + "\n".join(f"• {w['english']} — {w['arabic']}" for w in words),
                    "Listen to the model, then practise the words in the exercises.",
                    "Notice how the language works:\n" + guide["focusEn"],
                ])
                recap = "\n".join([
                    "You practised: " + ", ".join(w["english"] for w in words) + ".",
                    "Key sentence: " + sentence,
                    "Use what you learned:\n" + guide["taskEn"],
                    "One possible answer:\n" + guide["exampleEn"],
                ])
                exercises = lesson["exercises"]
                translations[exercises[0]["explanationAr"]] = intro
                translations[exercises[-1]["explanationAr"]] = recap
                for ex in exercises[1:-1]:
                    kind = ex["type"]
                    if ex.get("promptEn") == guide["check"]["promptEn"]:
                        continue
                    if kind == "flashcard":
                        word = next(w for w in words if w["english"] == ex["answer"])
                        lines = [f"{word['english']} ({word['partOfSpeech']})", "Example: " + word["example"], "Arabic meaning: " + word["arabic"]]
                        for extra in enrichment.get(lesson["id"], {}).get("extraExamples", {}).get(word["id"], []):
                            lines.append("Another example: " + extra["example"])
                        value = "\n".join(lines)
                    elif kind == "multipleChoice":
                        value = "Model usage: " + (ex.get("speechText") or ex["answer"]) + "\nAnswer: " + ex["answer"]
                    elif kind == "listenAndChoose":
                        value = "You heard: " + ex["answer"] + "."
                    elif kind == "arrangeWords":
                        value = "Correct order: " + sentence
                    elif kind == "translation":
                        value = "Model answer: " + ex["answer"]
                    elif kind == "speak":
                        value = "Focus on clear words and rhythm; don't worry about your accent."
                    else:
                        continue
                    if value != ex["explanationAr"]:
                        translations[ex["explanationAr"]] = value
                    prompt = ex["promptAr"]
                    for source, target in (("ترجم إلى الإنجليزية:", "Translate to English:"), ("رتب الكلمات لتكوين الجملة:", "Arrange the words to form the sentence:")):
                        if prompt.startswith(source):
                            translations[prompt] = target + prompt[len(source):]
                    if prompt.startswith("Arrange the words to form the sentence:"):
                        translations[prompt] = prompt.replace("Arrange the words to form the sentence:", "Put these words in order:", 1)
                    if prompt.startswith("اختر التعبير الذي يعني «"):
                        translations[prompt] = prompt.replace("اختر التعبير الذي يعني «", "Choose the expression meaning «", 1).replace("» لإكمال الجملة:", "» to complete the sentence:")
                    if prompt.startswith("ما معنى "):
                        translations[prompt] = "What does “" + (ex.get("promptEn") or "") + "” mean?"


def polished_learning_copy(value):
    """Mirror the runtime editorial replacements so exact lookup still works."""
    source = (ROOT / "EnglishNova/Data/Local/CurriculumEnhancer.swift").read_text()
    section = source.split("enum ArabicLearningCopy", 1)[1]
    exact_source, replacements_source = section.split("private static let phraseReplacements", 1)
    pairs = lambda text: [(json.loads('"' + a + '"'), json.loads('"' + b + '"')) for a, b in re.findall(r'"((?:\\.|[^"\\])*)"\s*[:,]\s*"((?:\\.|[^"\\])*)"', text)]
    exact = dict(pairs(exact_source))
    replacements = pairs(replacements_source.split("static func polish", 1)[0])
    if value in exact:
        return exact[value]
    for old, new in replacements:
        value = value.replace(old, new)
    while "  " in value:
        value = value.replace("  ", " ")
    for old, new in ((" ،", "،"), (" .", "."), (" ؟", "؟"), (" !", "!")):
        value = value.replace(old, new)
    if value.endswith("الإجابة الصحيح"):
        value = value[:-len("الإجابة الصحيح")] + "الإجابة الصحيحة"
    return value.strip()


def register_polished_aliases(translations):
    for key, value in list(translations.items()):
        polished = polished_learning_copy(key)
        if polished != key:
            translations[polished] = value
