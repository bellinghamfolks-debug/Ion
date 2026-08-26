#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

targets = [
    root / "BasirShareExtension" / "ShareViewController.swift",
    root / "BasirConvert" / "Services" / "FileAccess.swift",
]

old_block = '''    private func runtimeApplicationGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              ) else { return [] }
        return value as? [String] ?? []
    }
'''

old_static_block = '''    private static func runtimeApplicationGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              ) else { return [] }
        return value as? [String] ?? []
    }
'''

new_block = '''    private func runtimeApplicationGroups() -> [String] {
        // SecTask entitlement inspection is not exposed to Swift in the iOS 26 SDK.
        // The configured fallback App Group remains the source of truth.
        return []
    }
'''

new_static_block = '''    private static func runtimeApplicationGroups() -> [String] {
        // SecTask entitlement inspection is not exposed to Swift in the iOS 26 SDK.
        // The configured App Group identifier remains the source of truth.
        return []
    }
'''

for path in targets:
    if not path.is_file():
        raise SystemExit(f"Missing source file for Xcode 26 patch: {path}")
    text = path.read_text(encoding="utf-8")
    text = text.replace("import Security\n", "")
    if path.name == "ShareViewController.swift":
        if old_block in text:
            text = text.replace(old_block, new_block)
        elif "SecTaskCreateFromSelf" in text or "SecTaskCopyValueForEntitlement" in text:
            raise SystemExit(f"Unexpected SecTask block shape in {path}")
    else:
        if old_static_block in text:
            text = text.replace(old_static_block, new_static_block)
        elif "SecTaskCreateFromSelf" in text or "SecTaskCopyValueForEntitlement" in text:
            raise SystemExit(f"Unexpected SecTask block shape in {path}")
    path.write_text(text, encoding="utf-8")
    print(f"Patched for Xcode 26: {path.relative_to(root)}")

for path in targets:
    text = path.read_text(encoding="utf-8")
    if "SecTaskCreateFromSelf" in text or "SecTaskCopyValueForEntitlement" in text:
        raise SystemExit(f"SecTask symbols remain after patch: {path}")

print("Xcode 26 SecTask compatibility patch complete.")
