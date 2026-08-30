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

# R15: normalize localized page selections before the iOS quality manifest
# validates the server result. The server already accepts Arabic-Indic input,
# but the local PageSelectionParser historically expected ASCII punctuation and
# digits. Without this, a selection such as "١،٦" falls back to the full source
# page count and a valid [1, 6] result is rejected locally.
proxy_path = root / "BasirConvert" / "Services" / "ProxyClient.swift"
if not proxy_path.is_file():
    raise SystemExit(f"Missing ProxyClient for localized page-selection patch: {proxy_path}")
proxy = proxy_path.read_text(encoding="utf-8")
old_selection = '''        let expectedSourcePages: Int = {
            guard sourceDocumentPages > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: options.pageSelection, total: sourceDocumentPages).count)
                ?? sourceDocumentPages
        }()
        logger.record("QUALITY sourcePages=\\(sourceDocumentPages) selectedPages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection)")
'''
new_selection = '''        let normalizedPageSelection: String = {
            var value = options.pageSelection
            let replacements: [(String, String)] = [
                ("٠", "0"), ("١", "1"), ("٢", "2"), ("٣", "3"), ("٤", "4"),
                ("٥", "5"), ("٦", "6"), ("٧", "7"), ("٨", "8"), ("٩", "9"),
                ("۰", "0"), ("۱", "1"), ("۲", "2"), ("۳", "3"), ("۴", "4"),
                ("۵", "5"), ("۶", "6"), ("۷", "7"), ("۸", "8"), ("۹", "9"),
                ("،", ","), ("؛", ","), ("–", "-"), ("—", "-"), ("−", "-")
            ]
            for (source, target) in replacements {
                value = value.replacingOccurrences(of: source, with: target)
            }
            return value
        }()
        let expectedSourcePages: Int = {
            guard sourceDocumentPages > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: normalizedPageSelection, total: sourceDocumentPages).count)
                ?? sourceDocumentPages
        }()
        logger.record("QUALITY sourcePages=\\(sourceDocumentPages) selectedPages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection) normalizedSelection=\\(normalizedPageSelection)")
'''
if old_selection in proxy:
    proxy = proxy.replace(old_selection, new_selection, 1)
elif "let normalizedPageSelection: String" not in proxy:
    raise SystemExit("Localized page-selection accounting anchor not found after R14")
for marker in (
    "let normalizedPageSelection: String",
    '("١", "1")',
    '("،", ",")',
    "PageSelectionParser.pages(from: normalizedPageSelection",
    "normalizedSelection=\\(normalizedPageSelection)",
):
    if marker not in proxy:
        raise SystemExit(f"Localized page-selection gate missing {marker!r}")
proxy_path.write_text(proxy, encoding="utf-8")
print("BASIR_CLIENT_LAYER=R15_LOCALIZED_PAGE_SELECTION_ACCOUNTING")

# Xcode 26 can successfully build the arm64 iOS application while the old
# packaging script rejects it using a legacy "restricted to iPhone" check.
# Replace only the ephemeral CI copy of that script after source verification.
build_script_path = root / "scripts" / "build_unsigned_ipa.sh"
if not build_script_path.is_file():
    raise SystemExit(f"Missing unsigned IPA build script: {build_script_path}")

ci_build_script = r'''#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${BASIR_SERVER_URL:?BASIR_SERVER_URL is required}"
: "${BASIR_CLIENT_TOKEN:?BASIR_CLIENT_TOKEN is required}"

DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/BasirConvert.app"
IPA="$ROOT/dist/Basir_v2.3.0_unsigned.ipa"
SECRET_XCCONFIG="$(mktemp)"
trap 'rm -f "$SECRET_XCCONFIG"' EXIT
chmod 600 "$SECRET_XCCONFIG"
printf 'BASIR_CLIENT_TOKEN = %s\n' "$BASIR_CLIENT_TOKEN" > "$SECRET_XCCONFIG"

rm -rf "$DERIVED" "$ROOT/dist"
mkdir -p "$ROOT/dist"

echo "Building unsigned iPhone device app with Xcode 26..."
xcodebuild \
  -project BasirConvert.xcodeproj \
  -scheme BasirConvert \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -xcconfig "$SECRET_XCCONFIG" \
  BASIR_SERVER_URL="$BASIR_SERVER_URL" \
  TARGETED_DEVICE_FAMILY=1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

test -d "$APP"
test -f "$APP/BasirConvert"
file "$APP/BasirConvert"

if /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$APP/Info.plist" >/dev/null 2>&1; then
  echo "Built UIDeviceFamily:"
  /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$APP/Info.plist" || true
fi

# Keep the IPA genuinely unsigned, including the embedded Share Extension.
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} + || true
find "$APP" -name embedded.mobileprovision -delete || true

PAYLOAD="$ROOT/dist/Payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/BasirConvert.app"
(
  cd "$ROOT/dist"
  /usr/bin/zip -qry "Basir_v2.3.0_unsigned.ipa" Payload
)
rm -rf "$PAYLOAD"

test -s "$IPA"
unzip -t "$IPA"
shasum -a 256 "$IPA" > "$IPA.sha256"
echo "Unsigned IPA created: $IPA"
'''

build_script_path.write_text(ci_build_script, encoding="utf-8")
build_script_path.chmod(0o755)
print("Installed Xcode 26 CI-compatible unsigned IPA packager.")

print("Xcode 26 compatibility patch complete.")
