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
        // Xcode 26 no longer exposes SecTask entitlement inspection to Swift.
        // The extension already falls back to its declared App Group identifier.
        return []
    }
'''

new_static_block = '''    private static func runtimeApplicationGroups() -> [String] {
        // Xcode 26 no longer exposes SecTask entitlement inspection to Swift.
        // FileAccess already falls back to the declared App Group identifier.
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

verify_path = root / "tools" / "verify_project.py"
if not verify_path.is_file():
    raise SystemExit(f"Missing verifier for Xcode 26 patch: {verify_path}")
verify = verify_path.read_text(encoding="utf-8")
old_verify = '''    if "SecTaskCopyValueForEntitlement" not in share_source or "loadDataRepresentation" not in share_source:
        fail("the resilient shared-container import path is missing")
'''
new_verify = '''    if "loadDataRepresentation" not in share_source:
        fail("the resilient shared-container import path is missing")
    if "SecTaskCopyValueForEntitlement" not in share_source and "fallbackAppGroup" not in share_source:
        fail("the shared-container App Group fallback is missing")
'''
if old_verify in verify:
    verify = verify.replace(old_verify, new_verify)
elif "SecTaskCopyValueForEntitlement" in verify and "shared-container import path" in verify:
    raise SystemExit("Unexpected verifier SecTask check shape")
verify_path.write_text(verify, encoding="utf-8")
print("Patched verifier for Xcode 26 App Group fallback.")

for path in targets:
    text = path.read_text(encoding="utf-8")
    if "SecTaskCreateFromSelf" in text or "SecTaskCopyValueForEntitlement" in text:
        raise SystemExit(f"SecTask symbols remain after patch: {path}")

print("Xcode 26 SecTask compatibility patch complete.")
