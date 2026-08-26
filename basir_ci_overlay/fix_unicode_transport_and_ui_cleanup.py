#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def load(rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8")


def save(rel: str, text: str) -> None:
    (root / rel).write_text(text, encoding="utf-8")


def remove_swift_block(text: str, signature: str) -> str:
    start = text.find(signature)
    if start < 0:
        return text
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"Malformed Swift block: {signature}")
    depth = 0
    i = brace
    in_string = False
    escape = False
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    while end < len(text) and text[end] in " \t":
                        end += 1
                    if end < len(text) and text[end] == "\n":
                        end += 1
                    return text[:start] + text[end:]
        i += 1
    raise SystemExit(f"Unterminated Swift block: {signature}")


# 1) The top status indicator describes Internet state only. It must not expose
# implementation details about the processing service.
rel = "BasirConvert/Views/Components.swift"
s = load(rel)
s = s.replace('return l10n.t("متصل بخادم بصير", "Basir server online")',
              'return l10n.t("متصل بالإنترنت", "Online")')
s = s.replace('return l10n.t("متصل بالخادم", "Server online")',
              'return l10n.t("متصل بالإنترنت", "Online")')
s = s.replace('return l10n.t("الخادم متصل", "Server online")',
              'return l10n.t("متصل بالإنترنت", "Online")')
s = s.replace('return l10n.t("غير متصل بالخادم", "Server offline")',
              'return l10n.t("غير متصل", "Offline")')
s = save(rel, s)


# 2) Settings are user settings, not deployment diagnostics. Remove the service
# diagnostics card and all wording about a server/build/version.
rel = "BasirConvert/Views/SettingsView.swift"
s = load(rel)
for state_line in (
    '    @State private var testing = false\n',
    '    @State private var testMessage: String?\n',
    '    @State private var testSucceeded = false\n',
):
    s = s.replace(state_line, "")
s = s.replace("                        serverCard\n", "")
s = re.sub(
    r'\n\s*if let testMessage \{\n\s*InlineMessage\(text: testMessage, isError: !testSucceeded\)\n\s*\}\n',
    "\n",
    s,
)
s = s.replace("                        .disabled(testing)\n", "")
s = s.replace("            .interactiveDismissDisabled(testing)\n", "")
s = remove_swift_block(s, "    private var serverCard: some View")
s = remove_swift_block(s, "    private func testServerConnection()")
s = s.replace(
    '"يتصل التطبيق بخادم بصير المشفّر فقط. لا توجد إعلانات أو أدوات تتبع، وتُفحص الملفات قبل رفعها وتُراجع سلامة النتيجة بعد تنزيلها.",\n                                "The app connects only to the encrypted Basir server. It contains no ads or tracking, inspects files before upload, and verifies downloaded results."',
    '"تُنقل الملفات عبر اتصال مشفّر عند تنفيذ المهمة، ولا يحتوي التطبيق على إعلانات أو أدوات تتبع. تُفحص الملفات قبل المعالجة وتُراجع سلامة النتيجة بعد تنزيلها.",\n                                "Files are transferred over an encrypted connection when a task runs. The app contains no ads or tracking, validates inputs, and verifies downloaded results."'
)
# Defensive cleanup for any future copy changes in this view.
s = s.replace("خادم بصير", "الخدمة")
s = s.replace("الخادم", "الخدمة")
s = s.replace("هذه النسخة", "التطبيق")
s = s.replace("Basir server", "service")
s = s.replace("server", "service")
s = s.replace("This build", "The app")
s = save(rel, s)


# 3) Keep confirmations about what happens to the file, without deployment jargon.
rel = "BasirConvert/Views/TaskComposerView.swift"
s = load(rel)
s = s.replace('l10n.t("الخادم غير متاح", "Server unavailable")',
              'l10n.t("تعذر بدء المهمة", "Unable to start")')
s = s.replace(
    'Text(l10n.t("هذه النسخة غير مرتبطة بخادم بصير بعد. ثبّت النسخة النهائية المرتبطة بالخادم.",\n                        "This build is not connected to the Basir server. Install the final server-enabled build."))',
    'Text(l10n.t("تعذر بدء المهمة حاليًا. أغلق التطبيق وافتحه ثم حاول مرة أخرى.",\n                        "The task cannot start right now. Reopen the app and try again."))'
)
s = s.replace(
    '"سيُرسل محتوى \\(pendingURLs.count) من العناصر إلى خادم بصير لمعالجته، ثم تُنزّل النتيجة إلى جهازك.\\(networkNotice)",\n            "Content from \\(pendingURLs.count) item(s) will be sent to the Basir server, then the result will be downloaded to your device.\\(networkNotice)"',
    '"ستُنقل \\(pendingURLs.count) من العناصر عبر اتصال مشفّر للمعالجة، ثم تُنزّل النتيجة إلى جهازك.\\(networkNotice)",\n            "\\(pendingURLs.count) item(s) will be transferred over an encrypted connection for processing, then the result will be downloaded to your device.\\(networkNotice)"'
)
s = s.replace("هذه النسخة", "التطبيق")
s = s.replace("This build", "The app")
s = save(rel, s)


# 4) User-facing error mapping should talk about the service/network, not server
# internals or a particular build/version.
rel = "BasirConvert/ViewModels/AppViewModel.swift"
s = load(rel)
replacements = {
    '"هذه النسخة غير مرتبطة بخادم بصير. ثبّت النسخة النهائية المرتبطة بالخادم.",\n                "This build is not connected to the Basir server. Install the final server-enabled build."':
        '"تعذر بدء المهمة حاليًا. أغلق التطبيق وافتحه ثم حاول مرة أخرى.",\n                "The task cannot start right now. Reopen the app and try again."',
    '"تعذر العثور على عنوان الخادم.", "The server address could not be resolved."':
        '"تعذر العثور على عنوان الخدمة.", "The service address could not be resolved."',
    '"تعذر إنشاء اتصال مشفر موثوق بالخادم.",\n                              "A trusted encrypted connection to the server could not be established."':
        '"تعذر إنشاء اتصال مشفر موثوق بالخدمة.",\n                              "A trusted encrypted connection to the service could not be established."',
    '"هذه النسخة غير مرتبطة بخادم بصير بعد.",\n                          "This build is not connected to the Basir server yet."':
        '"تعذر بدء المهمة حاليًا.",\n                          "The task cannot start right now."',
    '"رابط الخادم غير صالح أو غير آمن. استخدم https.",\n                          "The server address is invalid or insecure. Use https."':
        '"تعذر إنشاء اتصال آمن بالخدمة.",\n                          "A secure service connection could not be created."',
    '"رفض الخادم اتصال هذه النسخة. يلزم إصدار محدث من التطبيق.",\n                          "The server rejected this build. An updated app build is required."':
        '"تعذر التحقق من الاتصال. حدّث التطبيق إذا استمرت المشكلة.",\n                          "The connection could not be verified. Update the app if the problem continues."',
    '"أرسل الخادم نوع ملف غير متوقع بدل Word.",\n                          "The server returned an unexpected file type instead of Word."':
        '"وصل نوع ملف غير متوقع بدل Word.",\n                          "An unexpected file type was returned instead of Word."',
}
for old, new in replacements.items():
    s = s.replace(old, new)
s = s.replace("هذه النسخة", "التطبيق")
s = s.replace("This build", "The app")
s = save(rel, s)


# 5) Low-level fallback descriptions are kept generic too.
rel = "BasirConvert/Models/AppModels.swift"
s = load(rel)
s = s.replace('return "Basir server is not configured in this build."',
              'return "The processing service is not available."')
s = s.replace('return "The Basir server address is invalid."',
              'return "The processing service address is invalid."')
s = s.replace('return "The Basir server returned an invalid response. \\(message)"',
              'return "The processing service returned an invalid response. \\(message)"')
s = save(rel, s)


# Build-time gates. A future UI refactor must not silently restore these strings.
settings_text = load("BasirConvert/Views/SettingsView.swift")
for forbidden in ("خادم", "server", "Server", "هذه النسخة", "This build"):
    if forbidden in settings_text:
        raise SystemExit(f"Settings cleanup failed; forbidden text remains: {forbidden}")
components_text = load("BasirConvert/Views/Components.swift")
for forbidden in ("متصل بخادم بصير", "Basir server online"):
    if forbidden in components_text:
        raise SystemExit(f"Status cleanup failed; forbidden text remains: {forbidden}")
for path in (root / "BasirConvert").rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    if "هذه النسخة" in text or "This build" in text:
        raise SystemExit(f"Build/version wording remains in {path}")

print("BASIR_UI_CLEANUP=NO_SERVER_OR_BUILD_WORDING_R4")
