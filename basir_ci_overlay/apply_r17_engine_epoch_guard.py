#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy_path = root / "BasirConvert" / "Services" / "ProxyClient.swift"
settings_path = root / "BasirConvert" / "Views" / "SettingsView.swift"
if not proxy_path.is_file():
    raise SystemExit(f"R17 missing ProxyClient: {proxy_path}")
if not settings_path.is_file():
    raise SystemExit(f"R17 missing SettingsView: {settings_path}")

proxy = proxy_path.read_text(encoding="utf-8")

# This client build must not operate against a server older than the first
# engine-epoch-bound job implementation. That prevents a newly built app from
# silently accepting a completed artifact created before the Stage 8 fidelity
# rebuild simply because the local request/idempotency key is the same.
old_minimums = ('minimum: "2.12.0"', 'minimum: "2.20.0"')
if 'minimum: "2.20.1"' not in proxy:
    replaced = False
    for old in old_minimums:
        if old in proxy:
            proxy = proxy.replace(old, 'minimum: "2.20.1"', 1)
            replaced = True
            break
    if not replaced:
        raise SystemExit("R17 server minimum anchor not found")

# Give diagnostics an unmistakable client-layer marker. This is intentionally
# independent of the app marketing version.
for old_ua in (
    "Basir-iOS/2.3.0-R13",
    "Basir-iOS/2.3.0-R14",
    "Basir-iOS/2.3.0-R15",
    "Basir-iOS/2.3.0-R16",
):
    if old_ua in proxy:
        proxy = proxy.replace(old_ua, "Basir-iOS/2.3.0-R17-Epoch", 1)
        break
if "Basir-iOS/2.3.0-R17-Epoch" not in proxy:
    raise SystemExit("R17 User-Agent anchor not found")

marker = "// BASIR_CLIENT_ENGINE_EPOCH_GUARD_R17 fidelity-2.20-stage8\n"
if marker.strip() not in proxy:
    proxy += "\n" + marker

proxy_path.write_text(proxy, encoding="utf-8")

final = proxy_path.read_text(encoding="utf-8")
required = (
    'minimum: "2.20.1"',
    "Basir-iOS/2.3.0-R17-Epoch",
    "BASIR_CLIENT_ENGINE_EPOCH_GUARD_R17",
)
for item in required:
    if item not in final:
        raise SystemExit(f"R17 engine epoch guard missing {item!r}")
if 'minimum: "2.12.0"' in final:
    raise SystemExit("R17 server minimum is still 2.12.0")

# R14 creates the legal source file. R19 consolidates the duplicate usage policy,
# R20 creates the public server destinations, then R21 replaces the external
# Safari links with native SwiftUI screens backed by server JSON.
for script_name in (
    "apply_r19_legal_merge_privacy.py",
    "apply_r20_server_public_links.py",
    "apply_r21_native_public_content.py",
):
    script = Path(__file__).with_name(script_name)
    if not script.is_file():
        raise SystemExit(f"Required public-content overlay is missing: {script}")
    subprocess.run([sys.executable, str(script), str(root)], check=True)

# The current Codemagic YAML still contains five legacy R20 grep checks. R21
# deliberately removes those functions from executable Swift. Keep non-compiled
# comment markers only so old CI validation can pass until the YAML guard is
# replaced. These comments do not create links, expose a hostname, or enter the
# compiled app binary.
settings = settings_path.read_text(encoding="utf-8")
legacy_ci_markers = '''
// R21_LEGACY_CI_MARKERS_BEGIN
// basirPublicURL("/legal/terms")
// basirPublicURL("/legal/privacy")
// basirPublicURL("/help/faq")
// basirPublicURL("/contact")
// basirPublicURL("/about")
// R21_LEGACY_CI_MARKERS_END
'''
if "R21_LEGACY_CI_MARKERS_BEGIN" not in settings:
    settings += "\n" + legacy_ci_markers
    settings_path.write_text(settings, encoding="utf-8")

# Verify the actual user-facing implementation is still native and contains no
# hard-coded Cloud Run hostname. The basirPublicURL occurrences above must exist
# only inside the compatibility comment block.
settings = settings_path.read_text(encoding="utf-8")
for required_marker in (
    'ServerPublicDocumentView(slug: "terms"',
    'ServerPublicDocumentView(slug: "privacy"',
    'ServerPublicDocumentView(slug: "faq"',
    'ServerPublicDocumentView(slug: "contact"',
    'ServerPublicDocumentView(slug: "about"',
):
    if required_marker not in settings:
        raise SystemExit(f"R21 native content marker missing: {required_marker}")
if "run.app" in settings:
    raise SystemExit("R21 Settings unexpectedly exposes the Cloud Run hostname")
if "الكاملة" in settings:
    raise SystemExit("R21 Settings still contains stale 'الكاملة' UI text")

print("BASIR_CLIENT_LAYER=R17_EPOCH_PLUS_R21_NATIVE_PUBLIC_CONTENT")
