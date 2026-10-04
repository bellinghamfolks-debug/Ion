"""Load the hand-reviewed teaching guides used by expand_curriculum.py.

Guides supplement the existing vocabulary sources; they never replace a lesson
or its stable id. Bilingual copy is also registered for the app's English mode.
"""
from __future__ import annotations

import json
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


def save_guide_translations(guides):
    translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    translations.update({
        "لاحظ طريقة الاستخدام:": "Notice how the language works:",
        "طبّق ما تعلمته:": "Use what you learned:",
        "إجابة ممكنة:": "One possible answer:",
        "اقرأ الموقف ثم اختر الإجابة المناسبة.": "Read the situation and choose the appropriate answer.",
        "اختر إجابة واحدة اعتمادًا على المعنى أو القاعدة المشروحة": "Choose one answer using the meaning or rule explained",
    })
    for guide in guides.values():
        for ar, en in (("focusAr", "focusEn"), ("taskAr", "taskEn"), ("exampleAr", "exampleEn")):
            translations[guide[ar]] = guide[en]
        check = guide["check"]
        translations[check["explanationAr"]] = check["explanationEn"]
        updates = guide.get("lessonUpdates", {})
        if "objectiveAr" in updates and "objectiveEn" in updates:
            translations[updates["objectiveAr"]] = updates["objectiveEn"]
    TRANSLATIONS.write_text(json.dumps(translations, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
