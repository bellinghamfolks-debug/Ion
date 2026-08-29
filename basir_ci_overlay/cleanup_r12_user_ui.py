#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
settings_path = root / "BasirConvert/Views/SettingsView.swift"
task_path = root / "BasirConvert/Views/TaskComposerView.swift"

if not settings_path.is_file() or not task_path.is_file():
    raise SystemExit("R12 UI cleanup: SettingsView.swift or TaskComposerView.swift is missing")


def remove_text_block_containing(text: str, needle: str) -> tuple[str, int]:
    lines = text.splitlines(keepends=True)
    removed = 0
    index = 0
    while index < len(lines):
        if needle not in lines[index]:
            index += 1
            continue

        start = index
        while start > 0 and "Text(" not in lines[start]:
            start -= 1
        if "Text(" not in lines[start]:
            del lines[index]
            removed += 1
            continue

        depth = 0
        end = start
        seen = False
        while end < len(lines):
            for ch in lines[end]:
                if ch == "(":
                    depth += 1
                    seen = True
                elif ch == ")" and seen:
                    depth -= 1
            end += 1
            if seen and depth <= 0:
                break

        while end < len(lines):
            stripped = lines[end].lstrip()
            if stripped.startswith(".font(") or stripped.startswith(".foregroundStyle(") or stripped.startswith(".multilineTextAlignment(") or stripped.startswith(".fixedSize("):
                end += 1
            else:
                break
        del lines[start:end]
        removed += 1
        index = start
    return "".join(lines), removed


def restore_toggle_status_icons(text: str) -> tuple[str, int]:
    pattern = re.compile(
        r'Toggle\(l10n\.t\("([^"\\]*(?:\\.[^"\\]*)*)",\s*"([^"\\]*(?:\\.[^"\\]*)*)"\),\s*isOn:\s*\$settings\.([A-Za-z_][A-Za-z0-9_]*)\)'
    )

    def repl(match: re.Match[str]) -> str:
        ar, en, prop = match.groups()
        return (
            f'Toggle(isOn: $settings.{prop}) {{\n'
            f'                    HStack(spacing: 10) {{\n'
            f'                        Image(systemName: settings.{prop} ? "checkmark.circle.fill" : "xmark.circle.fill")\n'
            f'                            .accessibilityHidden(true)\n'
            f'                        Text(l10n.t("{ar}", "{en}"))\n'
            f'                    }}\n'
            f'                }}'
        )

    return pattern.subn(repl, text)


settings = settings_path.read_text(encoding="utf-8")
task = task_path.read_text(encoding="utf-8")

for needle in (
    "هذا اختيار تنفيذي حقيقي",
    "يُرسل اسم النموذج إلى الخدمة",
    "يرفض أي نموذج غير مسموح",
):
    settings, _ = remove_text_block_containing(settings, needle)
    task, _ = remove_text_block_containing(task, needle)

replacements = {
    "خادم بصير": "الاتصال",
    "لم يُربط الخادم بهذه النسخة بعد": "الاتصال غير متاح في هذه النسخة",
    "فحص اتصال الخادم": "فحص الاتصال",
    "جارٍ فحص اتصال الخادم": "جارٍ فحص الاتصال",
    "Basir server": "Connection",
    "This build is not connected to the server yet": "Connection is not available in this build",
    "Check server connection": "Check connection",
}
for old, new in replacements.items():
    settings = settings.replace(old, new)
    task = task.replace(old, new)

settings, settings_toggle_count = restore_toggle_status_icons(settings)
task, task_toggle_count = restore_toggle_status_icons(task)

settings_path.write_text(settings, encoding="utf-8")
task_path.write_text(task, encoding="utf-8")

combined = settings + "\n" + task
for forbidden in (
    "هذا اختيار تنفيذي حقيقي",
    "يُرسل اسم النموذج إلى الخدمة",
    "يرفض أي نموذج غير مسموح",
    "خادم بصير",
    "فحص اتصال الخادم",
):
    if forbidden in combined:
        raise SystemExit(f"R12 UI cleanup still contains unwanted text: {forbidden}")

if "checkmark.circle.fill" not in combined or "xmark.circle.fill" not in combined:
    raise SystemExit("R12 UI cleanup could not restore the check/x option symbols")

if "preferredModel" not in settings:
    raise SystemExit("R12 UI cleanup accidentally removed preferredModel controls")

print(f"BASIR_R12_UI_CLEANUP=OK toggles={settings_toggle_count + task_toggle_count}")
