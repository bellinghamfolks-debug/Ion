#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import plistlib
import re
import struct
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"VERIFY FAILED: {message}")


def require_file(path: Path, root: Path) -> None:
    if not path.is_file():
        fail(f"missing {path.relative_to(root)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()

    required = [
        root / "BasirConvert/Supporting/Info.plist",
        root / "BasirConvert/Supporting/LaunchScreen.storyboard",
        root / "BasirConvert/Supporting/PrivacyInfo.xcprivacy",
        root / "BasirConvert/BasirConvert.entitlements",
        root / "BasirShareExtension/Info.plist",
        root / "BasirShareExtension/ShareExtension.entitlements",
        root / "project.yml",
        root / "cloud-project.yml",
        root / "scripts/build_unsigned_ipa.sh",
    ]
    if not args.source_only:
        required += [
            root / "BasirConvert.xcodeproj/project.pbxproj",
            root / "BasirConvert.xcodeproj/xcshareddata/xcschemes/BasirConvert.xcscheme",
        ]
    for path in required:
        require_file(path, root)

    with (root / "BasirConvert/Supporting/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("Info.plist bundle identifier is not build-setting based")
    if not info.get("LSSupportsOpeningDocumentsInPlace"):
        fail("in-place document access is disabled")
    if info.get("UILaunchStoryboardName") != "LaunchScreen":
        fail("a real launch storyboard is required")
    if info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"):
        fail("arbitrary insecure network loads must remain disabled")
    if info.get("UIFileSharingEnabled"):
        fail("the complete Documents directory must not be exposed")
    if "UISupportedInterfaceOrientations~ipad" in info:
        fail("iPad metadata is present in the iPhone-only build")
    for key in ("BasirServerURL", "BasirClientToken"):
        if key not in info:
            fail(f"missing injected setting {key}")
    content_types = {
        item
        for declaration in info.get("CFBundleDocumentTypes", [])
        for item in declaration.get("LSItemContentTypes", [])
    }
    if "public.image" not in content_types:
        fail("images are not registered for opening from other apps")

    with (root / "BasirConvert/Supporting/PrivacyInfo.xcprivacy").open("rb") as handle:
        privacy = plistlib.load(handle)
    if privacy.get("NSPrivacyTracking") is not False:
        fail("privacy manifest must declare tracking disabled")

    entitlement_values: list[list[str]] = []
    for relative in (
        "BasirConvert/BasirConvert.entitlements",
        "BasirShareExtension/ShareExtension.entitlements",
    ):
        with (root / relative).open("rb") as handle:
            entitlement_values.append(
                plistlib.load(handle).get("com.apple.security.application-groups", [])
            )
    if entitlement_values != [["group.com.basir.convert.ios"], ["group.com.basir.convert.ios"]]:
        fail("app and Share Extension App Group entitlements do not match")

    for name in ("project.yml", "cloud-project.yml"):
        specification = (root / name).read_text(encoding="utf-8")
        for token in (
            'TARGETED_DEVICE_FAMILY: "1"',
            "INFOPLIST_FILE: BasirConvert/Supporting/Info.plist",
            "CODE_SIGN_ENTITLEMENTS: BasirConvert/BasirConvert.entitlements",
            "CODE_SIGN_ENTITLEMENTS: BasirShareExtension/ShareExtension.entitlements",
            "MARKETING_VERSION: 3.0.0",
            "CURRENT_PROJECT_VERSION: 11",
        ):
            if token not in specification:
                fail(f"{name} is missing {token}")
        if re.search(r"(?m)^\s{4}info:\s*$", specification):
            fail(f"{name} would overwrite the maintained Info.plist")

    for json_path in root.rglob("*.json"):
        try:
            json.loads(json_path.read_text(encoding="utf-8"))
        except Exception as exc:
            fail(f"invalid JSON in {json_path.relative_to(root)}: {exc}")

    swift_files = sorted((root / "BasirConvert").rglob("*.swift"))
    test_files = sorted((root / "BasirConvertTests").glob("*.swift"))
    if len(swift_files) < 25:
        fail("unexpectedly small Swift source set")
    if len(test_files) < 2:
        fail("contract and page-selection unit tests are missing")
    combined = "\n".join(path.read_text(encoding="utf-8") for path in swift_files)
    if re.search(r"generativelanguage|x-goog-api-key|AIza[0-9A-Za-z_-]{20,}", combined, re.IGNORECASE):
        fail("the app contains a direct provider endpoint or API credential")
    if re.search(r"\biPad\b", combined, re.IGNORECASE):
        fail("iPad-only interface code remains")

    picker = (root / "BasirConvert/Views/DocumentPicker.swift").read_text(encoding="utf-8")
    if "UIDocumentPickerViewController" not in picker or "asCopy: true" not in picker:
        fail("the reliable copy-mode document picker is missing")
    view_source = "\n".join(
        (root / "BasirConvert/Views" / name).read_text(encoding="utf-8")
        for name in ("ConvertView.swift", "TranslateView.swift")
    )
    if ".fileImporter(" in view_source:
        fail("the unreliable SwiftUI file importer was reintroduced")

    proxy = (root / "BasirConvert/Services/ProxyClient.swift").read_text(encoding="utf-8")
    for token in (
        "api_contract_v3",
        "pageSelection: normalizedPageSelection",
        "JobStatusResponse",
        "Idempotency-Key",
        "Basir-iOS/3.0.0",
    ):
        if token not in proxy and token not in combined:
            fail(f"stable server contract is missing {token}")
    for obsolete in ("serverVersionAtLeast", "BASIR_CLIENT_ENGINE_EPOCH_GUARD", "minimum: \"2."):
        if obsolete in proxy:
            fail(f"obsolete server coupling remains: {obsolete}")

    required_sources = (
        "BackgroundTransferCoordinator.swift",
        "NetworkMonitor.swift",
        "PageSelectionNormalizer.swift",
        "PersistentJobStore.swift",
        "ServerContract.swift",
    )
    names = {path.name for path in swift_files}
    for name in required_sources:
        if name not in names:
            fail(f"missing maintained source {name}")

    build_script = (root / "scripts/build_unsigned_ipa.sh").read_text(encoding="utf-8")
    for token in (
        "CODE_SIGNING_ALLOWED=NO",
        "BasirShareExtension.appex",
        "_CodeSignature",
        "Basir_v3.0.0_unsigned.ipa",
    ):
        if token not in build_script:
            fail(f"unsigned build script is missing {token}")
    if "codesign --force" in build_script:
        fail("the unsigned package script unexpectedly signs code")

    expected = json.loads((root / "BasirConvertTests/Fixtures/expected.json").read_text(encoding="utf-8"))
    pages = sorted((root / "BasirConvertTests/Fixtures/markdown").glob("page-*.md"))
    if len(pages) != expected["source_pages"]:
        fail("reference page fixture count does not match expected.json")
    table_count = sum(
        len(re.findall(r"(?m)^\|(?:\s*:?-{3,}:?\s*\|)+\s*$", page.read_text(encoding="utf-8")))
        for page in pages
    )
    if table_count != expected["expected_tables"]:
        fail(f"reference Markdown has {table_count} tables, expected {expected['expected_tables']}")

    icon = root / "BasirConvert/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    data = icon.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (1024, 1024):
        fail("app icon is not a 1024x1024 PNG")

    if not args.source_only:
        pbx = (root / "BasirConvert.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        for token in ("BasirConvertTests", "ZIPFoundation", "BasirShareExtension"):
            if token not in pbx:
                fail(f"Xcode project is missing {token}")

    mode = "source" if args.source_only else "generated project"
    print(
        f"Static verification: OK ({mode}; {len(swift_files)} app sources, "
        f"{len(test_files)} tests, {len(pages)} fixture pages, {table_count} tables)"
    )


if __name__ == "__main__":
    main()

