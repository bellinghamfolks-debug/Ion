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
        jobs[index].serverCancelPending = nil
        let message: String
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
            "تعذر تأكيد الإلغاء بسبب الاتصال. سيواصل بصير إرسال الطلب تلقائيًا حتى يتأكد توقف المهمة.",
            "A connection issue prevented cancellation from being confirmed. Basir will keep retrying until the task is confirmed as stopped."
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
