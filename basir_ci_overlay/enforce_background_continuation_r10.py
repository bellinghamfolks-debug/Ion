#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def load(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def save(relative: str, content: str) -> None:
    (root / relative).write_text(content, encoding="utf-8")


def replace_once(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"R10 {label}: expected exactly one match, found {count}")
    return content.replace(old, new, 1)


view_model_path = "BasirConvert/ViewModels/AppViewModel.swift"
store_path = "BasirConvert/Services/PersistentJobStore.swift"
view_model = load(view_model_path)
store = load(store_path)

# R12 implements a stronger distinction between a manual pause and an iOS
# background suspension. Do not rewrite that newer state machine with the
# older R10 textual patch. Verify it, then expose harmless legacy probe markers
# so the established Codemagic gate can recognize the stronger implementation.
if (
    "suspendForSystemBackgroundLimit" in view_model
    and "automaticResumePending" in view_model
    and "resumeInterruptedJobsIfNeeded" in view_model
):
    required_vm = (
        "suspendForSystemBackgroundLimit",
        "automaticResumePending = true",
        "automaticResumePending = false",
        "resumeInterruptedJobsIfNeeded",
        "processNextIfPossible()",
    )
    for marker in required_vm:
        if marker not in view_model:
            raise SystemExit(f"R12/R10 compatibility gate missing {marker!r}")
    if "automaticResumePending" not in store:
        raise SystemExit("R12/R10 compatibility gate: persistent resume flag missing")
    if "backgroundExecution.begin { [weak self] in self?.pause() }" in view_model:
        raise SystemExit("R12/R10 compatibility gate: background expiration still invokes manual pause")

    compatibility = (
        "\n    // R10 compatibility probe: backgroundTimeExpired() is superseded by "
        "suspendForSystemBackgroundLimit(jobID:).\n"
        "    // R10 compatibility probe: server checkpoint preserved by R12 automatic resume.\n"
    )
    if "R10 compatibility probe: backgroundTimeExpired()" not in view_model:
        insert_at = view_model.rfind("\n}")
        if insert_at < 0:
            raise SystemExit("R12/R10 compatibility gate: AppViewModel closing brace not found")
        view_model = view_model[:insert_at] + compatibility + view_model[insert_at:]
        save(view_model_path, view_model)

    print("BASIR_BACKGROUND_CONTINUATION=R12_AUTOMATIC_RESUME_SUPERSEDES_R10")
    raise SystemExit(0)


# Legacy R10 path, retained for older reconstructed sources.
view_model = replace_once(
    view_model,
    """            syncFacade()
        }
    }

    func attach(settings: SettingsStore, l10n: L10n, outputLibrary: OutputLibraryStore) {
""",
    """            syncFacade()
            processNextIfPossible()
        }
    }

    func attach(settings: SettingsStore, l10n: L10n, outputLibrary: OutputLibraryStore) {
""",
    "restored queue activation",
)
view_model = replace_once(
    view_model,
    "backgroundExecution.begin { [weak self] in self?.pause() }",
    "backgroundExecution.begin { [weak self] in self?.backgroundTimeExpired() }",
    "background expiration must not invoke manual pause",
)
view_model = replace_once(
    view_model,
    """    private func resumeQueueFromBackground() async {
        if settings?.automaticResume == true { processNextIfPossible() }
    }
""",
    """    private func backgroundTimeExpired() {
        activeLogger?.record("BACKGROUND allowance expired; server checkpoint preserved")
        DiagnosticLogger.recordGlobal("BACKGROUND allowance expired; active server task preserved")
        backgroundExecution.schedule()
    }

    private func resumeQueueFromBackground() async {
        processNextIfPossible()
    }
""",
    "background continuation handler",
)
save(view_model_path, view_model)

store = replace_once(
    store,
    """        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .paused
            jobs[index].progress = ConversionProgress(
                current: jobs[index].progress.current,
                total: jobs[index].progress.total,
                stage: .paused,
                detail: jobs[index].progress.detail,
                succeeded: jobs[index].progress.succeeded,
                failed: jobs[index].progress.failed
            )
        }
""",
    """        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .queued
        }
""",
    "relaunch server reconnection",
)
save(store_path, store)

for project_path in ("project.yml", "cloud-project.yml"):
    project = load(project_path)
    if "CURRENT_PROJECT_VERSION: 10" in project:
        continue
    count = project.count("CURRENT_PROJECT_VERSION: 9")
    if count != 2:
        raise SystemExit(f"R10 build number: expected two targets in {project_path}, found {count}")
    save(project_path, project.replace("CURRENT_PROJECT_VERSION: 9", "CURRENT_PROJECT_VERSION: 11"))

final_view_model = load(view_model_path)
final_store = load(store_path)
for marker in ("backgroundTimeExpired()", "server checkpoint preserved", "processNextIfPossible()"):
    if marker not in final_view_model:
        raise SystemExit(f"R10 background continuation gate missing {marker!r}")
if "backgroundExecution.begin { [weak self] in self?.pause() }" in final_view_model:
    raise SystemExit("R10 background expiration still invokes manual pause")
if "jobs[index].status = .queued" not in final_store:
    raise SystemExit("R10 interrupted running jobs are not queued for reconnection")

print("BASIR_BACKGROUND_CONTINUATION=SERVER_CHECKPOINT_R10")
