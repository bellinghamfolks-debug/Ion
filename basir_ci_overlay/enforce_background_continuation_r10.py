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


# Server-side conversion continues after iOS suspends the app. Expiration of the
# short foreground grace period must not be reported as a user-requested pause.
view_model_path = "BasirConvert/ViewModels/AppViewModel.swift"
view_model = load(view_model_path)
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
        // This resumes only queued continuations. A task explicitly paused by
        // the user remains paused until the Resume button is activated.
        processNextIfPossible()
    }
""",
    "background continuation handler",
)
save(view_model_path, view_model)


# If iOS terminates the process while the server is working, reconnect using the
# job's stable request ID on next launch instead of presenting a false pause.
store_path = "BasirConvert/Services/PersistentJobStore.swift"
store = load(store_path)
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


# Keep the public version stable while giving this corrected IPA a distinct
# build number for installation and diagnostics. R11 includes this R10
# background correction plus the universal result contract applied later.
for project_path in ("project.yml", "cloud-project.yml"):
    project = load(project_path)
    count = project.count("CURRENT_PROJECT_VERSION: 9")
    if count != 2:
        raise SystemExit(f"R10 build number: expected two targets in {project_path}, found {count}")
    save(project_path, project.replace("CURRENT_PROJECT_VERSION: 9", "CURRENT_PROJECT_VERSION: 11"))


final_view_model = load(view_model_path)
final_store = load(store_path)
required = (
    "backgroundTimeExpired()",
    "server checkpoint preserved",
    "processNextIfPossible()",
)
for marker in required:
    if marker not in final_view_model:
        raise SystemExit(f"R10 background continuation gate missing {marker!r}")
if "backgroundExecution.begin { [weak self] in self?.pause() }" in final_view_model:
    raise SystemExit("R10 background expiration still invokes manual pause")
if "jobs[index].status = .queued" not in final_store:
    raise SystemExit("R10 interrupted running jobs are not queued for reconnection")
if "jobs[index].status = .paused" in final_store:
    raise SystemExit("R10 persistent store still creates a false paused state")

print("BASIR_BACKGROUND_CONTINUATION=SERVER_CHECKPOINT_R10")
