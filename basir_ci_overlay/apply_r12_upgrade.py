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
        if not rejects or not rejects.issubset(OPTIONAL_REJECTS):
            raise SystemExit(f"R12 patch returned {result.returncode} without only approved optional rejects")
        print("R12 optional compatibility targets absent; continuing after strict verification.")

    cleanup = overlay / "cleanup_r12_user_ui.py"
    subprocess.run([sys.executable, str(cleanup), str(root)], check=True)

    polish = overlay / "polish_r12_background.py"
    subprocess.run([sys.executable, str(polish), str(root)], check=True)

    accounting_patch = overlay / "fix_r12_accounting_resume.patch"
    if not accounting_patch.is_file():
        raise SystemExit("R12 exact-accounting patch is missing")
    subprocess.run(
        ["patch", "-p1", "--forward", "--batch", "-i", str(accounting_patch)],
        cwd=root,
        check=True,
    )

    finalize_ui = overlay / "finalize_r12_accounting_ui.py"
    subprocess.run([sys.executable, str(finalize_ui), str(root)], check=True)

    checks = [
        ("BasirConvert/Models/SettingsStore.swift", "preferredModel"),
        ("BasirConvert/Models/AppModels.swift", "Gemini 3.7 Flash"),
        ("BasirConvert/Models/AppModels.swift", "let skipped: Int?"),
        ("BasirConvert/Services/ProxyClient.swift", "preferred_model"),
        ("BasirConvert/Services/ProxyClient.swift", "skipped: skippedItems.count"),
        ("BasirConvert/ViewModels/AppViewModel.swift", "resumeInterruptedJobsIfNeeded"),
        ("BasirConvert/ViewModels/AppViewModel.swift", "TRANSPORT_CANCELLED resumable server task preserved"),
        ("BasirConvert/Views/JobView.swift", "المحاسبة"),
        ("BasirConvert/Views/JobView.swift", "الصفحات الفارغة التي تم تخطيها"),
        ("BasirConvert/Views/JobView.swift", "if !job.failedItems.isEmpty"),
        ("BasirConvert/Views/SettingsView.swift", "preferredModel"),
        ("BasirConvert/Views/SettingsView.swift", "checkmark.circle.fill"),
        ("BasirConvert/Views/SettingsView.swift", "xmark.circle.fill"),
        ("BasirConvert/Views/Components.swift", "BASIR_POLISHED_BACKGROUND_R12"),
        ("R12_CHANGELOG_AR.md", "R12"),
        ("tools/verify_project.py", "user_model_selection"),
    ]
    for relative, needle in checks:
        path = root / relative
        if not path.is_file():
            raise SystemExit(f"R12 verification failed: missing required file {relative}")
        text = path.read_text(encoding="utf-8")
        if needle not in text:
            raise SystemExit(f"R12 verification failed: {relative} missing {needle}")

    settings = (root / "BasirConvert/Views/SettingsView.swift").read_text(encoding="utf-8")
    for forbidden in ("هذا اختيار تنفيذي حقيقي", "خادم بصير", "فحص اتصال الخادم"):
        if forbidden in settings:
            raise SystemExit(f"R12 UI verification failed: unwanted text remains: {forbidden}")

    print("BASIR_IOS_UPGRADE=UNIVERSAL_RELIABILITY_GUARD_R12_EXACT_ACCOUNTING")


if __name__ == "__main__":
    main()
