import Foundation
import UIKit

/// Cancelling on the server, retried until the server confirms.
extension AppViewModel {
    /// Sends the cancellation to the server until it is confirmed, with
    /// growing pauses between attempts. Survives relaunches through
    /// `serverCancelPending`, which `attach` and reconnection pick up again.
    func sendServerCancellation(jobID: UUID) {
        guard cancellationTasks[jobID] == nil else { return }
        cancellationTasks[jobID] = Task { [weak self] in
            var attempt = 0
            while let model = self,
                  let job = model.jobs.first(where: { $0.id == jobID }),
                  job.serverCancelPending == true,
                  !Task.isCancelled {
                guard let configuration = model.serverConfiguration else { break }
                do {
                    let outcome = try await ProxyClient(configuration: configuration)
                        .cancelServerTask(requestID: job.requestID)
                    // A create request can still be unwinding after Pause.
                    // A 404 is final only after the local producer has stopped.
                    if case .neverReachedServer = outcome, model.jobTask != nil {
                        attempt += 1
                        try? await Task.sleep(for: .seconds(JobQueuePolicy.cancellationRetryDelay(attempt: attempt)))
                        continue
                    }
                    model.serverCancellationConfirmed(jobID: jobID, outcome: outcome)
                    break
                } catch is CancellationError {
                    break
                } catch {
                    DiagnosticLogger.recordGlobal("CANCEL not confirmed appJob=\(jobID.uuidString) attempt=\(attempt) description=\(error.localizedDescription)")
                    model.serverCancellationWaiting(jobID: jobID)
                    attempt += 1
                    try? await Task.sleep(for: .seconds(JobQueuePolicy.cancellationRetryDelay(attempt: attempt)))
                }
            }
            self?.cancellationTasks[jobID] = nil
        }
    }

    var serverConfiguration: ServerConfiguration? {
        if let configuration = settings?.configuration, configuration.isConfigured { return configuration }
        return lastConfiguration
    }

    func serverCancellationConfirmed(jobID: UUID, outcome: ServerCancellation) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].serverCancelPending = false
        let message: String
        if jobs[index].status == .paused, jobs[index].automaticResumePending != true {
            switch outcome {
            case .cancelled, .neverReachedServer:
                message = l10n?.t(
                    "أكّد الخادم طلب التوقف. لن تُستكمل بقية الصفحات حتى تختار الاستئناف. قد تُحتسب الطلبات التي بدأت قبل التوقف. سيُعاد استخدام النتائج المحفوظة المتوافقة عند الاستئناف.",
                    "The server confirmed the stop request. Remaining pages will wait for you to resume. Requests started before stopping may be charged. Compatible saved results will be reused on resume."
                ) ?? ""
            case .alreadyFinished:
                message = l10n?.t(
                    "اكتملت المعالجة قبل وصول طلب التوقف. اختر «استئناف المهمة» لتنزيل النتيجة الجاهزة دون إعادة التحويل.",
                    "Processing finished before the stop request arrived. Choose Resume task to download the existing result without repeating the conversion."
                ) ?? ""
            }
        } else {
            switch outcome {
            case .cancelled:
                message = l10n?.t(
                    "أُلغيت المهمة وتوقفت معالجتها. الملف الأصلي محفوظ، ويمكنك إعادة المحاولة.",
                    "The task was cancelled and processing has stopped. The original file is saved, so you can try again."
                ) ?? ""
            case .neverReachedServer:
                message = l10n?.t(
                    "أُلغيت المهمة قبل بدء معالجتها على الخادم. الملف الأصلي محفوظ، ويمكنك إعادة المحاولة.",
                    "The task was cancelled before server processing began. The original file is saved, so you can try again."
                ) ?? ""
            case .alreadyFinished:
                message = l10n?.t(
                    "اكتملت المعالجة قبل وصول طلب الإلغاء. اختر «إعادة المحاولة» لتنزيل النتيجة الجاهزة دون تكرار التحويل.",
                    "Processing finished before the cancellation request arrived. Choose Try again to download the existing result without repeating the conversion."
                ) ?? ""
            }
        }
        jobs[index].errorMessage = message
        jobs[index].updatedAt = Date()
        DiagnosticLogger.recordGlobal("CANCEL confirmed appJob=\(jobID.uuidString) outcome=\(outcome)")
        persist()
        syncFacade()
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func serverCancellationWaiting(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].errorMessage = l10n?.t(
            "تعذر تأكيد التوقف بسبب الاتصال؛ قد تستمر المعالجة والتكلفة. سيُعاد إرسال طلب التوقف تلقائيًا.",
            "The server stop could not be confirmed because of the connection; processing and charges may continue. The stop request will be retried automatically."
        )
        persist()
        syncFacade()
    }

    /// Cancellations left unconfirmed by an earlier launch or a lost
    /// connection are sent again.
    func resendPendingCancellations() {
        for job in jobs where job.serverCancelPending == true {
            sendServerCancellation(jobID: job.id)
        }
    }
}
