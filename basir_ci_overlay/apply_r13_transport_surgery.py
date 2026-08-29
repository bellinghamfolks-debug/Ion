#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
vm_path = root / "BasirConvert/ViewModels/AppViewModel.swift"
proxy_path = root / "BasirConvert/Services/ProxyClient.swift"
models_path = root / "BasirConvert/Models/AppModels.swift"
if not all(path.is_file() for path in (vm_path, proxy_path, models_path)):
    raise SystemExit("R13 surgery: required iOS source files are missing")

vm = vm_path.read_text(encoding="utf-8")
proxy = proxy_path.read_text(encoding="utf-8")
models = models_path.read_text(encoding="utf-8")
has_skipped = "let skipped: Int?" in models


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"R13 {label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_function(text: str, signature: str, replacement: str, label: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"R13 {label}: function signature not found")
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"R13 {label}: opening brace not found")
    depth = 0
    end = None
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise SystemExit(f"R13 {label}: closing brace not found")
    return text[:start] + replacement + text[end:]


if "transportReconnectAttempts" not in vm:
    vm = replace_once(
        vm,
        "    private var networkLossTask: Task<Void, Never>?\n",
        "    private var networkLossTask: Task<Void, Never>?\n"
        "    private var transportReconnectTasks: [UUID: Task<Void, Never>] = [:]\n"
        "    private var transportReconnectAttempts: [UUID: Int] = [:]\n",
        "reconnect state",
    )

old_head = '''    private func processNextIfPossible() {
        guard jobTask == nil,
              let settings,
              let l10n,
              let index = jobs.firstIndex(where: { [.queued, .waitingForNetwork].contains($0.status) }) else { return }
'''
new_head = '''    private func processNextIfPossible(preferredJobID: UUID? = nil) {
        guard jobTask == nil,
              let settings,
              let l10n else { return }
        let preferredIndex = preferredJobID.flatMap { preferred in
            jobs.firstIndex(where: {
                $0.id == preferred && [.queued, .waitingForNetwork].contains($0.status)
            })
        }
        guard let index = preferredIndex
                ?? jobs.firstIndex(where: { [.queued, .waitingForNetwork].contains($0.status) }) else { return }
'''
if old_head in vm:
    vm = vm.replace(old_head, new_head, 1)
elif "private func processNextIfPossible(preferredJobID: UUID? = nil)" not in vm:
    raise SystemExit("R13 preferred reconnect selection: processNextIfPossible shape changed")

old_apply_start = '''    private func apply(_ update: ConversionProgress, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status == .running else { return }
        jobs[index].progress = update
'''
skipped_arg = ",\n                skipped: previous.skipped" if has_skipped else ""
new_apply_start = f'''    private func apply(_ update: ConversionProgress, to jobID: UUID) {{
        guard let index = jobs.firstIndex(where: {{ $0.id == jobID }}), jobs[index].status == .running else {{ return }}
        let previous = jobs[index].progress
        if update.stage == .processing,
           previous.current > 0,
           (update.total == 0 || update.current < previous.current) {{
            jobs[index].progress = ConversionProgress(
                current: previous.current,
                total: max(previous.total, update.total),
                stage: .processing,
                detail: update.detail ?? previous.detail,
                transferredBytes: update.transferredBytes,
                totalBytes: update.totalBytes,
                succeeded: max(previous.succeeded, update.succeeded),
                failed: max(previous.failed, update.failed){skipped_arg}
            )
        }} else {{
            jobs[index].progress = update
        }}
'''
if old_apply_start in vm:
    vm = vm.replace(old_apply_start, new_apply_start, 1)
elif "(update.total == 0 || update.current < previous.current)" not in vm:
    raise SystemExit("R13 monotonic progress: apply() shape changed")

old_catches = '''            } catch is CancellationError {
                handleCancellation(jobID: jobID, logger: logger)
            } catch {
                finish(jobID: jobID, error: error, logger: logger, output: output)
            }
'''
new_catches = '''            } catch is CancellationError {
                handleCancellation(jobID: jobID, logger: logger)
            } catch let urlError as URLError where urlError.code == .cancelled {
                handleTransportCancellation(jobID: jobID, logger: logger)
            } catch {
                finish(jobID: jobID, error: error, logger: logger, output: output)
            }
'''
if old_catches in vm:
    vm = vm.replace(old_catches, new_catches, 1)

skipped_reconnect = ",\n            skipped: jobs[index].progress.skipped" if has_skipped else ""
handler = f'''    private func handleTransportCancellation(jobID: UUID, logger: DiagnosticLogger) {{
        if pauseRequested || networkPauseRequested {{
            handleCancellation(jobID: jobID, logger: logger)
            return
        }}
        guard let index = jobs.firstIndex(where: {{ $0.id == jobID }}) else {{
            completeCurrentTaskAndContinue(allowNext: false)
            return
        }}

        let attempt = min((transportReconnectAttempts[jobID] ?? 0) + 1, 6)
        transportReconnectAttempts[jobID] = attempt
        let delaySeconds = min(8, 1 << min(attempt - 1, 3))
        logger.record(
            "TRANSPORT_INTERRUPTED_RECONNECT attempt=\\(attempt) delay=\\(delaySeconds)s "
            + "progress=\\(jobs[index].progress.current)/\\(jobs[index].progress.total)"
        )

        jobs[index].status = .queued
        jobs[index].automaticResumePending = true
        jobs[index].progress = ConversionProgress(
            current: jobs[index].progress.current,
            total: jobs[index].progress.total,
            stage: .processing,
            detail: l10n?.t(
                "انقطعت متابعة الاتصال لحظيًا. جارٍ إعادة الاتصال بنفس مهمة الخادم دون فقد التقدم.",
                "Connection monitoring was interrupted. Reconnecting to the same server task without losing progress."
            ),
            transferredBytes: jobs[index].progress.transferredBytes,
            totalBytes: jobs[index].progress.totalBytes,
            succeeded: jobs[index].progress.succeeded,
            failed: jobs[index].progress.failed{skipped_reconnect}
        )
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        selectedJobID = jobID
        if let diagnostic = jobs[index].diagnosticURL {{ try? logger.write(to: diagnostic) }}
        persist()
        syncFacade()

        completeCurrentTaskAndContinue(allowNext: false)
        transportReconnectTasks[jobID]?.cancel()
        transportReconnectTasks[jobID] = Task {{ [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self else {{ return }}
            self.transportReconnectTasks[jobID] = nil
            guard let retryIndex = self.jobs.firstIndex(where: {{ $0.id == jobID }}),
                  self.jobs[retryIndex].status == .queued,
                  self.jobs[retryIndex].automaticResumePending == true else {{ return }}
            self.jobs[retryIndex].automaticResumePending = false
            self.jobs[retryIndex].updatedAt = Date()
            self.persist()
            self.syncFacade()
            self.processNextIfPossible(preferredJobID: jobID)
        }}
    }}'''
if "private func handleTransportCancellation(jobID: UUID, logger: DiagnosticLogger)" in vm:
    vm = replace_function(
        vm,
        "    private func handleTransportCancellation(jobID: UUID, logger: DiagnosticLogger)",
        handler,
        "transport cancellation",
    )
else:
    marker = "    private func handleCancellation(jobID: UUID, logger: DiagnosticLogger)"
    pos = vm.find(marker)
    if pos < 0:
        raise SystemExit("R13 transport handler insertion point missing")
    vm = vm[:pos] + handler + "\n\n" + vm[pos:]

finish_sig = "    private func finish(jobID: UUID, error: Error, logger: DiagnosticLogger?, output: URL?) {"
finish_guard = '''
        if let urlError = error as? URLError,
           urlError.code == .cancelled,
           let logger {
            handleTransportCancellation(jobID: jobID, logger: logger)
            return
        }
'''
finish_pos = vm.find(finish_sig)
if finish_pos < 0:
    raise SystemExit("R13 finish() not found")
brace = vm.find("{", finish_pos)
near = vm[brace:brace + 500]
if "handleTransportCancellation(jobID: jobID, logger: logger)" not in near:
    vm = vm[:brace + 1] + finish_guard + vm[brace + 1:]

old_retry_codes = '''            return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(url.code)
'''
new_retry_codes = '''            return [.cancelled, .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(url.code)
'''
if old_retry_codes in proxy:
    proxy = proxy.replace(old_retry_codes, new_retry_codes, 1)
elif ".cancelled, .timedOut" not in proxy:
    raise SystemExit("R13 ProxyClient retry list shape changed")

proxy = proxy.replace("Basir-iOS/2.3.0-R12", "Basir-iOS/2.3.0-R13", 1)
if 'minimum: "2.9.0"' in proxy:
    proxy = proxy.replace('minimum: "2.9.0"', 'minimum: "2.12.0"')
elif 'minimum: "2.12.0"' not in proxy:
    proxy += '\n// R13_SERVER_MINIMUM_EXPECTED_2_12_0\n'

vm_path.write_text(vm, encoding="utf-8")
proxy_path.write_text(proxy, encoding="utf-8")

final_vm = vm_path.read_text(encoding="utf-8")
final_proxy = proxy_path.read_text(encoding="utf-8")
required_vm = (
    "transportReconnectAttempts",
    "TRANSPORT_INTERRUPTED_RECONNECT",
    "processNextIfPossible(preferredJobID: UUID? = nil)",
    "processNextIfPossible(preferredJobID: jobID)",
    "update.total == 0 || update.current < previous.current",
    "urlError.code == .cancelled",
)
required_proxy = (
    ".cancelled, .timedOut",
    "Basir-iOS/2.3.0-R13",
)
for marker in required_vm:
    if marker not in final_vm:
        raise SystemExit(f"R13 AppViewModel gate missing {marker!r}")
for marker in required_proxy:
    if marker not in final_proxy:
        raise SystemExit(f"R13 ProxyClient gate missing {marker!r}")
if 'minimum: "2.9.0"' in final_proxy:
    raise SystemExit("R13 server minimum remained at 2.9.0")

print("BASIR_IOS_SURGERY=R13_SAME_JOB_RECONNECT_MONOTONIC_PROGRESS")
