#!/usr/bin/env python3
from __future__ import annotations

import base64
import pathlib
import subprocess
import sys
import tempfile
import zlib


OPTIONAL_REJECTS = {
    pathlib.PurePosixPath("BasirConvertTests/SecurityTests.swift.rej"),
    pathlib.PurePosixPath("SERVER_LINK_STATUS.txt.rej"),
}


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

    # Remove stale reject files so this run is judged only on its own result.
    for reject in root.rglob("*.rej"):
        reject.unlink(missing_ok=True)

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".patch", delete=False) as handle:
        handle.write(patch_text)
        patch_path = pathlib.Path(handle.name)

    try:
        result = subprocess.run(
            ["patch", "-p1", "--forward", "--batch", "-i", str(patch_path)],
            cwd=root,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.stdout:
            print(result.stdout, end="")
    finally:
        patch_path.unlink(missing_ok=True)

    rejects = {
        pathlib.PurePosixPath(path.relative_to(root).as_posix())
        for path in root.rglob("*.rej")
    }
    unexpected_rejects = rejects - OPTIONAL_REJECTS

    if unexpected_rejects:
        rendered = ", ".join(sorted(str(path) for path in unexpected_rejects))
        raise SystemExit(f"R12 patch failed on required targets: {rendered}")

    if result.returncode != 0:
        # The R12 payload also carries two optional compatibility files that are
        # absent from the reconstructed R11 source. GNU patch returns 1 for
        # those missing targets even though every required app hunk applied.
        # We therefore permit only those exact reject files and verify the
        # required R12 behavior below before declaring success.
        if not rejects or not rejects.issubset(OPTIONAL_REJECTS):
            raise SystemExit(f"R12 patch returned {result.returncode} without only approved optional rejects")
        print("R12 optional compatibility targets absent; continuing after strict verification.")

    checks = {
        "BasirConvert/Models/SettingsStore.swift": "preferredModel",
        "BasirConvert/Models/AppModels.swift": "Gemini 3.7 Flash",
        "BasirConvert/Services/ProxyClient.swift": "preferred_model",
        "BasirConvert/ViewModels/AppViewModel.swift": "resumeInterruptedJobsIfNeeded",
        "BasirConvert/Views/SettingsView.swift": "preferredModel",
        "R12_CHANGELOG_AR.md": "R12",
        "tools/verify_project.py": "user_model_selection",
    }
    for relative, needle in checks.items():
        path = root / relative
        if not path.is_file():
            raise SystemExit(f"R12 verification failed: missing required file {relative}")
        text = path.read_text(encoding="utf-8")
        if needle not in text:
            raise SystemExit(f"R12 verification failed: {relative} missing {needle}")

    print("BASIR_IOS_UPGRADE=UNIVERSAL_RELIABILITY_GUARD_R12")


if __name__ == "__main__":
    main()
