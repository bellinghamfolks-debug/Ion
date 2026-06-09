#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(__file__).resolve().parents[1]
path = root / "EnglishNova/Resources/Curriculum/curriculum.json"
errors = []

try:
    catalog = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"تعذر قراءة المنهج: {exc}")
    sys.exit(1)

levels = catalog.get("levels", [])
if [level.get("level") for level in levels] != ["A0", "A1", "A2", "B1", "B2", "C1"]:
    errors.append("ترتيب المستويات أو عددها غير صحيح.")

lesson_ids = set()
exercise_ids = set()
lesson_count = exercise_count = word_count = 0
for level in levels:
    lessons = [lesson for unit in level.get("units", []) for lesson in unit.get("lessons", [])]
    code = level.get("level")
    minimum = 60 if code in {"A0", "A1"} else 8
    if len(lessons) < minimum:
        errors.append(f"المستوى {code} يحتوي {len(lessons)} درسًا فقط، والمطلوب {minimum} على الأقل.")
    if code in {"A0", "A1"} and len(level.get("units", [])) != 10:
        errors.append(f"المستوى {code} يجب أن يحتوي 10 وحدات في الدفعة الثانية.")
    for lesson in lessons:
        lesson_count += 1
        lid = lesson.get("id")
        if not lid or lid in lesson_ids:
            errors.append(f"معرف درس مفقود أو مكرر: {lid}")
        lesson_ids.add(lid)
        exercises = lesson.get("exercises", [])
        if not exercises:
            errors.append(f"الدرس {lid} بلا تمارين.")
        if level.get("level") in {"A0", "A1"} and len(exercises) < 6:
            errors.append(f"الدرس {lid} يجب أن يحتوي ستة تمارين متنوعة على الأقل.")
        for exercise in exercises:
            exercise_count += 1
            eid = exercise.get("id")
            if not eid or eid in exercise_ids:
                errors.append(f"معرف تمرين مفقود أو مكرر: {eid}")
            exercise_ids.add(eid)
            if not str(exercise.get("answer", "")).strip():
                errors.append(f"التمرين {eid} بلا إجابة.")
        word_count += len(lesson.get("vocabulary", []))

if errors:
    print("فشل التحقق:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(f"المنهج صالح: {len(levels)} مستويات، {lesson_count} درسًا، {exercise_count} تمرينًا، {word_count} مفردة تعليمية.")
