#!/usr/bin/env python3
"""Static release validation for EnglishNova Batch 4 merged project."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "EnglishNova"
TESTS = ROOT / "EnglishNovaTests"
PBX = ROOT / "EnglishNova.xcodeproj" / "project.pbxproj"
CURRICULUM = APP / "Resources" / "Curriculum" / "curriculum.json"
MANIFEST = ROOT / "PROJECT_MANIFEST.json"

errors: list[str] = []
notes: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def run(command: list[str], label: str) -> None:
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        errors.append(f"{label}: {result.stderr.strip() or result.stdout.strip()}")
    else:
        notes.append(f"نجح: {label}")


# 1. Curriculum structure and counts.
data = json.loads(CURRICULUM.read_text(encoding="utf-8"))
levels = data["levels"]
lessons = [lesson for level in levels for unit in level["units"] for lesson in unit["lessons"]]
exercises = [exercise for lesson in lessons for exercise in lesson["exercises"]]
vocabulary = [word for lesson in lessons for word in lesson["vocabulary"]]
level_counts = {level["level"].upper(): sum(len(unit["lessons"]) for unit in level["units"]) for level in levels}

require(len(levels) == 6, "يجب أن يحتوي المنهج على ستة مستويات CEFR.")
require(len(lessons) == 152, f"عدد الدروس غير متوقع: {len(lessons)}")
require(level_counts.get("A0") == 60, f"عدد دروس A0 غير متوقع: {level_counts.get('A0')}")
require(level_counts.get("A1") == 60, f"عدد دروس A1 غير متوقع: {level_counts.get('A1')}")
require(len(exercises) == 880, f"عدد التمارين غير متوقع: {len(exercises)}")
require(len(vocabulary) == 456, f"عدد المفردات غير متوقع: {len(vocabulary)}")
for name, items in {
    "الدروس": [item["id"] for item in lessons],
    "التمارين": [item["id"] for item in exercises],
}.items():
    duplicates = [key for key, count in Counter(items).items() if count > 1]
    require(not duplicates, f"توجد معرفات مكررة في {name}: {duplicates[:5]}")

required_beginner_types = {"explanation", "listenAndChoose", "multipleChoice", "arrangeWords", "translation", "speak"}
for level in levels:
    if level["level"].upper() in {"A0", "A1"}:
        for unit in level["units"]:
            for lesson in unit["lessons"]:
                found = {exercise["type"] for exercise in lesson["exercises"]}
                require(required_beginner_types.issubset(found), f"الدرس {lesson['id']} ينقصه نوع تمرين تأسيسي.")

# 2. Source/project membership.
app_files = sorted(APP.rglob("*.swift"))
test_files = sorted(TESTS.rglob("*.swift"))
all_swift = app_files + test_files
require(len(app_files) == 81, f"عدد ملفات Swift للتطبيق غير متوقع: {len(app_files)}")
require(len(test_files) == 12, f"عدد ملفات الاختبار غير متوقع: {len(test_files)}")
require(len({path.name for path in all_swift}) == len(all_swift), "توجد أسماء ملفات Swift مكررة قد تربك مشروع Xcode.")

pbx = PBX.read_text(encoding="utf-8")
file_ref_pattern = re.compile(
    r"^\s*([A-F0-9]{24}) /\* ([^*]+\.swift) \*/ = \{\s*isa = PBXFileReference;",
    re.MULTILINE,
)
build_file_pattern = re.compile(
    r"^\s*([A-F0-9]{24}) /\* ([^*]+\.swift) in Sources \*/ = \{\s*isa = PBXBuildFile;\s*fileRef = ([A-F0-9]{24})",
    re.MULTILINE,
)
file_refs = {name: identifier for identifier, name in file_ref_pattern.findall(pbx)}
build_files = {name: (identifier, reference) for identifier, name, reference in build_file_pattern.findall(pbx)}

for path in all_swift:
    require(path.name in file_refs, f"الملف غير مسجل كمرجع في مشروع Xcode: {path.name}")
    require(path.name in build_files, f"الملف غير مسجل في مرحلة البناء: {path.name}")
    if path.name in file_refs and path.name in build_files:
        require(build_files[path.name][1] == file_refs[path.name], f"مرجع بناء غير متطابق: {path.name}")
        build_id = build_files[path.name][0]
        require(pbx.count(build_id) >= 2, f"الملف غير مضاف إلى قائمة Sources الفعلية: {path.name}")

# Resolve PBX group hierarchy to ensure Xcode points at the real on-disk file,
# not merely at a matching basename in the wrong group.
group_section_match = re.search(
    r"/\* Begin PBXGroup section \*/(.*?)/\* End PBXGroup section \*/",
    pbx,
    re.DOTALL,
)
require(group_section_match is not None, "تعذر العثور على قسم مجموعات Xcode.")
groups: dict[str, tuple[str, list[str]]] = {}
parent_by_child: dict[str, str] = {}
if group_section_match:
    group_section = group_section_match.group(1)
    group_pattern = re.compile(
        r"^\s*([A-F0-9]{24}) /\* .*? \*/ = \{\n(.*?)(?=^\s*\};)",
        re.MULTILINE | re.DOTALL,
    )
    for group_id, body in group_pattern.findall(group_section):
        if "isa = PBXGroup;" not in body:
            continue
        path_match = re.search(r'\bpath = (?:"([^"]*)"|([^;]+));', body)
        group_path_value = ""
        if path_match:
            group_path_value = (path_match.group(1) or path_match.group(2) or "").strip()
        children_match = re.search(r"children = \((.*?)\);", body, re.DOTALL)
        children = re.findall(r"([A-F0-9]{24}) /\*", children_match.group(1) if children_match else "")
        groups[group_id] = (group_path_value, children)
        for child in children:
            require(child not in parent_by_child, f"مرجع Xcode موجود في أكثر من مجموعة: {child}")
            parent_by_child[child] = group_id

    main_group_match = re.search(r"mainGroup = ([A-F0-9]{24});", pbx)
    require(main_group_match is not None, "تعذر تحديد المجموعة الجذرية لمشروع Xcode.")
    main_group = main_group_match.group(1) if main_group_match else ""

    resolved_group_cache: dict[str, Path] = {}

    def resolved_group_path(group_id: str, visiting: set[str] | None = None) -> Path:
        if group_id in resolved_group_cache:
            return resolved_group_cache[group_id]
        visiting = set() if visiting is None else visiting
        require(group_id not in visiting, f"حلقة في مجموعات Xcode عند {group_id}")
        if group_id in visiting:
            return Path()
        visiting.add(group_id)
        own_path = Path(groups.get(group_id, ("", []))[0]) if groups.get(group_id, ("", []))[0] else Path()
        if group_id == main_group or group_id not in parent_by_child:
            result = own_path
        else:
            result = resolved_group_path(parent_by_child[group_id], visiting) / own_path
        resolved_group_cache[group_id] = result
        visiting.remove(group_id)
        return result

    ref_path_by_id: dict[str, str] = {}
    file_ref_section_match = re.search(
        r"/\* Begin PBXFileReference section \*/(.*?)/\* End PBXFileReference section \*/",
        pbx,
        re.DOTALL,
    )
    if file_ref_section_match:
        file_object_pattern = re.compile(
            r"^\s*([A-F0-9]{24}) /\* .*? \*/ = \{\n(.*?)(?=^\s*\};)",
            re.MULTILINE | re.DOTALL,
        )
        for ref_id, body in file_object_pattern.findall(file_ref_section_match.group(1)):
            path_match = re.search(r'\bpath = (?:"([^"]*)"|([^;]+));', body)
            if path_match:
                ref_path_by_id[ref_id] = (path_match.group(1) or path_match.group(2) or "").strip()

    for disk_path in all_swift:
        ref_id = file_refs.get(disk_path.name)
        if not ref_id:
            continue
        parent_id = parent_by_child.get(ref_id)
        require(parent_id is not None, f"مرجع الملف غير موضوع في مجموعة Xcode: {disk_path.name}")
        if parent_id is None:
            continue
        project_relative = resolved_group_path(parent_id) / ref_path_by_id.get(ref_id, disk_path.name)
        actual_relative = disk_path.relative_to(ROOT)
        require(
            project_relative == actual_relative,
            f"مسار Xcode لا يطابق القرص للملف {disk_path.name}: {project_relative} بدل {actual_relative}",
        )

object_ids = re.findall(r"^\s*([A-F0-9]{24}) /\*.*?\*/ = \{", pbx, re.MULTILINE)
require(len(object_ids) == len(set(object_ids)), "توجد معرفات PBX مكررة في ملف المشروع.")
require("curriculum.json" in pbx and "in Resources" in pbx, "ملف المنهج غير مسجل ضمن موارد التطبيق.")

# 3. Feature catalog counts.
placement_source = (APP / "Data/Local/PlacementQuestionBank.swift").read_text(encoding="utf-8")
conversation_source = (APP / "Data/Local/ConversationLibrary.swift").read_text(encoding="utf-8")
story_source = (APP / "Data/Local/InteractiveStoryLibrary.swift").read_text(encoding="utf-8")
placement_count = len(re.findall(r"^\s*q\(", placement_source, re.MULTILINE))
conversation_count = len(re.findall(r"^\s*scenario\(", conversation_source, re.MULTILINE))
story_count = len(re.findall(r"^\s*build\(", story_source, re.MULTILINE))
ielts_count = len(re.findall(r'speaking\("ielts-', conversation_source))
step_count = len(re.findall(r'choice\("step-', conversation_source))
interview_count = len(re.findall(r'interview\("int-', conversation_source))
require(placement_count == 48, f"عدد أسئلة تحديد المستوى غير متوقع: {placement_count}")
require(conversation_count == 12, f"عدد سيناريوهات المحادثة غير متوقع: {conversation_count}")
require(story_count == 12, f"عدد القصص التفاعلية غير متوقع: {story_count}")
require(ielts_count == 12, f"عدد أسئلة IELTS غير متوقع: {ielts_count}")
require(step_count == 24, f"عدد أسئلة STEP غير متوقع: {step_count}")
require(interview_count == 18, f"عدد أسئلة المقابلات غير متوقع: {interview_count}")

advanced_source = (APP / "Data/Local/AdvancedSkillsLibrary.swift").read_text(encoding="utf-8")
def section_count(start: str, end: str) -> int:
    body = advanced_source.split(start, 1)[1].split(end, 1)[0]
    return len(re.findall(r"^\s*\.init\(", body, re.MULTILINE))

reading_activities = section_count("private static let readingSeeds", "private static let listeningSeeds") * 2
listening_activities = section_count("private static let listeningSeeds", "private static let writingSeeds") * 2
writing_activities = section_count("private static let writingSeeds", "private static func makeReading") * 2
require(reading_activities == 24, f"عدد أنشطة القراءة غير متوقع: {reading_activities}")
require(listening_activities == 24, f"عدد أنشطة الاستماع غير متوقع: {listening_activities}")
require(writing_activities == 24, f"عدد مهام الكتابة غير متوقع: {writing_activities}")
require("AdaptiveReviewEngine" in (APP / "Data/Local/MasteryEngine.swift").read_text(encoding="utf-8"), "محرك المراجعة التكيفية غير موجود.")
require("schemaVersion: 4" in (APP / "Core/Persistence/BackupService.swift").read_text(encoding="utf-8"), "مخطط النسخ الاحتياطي ليس الإصدار الرابع.")

# 4. Manifest consistency.
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
expected_manifest = {
    "batch": 4,
    "version": "0.4.0",
    "swiftSourceFiles": len(app_files),
    "testFiles": len(test_files),
    "levels": len(levels),
    "lessons": len(lessons),
    "a0Lessons": level_counts["A0"],
    "a1Lessons": level_counts["A1"],
    "exercises": len(exercises),
    "vocabularyEntries": len(vocabulary),
    "interactiveStories": story_count,
    "conversationScenarios": conversation_count,
    "placementQuestions": placement_count,
    "ieltsSpeakingQuestions": ielts_count,
    "stepQuestions": step_count,
    "interviewQuestions": interview_count,
    "readingActivities": reading_activities,
    "listeningActivities": listening_activities,
    "writingActivities": writing_activities,
    "learningPathways": 6,
    "backupSchema": 4,
}
for key, expected in expected_manifest.items():
    require(manifest.get(key) == expected, f"قيمة البيان {key} لا تطابق المشروع: {manifest.get(key)} بدل {expected}")

# 5. Safety and release hygiene.
source_text = "\n".join(path.read_text(encoding="utf-8") for path in app_files)
require("try!" not in source_text, "يوجد try! غير آمن في ملفات التطبيق.")
require(" as! " not in source_text, "يوجد تحويل نوع إجباري as! في ملفات التطبيق.")
secret_patterns = [
    r"AIza[0-9A-Za-z_-]{20,}",
    r"sk-[0-9A-Za-z]{20,}",
    r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
]
for pattern in secret_patterns:
    require(re.search(pattern, source_text) is None, "عُثر على نمط قد يمثل مفتاحًا سريًا داخل الشفرة.")

# 6. Tool-backed syntax/property-list checks.
if shutil.which("plutil"):
    run(["plutil", "-lint", str(PBX)], "سلامة ملف مشروع Xcode")
else:
    notes.append("تخطّي plutil لعدم توفره.")

if shutil.which("swiftc"):
    for path in all_swift:
        run(["swiftc", "-frontend", "-parse", str(path)], f"تحليل Swift: {path.relative_to(ROOT)}")
else:
    notes.append("تخطّي تحليل Swift لعدم توفر swiftc.")

if errors:
    print("فشل فحص الإصدار:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("نجح فحص مشروع EnglishNova، الدفعة الرابعة المدمجة.")
print(f"- ملفات Swift للتطبيق: {len(app_files)}")
print(f"- ملفات الاختبارات: {len(test_files)}")
print(f"- المستويات: {len(levels)}")
print(f"- الدروس: {len(lessons)}")
print(f"- التمارين: {len(exercises)}")
print(f"- المفردات التعليمية: {len(vocabulary)}")
print(f"- أسئلة تحديد المستوى: {placement_count}")
print(f"- سيناريوهات المحادثة: {conversation_count}")
print(f"- القصص التفاعلية: {story_count}")
print(f"- أسئلة IELTS Speaking: {ielts_count}")
print(f"- أسئلة STEP: {step_count}")
print(f"- أسئلة المقابلات: {interview_count}")
print(f"- أنشطة القراءة المتقدمة: {reading_activities}")
print(f"- أنشطة الاستماع المتقدمة: {listening_activities}")
print(f"- مهام الكتابة المتقدمة: {writing_activities}")
print(f"- اختبارات Swift النحوية المنفذة: {len(all_swift)}")
