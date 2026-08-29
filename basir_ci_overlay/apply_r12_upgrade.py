#!/usr/bin/env python3
from __future__ import annotations

import base64
import pathlib
import subprocess
import sys
import tempfile
import zlib


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_r12_upgrade.py <BasirConvertiOS-root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    overlay = pathlib.Path(__file__).resolve().parent
    if not (root / "BasirConvert").is_dir():
        raise SystemExit(f"invalid Basir source root: {root}")

    names = [f"r12_payload_{index}.txt" for index in range(4)]
    encoded = "".join((overlay / name).read_text(encoding="utf-8").strip() for name in names)
    patch_text = zlib.decompress(base64.b64decode(encoded, validate=True)).decode("utf-8")

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".patch", delete=False) as handle:
        handle.write(patch_text)
        patch_path = pathlib.Path(handle.name)

    try:
        subprocess.run(
            ["patch", "-p1", "--forward", "--batch", "-i", str(patch_path)],
            cwd=root,
            check=True,
        )
    finally:
        patch_path.unlink(missing_ok=True)

    checks = {
        "BasirConvert/Models/SettingsStore.swift": "preferredModel",
        "BasirConvert/Models/AppModels.swift": "Gemini 3.7 Flash",
        "BasirConvert/Services/ProxyClient.swift": "preferred_model",
        "BasirConvert/ViewModels/AppViewModel.swift": "resumeInterruptedJobsIfNeeded",
        "BasirConvert/Views/SettingsView.swift": "preferredModel",
        "R12_CHANGELOG_AR.md": "R12",
    }
    for relative, needle in checks.items():
        text = (root / relative).read_text(encoding="utf-8")
        if needle not in text:
            raise SystemExit(f"R12 verification failed: {relative} missing {needle}")

    print("BASIR_IOS_UPGRADE=UNIVERSAL_RELIABILITY_GUARD_R12")


if __name__ == "__main__":
    main()
