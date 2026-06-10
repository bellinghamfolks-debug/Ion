#!/usr/bin/env python3
"""Scores a PDFToWord DOCX against the 20-page Arabic scientific benchmark.

Usage:
    python3 Tools/evaluate_scientific_benchmark.py Output.docx
    python3 Tools/evaluate_scientific_benchmark.py Output.docx --json report.json

The evaluator checks both visible text and OOXML semantics. It does not award a
perfect score merely because a DOCX opens. Each of the 20 benchmark sections is
worth five points.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
import zipfile
from collections import Counter
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Callable, Iterable
from xml.etree import ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
WP = "{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}"
PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"


def normalized(value: str) -> str:
    value = unicodedata.normalize("NFC", value)
    value = value.replace("\u200e", "").replace("\u200f", "").replace("\ufeff", "")
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"[ \t]+", " ", value)
    return value


def compact(value: str) -> str:
    return re.sub(r"\s+", "", normalized(value))


def occurrence(text: str, token: str) -> int:
    return normalized(text).count(normalized(token))


def all_present(text: str, tokens: Iterable[str]) -> bool:
    n = normalized(text)
    return all(normalized(token) in n for token in tokens)


@dataclass
class SectionResult:
    code: str
    title: str
    score: float
    maximum: float
    passed: list[str]
    failed: list[str]
    critical: bool = False


class DocxFacts:
    def __init__(self, path: Path):
        self.path = path
        if not path.is_file():
            raise FileNotFoundError(path)
        if not zipfile.is_zipfile(path):
            raise ValueError("The output is not a valid ZIP-based DOCX package.")
        with zipfile.ZipFile(path) as zf:
            self.names = set(zf.namelist())
            self.parts = {
                name: zf.read(name)
                for name in self.names
                if name.endswith(".xml") or name.endswith(".rels")
            }
            self.media = {
                name: zf.read(name)
                for name in self.names
                if name.startswith("word/media/")
            }

        self.document_xml = self.parts.get("word/document.xml", b"").decode("utf-8", "replace")
        self.document_root = ET.fromstring(self.parts["word/document.xml"])
        self.body_text = self._part_text("word/document.xml")
        self.header_text = "\n".join(
            self._part_text(name) for name in sorted(self.names)
            if re.fullmatch(r"word/header\d+\.xml", name)
        )
        self.footer_text = "\n".join(
            self._part_text(name) for name in sorted(self.names)
            if re.fullmatch(r"word/footer\d+\.xml", name)
        )
        self.footnote_text = self._part_text("word/footnotes.xml")
        self.all_text = "\n".join([self.body_text, self.header_text, self.footer_text, self.footnote_text])
        self.raw_all = "\n".join(data.decode("utf-8", "replace") for data in self.parts.values())
        self.alt_texts = self._alt_texts()
        self.hyperlink_targets = self._external_targets("word/_rels/document.xml.rels")

    def _part_text(self, name: str) -> str:
        raw = self.parts.get(name)
        if not raw:
            return ""
        try:
            root = ET.fromstring(raw)
        except ET.ParseError:
            return ""
        paragraphs: list[str] = []
        for paragraph in root.iter(W + "p"):
            pieces: list[str] = []
            for node in paragraph.iter():
                if node.tag == W + "t" and node.text:
                    pieces.append(node.text)
                elif node.tag == W + "tab":
                    pieces.append("\t")
                elif node.tag in (W + "br", W + "cr"):
                    pieces.append("\n")
            if pieces:
                paragraphs.append("".join(pieces))
        return "\n".join(paragraphs)

    def _alt_texts(self) -> list[str]:
        values: list[str] = []
        for raw in self.parts.values():
            try:
                root = ET.fromstring(raw)
            except ET.ParseError:
                continue
            for node in root.iter(WP + "docPr"):
                description = node.attrib.get("descr", "").strip()
                title = node.attrib.get("title", "").strip()
                if description:
                    values.append(description)
                elif title:
                    values.append(title)
        return values

    def _external_targets(self, name: str) -> list[str]:
        raw = self.parts.get(name)
        if not raw:
            return []
        try:
            root = ET.fromstring(raw)
        except ET.ParseError:
            return []
        output = []
        for rel in root.iter(PKG_REL + "Relationship"):
            if rel.attrib.get("TargetMode") == "External":
                output.append(rel.attrib.get("Target", ""))
        return output

    @property
    def table_count(self) -> int:
        return len(list(self.document_root.iter(W + "tbl")))

    @property
    def row_count(self) -> int:
        return len(list(self.document_root.iter(W + "tr")))

    @property
    def drawing_count(self) -> int:
        return self.raw_all.count("<w:drawing")

    @property
    def paragraph_count(self) -> int:
        return len(list(self.document_root.iter(W + "p")))


class Section:
    def __init__(self, code: str, title: str, critical: bool = False):
        self.code = code
        self.title = title
        self.critical = critical
        self.checks: list[tuple[str, Callable[[DocxFacts], bool], float]] = []

    def add(self, label: str, predicate: Callable[[DocxFacts], bool], points: float = 1.0) -> "Section":
        self.checks.append((label, predicate, points))
        return self

    def evaluate(self, facts: DocxFacts) -> SectionResult:
        passed: list[str] = []
        failed: list[str] = []
        earned = 0.0
        maximum = sum(points for _, _, points in self.checks)
        for label, predicate, points in self.checks:
            try:
                ok = bool(predicate(facts))
            except Exception:
                ok = False
            if ok:
                earned += points
                passed.append(label)
            else:
                failed.append(label)
        scaled = 5.0 * earned / maximum if maximum else 0.0
        return SectionResult(self.code, self.title, round(scaled, 2), 5.0, passed, failed, self.critical)


def token_once(token: str, *, any_text: bool = False) -> Callable[[DocxFacts], bool]:
    return lambda f: occurrence(f.all_text if any_text else f.body_text, token) == 1


def tokens(tokens_: Iterable[str], *, any_text: bool = False) -> Callable[[DocxFacts], bool]:
    return lambda f: all_present(f.all_text if any_text else f.body_text, tokens_)


def raw_contains(fragment: str) -> Callable[[DocxFacts], bool]:
    return lambda f: fragment in f.raw_all


def build_sections() -> list[Section]:
    sections: list[Section] = []

    sections.append(Section("COVER", "الغلاف وسلامة المستند", True)
        .add("عبارة سلامة الغلاف محفوظة مرة واحدة", token_once("زمردة-47-نهر91-AX"), 2)
        .add("رمز الملف محفوظ", tokens(["PW-BENCH-AR-2026-01"]), 1)
        .add("العنوان يحوي PDF وWord", lambda f: "PDF" in f.body_text and "Word" in f.body_text, 1)
        .add("لا يوجد انفجار غير منطقي في الفقرات", lambda f: f.paragraph_count < 800, 1))

    sections.append(Section("T01", "النص العربي الرقمي وترتيب الفقرات", True)
        .add("المعرّفات الخمسة موجودة مرة واحدة", lambda f: all(occurrence(f.body_text, f"T01-{i:03d}-AR") == 1 for i in range(1, 6)), 2)
        .add("الهمزات والتاء المربوطة محفوظة", tokens(["أ، إ، آ", "مدرسة", "وجهه"]), 1)
        .add("الأرقام العربية والغربية والمبلغ محفوظة", tokens(["١٤٤٧", "2026", "12,345.67"]), 1)
        .add("عبارة نهاية الصفحة فريدة", token_once("باب أزرق لا يفتح مرتين"), 1))

    bidi_tokens = [
        "KSU-2026-AX19", "legal.qa+ios@example.com", "https://example.org/test?id=47&lang=ar",
        "+966 55 123 4567", "08:35 PM", "09-06-2026", "Documents/Benchmark/Output-v1.docx",
        "12,450.75 SAR", "v2.3.1-build.407"
    ]
    sections.append(Section("T02", "الاتجاه المختلط Bidi والمعرّفات", True)
        .add("المعرّف لا ينقلب", tokens(["KSU-2026-AX19", "AX19-B7"]), 1)
        .add("البريد والرابط محفوظان", tokens(bidi_tokens[1:3]), 1)
        .add("الهاتف والوقت والتاريخ محفوظة", tokens(bidi_tokens[3:6]), 1)
        .add("المسار والإصدار محفوظان", tokens([bidi_tokens[6], "iOS 26.4"]), 1)
        .add("قيم الجدول المختلطة محفوظة", tokens(bidi_tokens[7:]), 1))

    sections.append(Section("T03", "الأنماط الطباعية وUnicode")
        .add("العريض والمائل وتحته خط موجودة كتنسيق Word", lambda f: all(x in f.raw_all for x in ["<w:b", "<w:i", "<w:u"]), 1)
        .add("المشطوب والتظليل واللون موجودة", lambda f: all(x in f.raw_all for x in ["<w:strike", "<w:shd", "<w:color"]), 1)
        .add("الأسس والمؤشرات محفوظة", lambda f: f.raw_all.count("<w:vertAlign") >= 2, 1)
        .add("الرموز العلمية والخاصة محفوظة", tokens(["π", "Ω", "√", "∞", "★", "✓", "©"]), 1)
        .add("رمز التحقق محفوظ", tokens(["TYPO", "2026", "♠"]), 1))

    sections.append(Section("T04", "القوائم متعددة المستويات")
        .add("المستويات ممثلة بـ numPr", lambda f: f.raw_all.count("<w:numPr") >= 6, 2)
        .add("يوجد أكثر من مستوى قائمة", lambda f: len(set(re.findall(r'<w:ilvl w:val="(\d+)"', f.raw_all))) >= 3, 1)
        .add("العبارتان الحرجتان محفوظتان", tokens(["عدم حذف الكلمات", "عدم اختلاق كلمات"]), 1)
        .add("الأرقام الرومانية والإنجليزية محفوظة", tokens(["Roman numeral", "English number"]), 1))

    def column_order(f: DocxFacts) -> bool:
        c = compact(f.body_text)
        markers = ["COL-A-01", "COL-A-02", "COL-A-03", "COL-B-01", "COL-B-02", "COL-B-03", "COL-C-01", "COL-C-02", "COL-C-03", "TEXTBOX-T05"]
        positions = [c.find(compact(m)) for m in markers]
        return all(pos >= 0 for pos in positions) and positions == sorted(positions)
    sections.append(Section("T05", "الأعمدة وترتيب القراءة", True)
        .add("تسلسل الأعمدة A ثم B ثم C صحيح", column_order, 3)
        .add("كلمات نهايات الأعمدة محفوظة", tokens(["نخلة", "مرآة", "سحابة"]), 1)
        .add("الصندوق الجانبي يأتي بعد الأعمدة", lambda f: compact(f.body_text).find("TEXTBOX-T05") > compact(f.body_text).find("COL-C-03"), 1))

    sections.append(Section("T06", "الرؤوس والتذييلات والعلامة المائية")
        .add("رأس Word مستقل موجود", lambda f: any(re.fullmatch(r"word/header\d+\.xml", n) for n in f.names), 1)
        .add("تذييل Word مستقل موجود", lambda f: any(re.fullmatch(r"word/footer\d+\.xml", n) for n in f.names), 1)
        .add("رموز الرأس لا تتكرر داخل المتن", lambda f: occurrence(f.body_text, "HEADER-T06-L") <= 1 and occurrence(f.body_text, "HEADER-T06-R") <= 1, 1)
        .add("فقرات المتن الثلاث محفوظة", lambda f: all(occurrence(f.body_text, f"BODY-T06-0{i}") == 1 for i in range(1,4)), 1)
        .add("العلامة المائية لا تنفجر إلى تكرارات", lambda f: occurrence(f.all_text, "نسخة اختبار") <= 2, 1))

    sections.append(Section("T07", "الجدول العربي البسيط", True)
        .add("جدول Word حقيقي موجود", lambda f: f.table_count >= 1, 1)
        .add("الرموز والقيم محفوظة", tokens(["TB-A1", "TB-A2", "TB-A3", "12.50", "37.50", "103.75"]), 2)
        .add("دمج أفقي موجود", raw_contains("<w:gridSpan"), 1)
        .add("العناوين الخمسة محفوظة", tokens(["الرمز", "الوصف", "الكمية", "سعر الوحدة", "الإجمالي"]), 1))

    sections.append(Section("T08", "الخلايا المدمجة والبنية المتداخلة", True)
        .add("الدمج الأفقي موجود", raw_contains("<w:gridSpan"), 1)
        .add("الدمج الرأسي موجود", raw_contains("<w:vMerge"), 1)
        .add("رمز البنية المتداخلة محفوظ", token_once("NEST-T08"), 1)
        .add("القيم المتداخلة محفوظة", tokens(["مراجعة: 7", "مقبول: 6"]), 1)
        .add("رمز الخلية النهائية محفوظ", token_once("MERGE-T08-END"), 1))

    sections.append(Section("T09", "استمرارية الجدول الطويل", True)
        .add("الصفوف 01 إلى 15 موجودة مرة واحدة", lambda f: all(occurrence(f.body_text, f"ROW-{i:02d}") == 1 for i in range(1,16)), 1.5)
        .add("الصفوف 16 إلى 30 موجودة مرة واحدة", lambda f: all(occurrence(f.body_text, f"ROW-{i:02d}") == 1 for i in range(16,31)), 1.5)
        .add("لا توجد صفوف خارج النطاق", lambda f: not re.search(r"ROW-(?:00|3[1-9]|[4-9]\d)", f.body_text), 0.5)
        .add("رأس جدول مكرر دلاليًا في Word", lambda f: "<w:tblHeader" in f.raw_all, 0.5)
        .add("القيم الطرفية محفوظة", tokens(["1017", "1255", "1272", "1510"]), 1))

    sections.append(Section("T10", "الصور والالتفاف والتسميات")
        .add("صور فعلية مضمّنة", lambda f: len(f.media) >= 2, 1.5)
        .add("كل صورة ذات وصف بديل", lambda f: len(f.alt_texts) >= 2 and all(a.strip() for a in f.alt_texts), 1.5)
        .add("تسمية الشكل محفوظة", tokens(["شكل", "الأشكال الهندسية الثلاثة"]), 1)
        .add("الرمز المرجعي للصورة محفوظ", tokens(["IMG-T10-01", "CAPTION-T10-01"]), 1))

    sections.append(Section("T11", "المخططات المتجهية والرسوم البيانية")
        .add("المخطط أو الرسم محفوظ كصورة", lambda f: len(f.media) >= 3, 2)
        .add("وصف بديل للمخطط موجود", lambda f: any("مخطط" in a or "رسم" in a or "chart" in a.lower() or "diagram" in a.lower() for a in f.alt_texts), 1)
        .add("رمز المسار محفوظ", token_once("FLOW-T11-01"), 1)
        .add("رمز الرسم البياني محفوظ", tokens(["CHART-T11-01"]), 1))

    sections.append(Section("T12", "المعادلات والرموز العلمية")
        .add("المعادلات الخمس موجودة", lambda f: all(occurrence(f.body_text, f"EQ-0{i}") == 1 for i in range(1,6)), 2)
        .add("الجذر والتكامل والتقاطع والمجموع محفوظة", tokens(["√", "∫", "∩", "Σ"]), 1)
        .add("الأسس أو المؤشرات ممثلة بتنسيق", raw_contains("<w:vertAlign"), 1)
        .add("جدول الرموز محفوظ", tokens(["≥", "≠", "∞"]), 1))

    sections.append(Section("T13", "الروابط والحواشي والإحالات الداخلية")
        .add("علاقة رابط خارجي حقيقية", lambda f: len(f.hyperlink_targets) >= 1, 1)
        .add("ملف footnotes.xml موجود", lambda f: "word/footnotes.xml" in f.names, 1)
        .add("مرجع حاشية موجود داخل المتن", raw_contains("<w:footnoteReference"), 1)
        .add("Bookmark وإحالة داخلية موجودان", lambda f: "<w:bookmarkStart" in f.raw_all and 'w:anchor=' in f.raw_all, 1)
        .add("نصوص الأقسام والحاشية محفوظة", tokens(["REF-A", "REF-B", "FOOTNOTE-T13-01"], any_text=True), 1))

    sections.append(Section("T14", "المسح الضوئي الجيد", True)
        .add("المبلغ الحرج مستخرج", tokens(["12,450.75"]), 1)
        .add("التاريخ مستخرج", lambda f: "9 يونيو 2026" in f.body_text or "09-06-2026" in f.body_text, 1)
        .add("النهاية المرجعية مستخرجة", tokens(["شمس هادئة فوق نافذة زرقاء"]), 2)
        .add("الختم محفوظ بصريًا أو نصيًا", lambda f: "TEST" in f.all_text or any("ختم" in a or "seal" in a.lower() for a in f.alt_texts), 1))

    sections.append(Section("T15", "المسح المنخفض الجودة والمنحرف", True)
        .add("الصفحة محفوظة بصريًا عند الشك", lambda f: any(("17" in a or "منخفضة" in a or "منحرف" in a or "low" in a.lower()) for a in f.alt_texts) or len(f.media) >= 5, 2)
        .add("لا يوجد انفجار نصي من الضوضاء", lambda f: f.paragraph_count < 800 and "��������" not in f.body_text, 1)
        .add("البيانات الواضحة إن استخرجت بقيت صحيحة", lambda f: not any(bad in f.body_text for bad in ["684.05", "18.05", "2026-09-06"]), 1)
        .add("لا توجد فقرة مكررة عشر مرات", lambda f: max(Counter(line.strip() for line in f.body_text.splitlines() if len(line.strip()) > 15).values(), default=0) < 10, 1))

    sections.append(Section("T16", "مربعات الاختيار والختم والتوقيع")
        .add("رمز النموذج محفوظ", token_once("FORM-T16-01"), 1)
        .add("حالات الاختيار محفوظة", tokens(["مكتمل", "غير مكتمل", "يحتاج مراجعة"]), 1)
        .add("رموز الاختيار أو دوائرها محفوظة", lambda f: any(sym in f.body_text for sym in ["☒", "☐", "◉", "○"]), 1)
        .add("الختم له صورة ووصف بديل", lambda f: any("ختم" in a or "seal" in a.lower() for a in f.alt_texts), 1)
        .add("التوقيع له صورة ووصف بديل", lambda f: any("توقيع" in a or "signature" in a.lower() for a in f.alt_texts), 1))

    sections.append(Section("T17", "المناطق الفارغة والعناصر المدورة")
        .add("رمز أعلى اليمين محفوظ", token_once("TOP-RIGHT-T17"), 1)
        .add("رمز أسفل اليسار محفوظ", token_once("BOTTOM-LEFT-T17"), 1)
        .add("النص المدور محفوظ كنص أو صورة موصوفة", lambda f: "ROTATED" in f.body_text or any("مدو" in a or "rotat" in a.lower() for a in f.alt_texts), 1)
        .add("رمز نهاية الحافة محفوظ", lambda f: "END17" in f.body_text and "8842" in f.body_text, 1)
        .add("المساحة الفارغة لم تُملأ بتكرار", lambda f: occurrence(f.body_text, "هذه مساحة فارغة مقصودة") <= 1, 1))

    def dense_ok(f: DocxFacts) -> bool:
        return all(occurrence(f.body_text, f"DENSE-{i:03d}") == 1 for i in range(1,49))
    sections.append(Section("T18", "إجهاد الكثافة وكشف التكرار", True)
        .add("الأسطر 001 إلى 048 موجودة مرة واحدة", dense_ok, 3)
        .add("القيم الطرفية محفوظة", tokens(["7013", "017X", "7624", "816X"]), 1)
        .add("عدد علامات DENSE يساوي 48", lambda f: len(re.findall(r"DENSE-\d{3}", f.body_text)) == 48, 1))

    return sections


def grade(score: float) -> str:
    if score >= 95: return "ممتاز"
    if score >= 90: return "جيد جدًا مرتفع"
    if score >= 80: return "جيد جدًا"
    if score >= 70: return "جيد"
    if score >= 60: return "مقبول"
    return "غير مجتاز"


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate a DOCX against the 20-page Arabic PDF-to-Word benchmark.")
    parser.add_argument("docx", type=Path)
    parser.add_argument("--json", dest="json_path", type=Path)
    args = parser.parse_args()

    try:
        facts = DocxFacts(args.docx)
    except Exception as error:
        print(f"تعذر فحص الملف: {error}", file=sys.stderr)
        return 2

    results = [section.evaluate(facts) for section in build_sections()]
    total = round(sum(item.score for item in results), 2)
    critical_failures = [item.code for item in results if item.critical and item.score < 4.0]
    excellent_pass = total >= 95 and not critical_failures

    report = {
        "file": str(args.docx),
        "score": total,
        "maximum": 100,
        "grade": grade(total),
        "excellent_pass": excellent_pass,
        "critical_failures": critical_failures,
        "package": {
            "paragraphs": facts.paragraph_count,
            "tables": facts.table_count,
            "table_rows": facts.row_count,
            "media_files": len(facts.media),
            "alt_text_entries": len(facts.alt_texts),
            "external_hyperlinks": len(facts.hyperlink_targets),
            "has_footnotes": "word/footnotes.xml" in facts.names,
        },
        "sections": [asdict(item) for item in results],
    }

    print(f"نتيجة معيار PDFToWord: {total:.2f} من 100، التقدير: {grade(total)}")
    print(f"اجتياز ممتاز صارم: {'نعم' if excellent_pass else 'لا'}")
    if critical_failures:
        print("أقسام حرجة لم تبلغ 4 من 5: " + ", ".join(critical_failures))
    print()
    for item in results:
        status = "✓" if item.score >= 4.0 else "!"
        print(f"{status} {item.code}: {item.title}: {item.score:.2f}/5")
        for failure in item.failed:
            print(f"   - لم يجتز: {failure}")

    if args.json_path:
        args.json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"\nحُفظ التقرير التفصيلي في: {args.json_path}")
    return 0 if excellent_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
