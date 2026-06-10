import SwiftUI
import MessageUI
import CoreLocation

struct EmergencyView: View {
    @EnvironmentObject var settings: BasirSettings
    @StateObject private var location = LocationService.shared
    @StateObject private var tts = SpeechSynthesizer.shared
    @State private var showMessageComposer = false
    @State private var smsBody = ""
    @State private var smsRecipients: [String] = []

    var body: some View {
        BasirScreen {
            BasirStatusBanner(
                text: L10n.t(
                    "بصير لا يتصل بخدمات الطوارئ ولا يرسل رسالة تلقائيًا. سيفتح تطبيق الرسائل لتراجع المستلم والنص والموقع ثم تقرر الإرسال.",
                    "Basir does not contact emergency services or send messages automatically. It opens Messages so you can review the recipient, text, and location before deciding to send."
                ),
                tone: .warning,
                title: L10n.t("ليست خدمة طوارئ", "Not an emergency service")
            )

            if settings.emergencyContact.isEmpty {
                BasirStatusBanner(
                    text: L10n.t(
                        "لا توجد جهة موثوقة محفوظة. أضف رقمًا من الإعدادات لتجهيز رسالة مساعدة.",
                        "No trusted contact is saved. Add a number in Settings to prepare a help message."
                    ),
                    tone: .danger,
                    title: L10n.t("يلزم إضافة رقم", "A contact number is required")
                )

                NavigationLink { SettingsView() } label: {
                    Label(L10n.t("فتح إعدادات جهة المساعدة", "Open help contact settings"),
                          systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
            } else {
                BasirInfoRow(
                    label: L10n.t("الجهة الموثوقة", "Trusted contact"),
                    value: settings.emergencyContact,
                    systemImage: "person.crop.circle.fill.badge.checkmark"
                )

                Button { Task { await prepareHelpRequest() } } label: {
                    Label(L10n.t("تجهيز رسالة مساعدة مع الموقع", "Prepare a help message with location"),
                          systemImage: "sos.circle.fill")
                }
                .buttonStyle(BasirPrimaryButtonStyle(tone: .danger))

                Button { Task { await prepareLocationMessage() } } label: {
                    Label(L10n.t("تجهيز رسالة بالموقع فقط", "Prepare a location-only message"),
                          systemImage: "location.fill")
                }
                .buttonStyle(BasirSecondaryButtonStyle(tone: .info))
            }

            Button { playLocatorSound() } label: {
                Label(L10n.t("تشغيل نداء صوتي: أحتاج إلى مساعدة", "Play audible call: I need help"),
                      systemImage: "speaker.wave.3.fill")
            }
            .buttonStyle(BasirSecondaryButtonStyle(tone: .warning))

            BasirPageIntro(
                text: L10n.t(
                    "الموقع المضاف تقريبي وقد لا يتوفر داخل المباني. راجع الرابط والنص قبل الإرسال.",
                    "The added location is approximate and may be unavailable indoors. Review the link and message before sending."
                ),
                tone: .neutral
            )
        }
        .navigationTitle(L10n.t("طلب مساعدة", "Get help"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMessageComposer) {
            if MFMessageComposeViewController.canSendText() {
                MessageComposer(body: smsBody, recipients: smsRecipients) { _ in
                    showMessageComposer = false
                }
            } else {
                ShareSheet(items: [smsBody])
            }
        }
    }

    private func playLocatorSound() {
        let line = L10n.t("أحتاج إلى مساعدة، أنا هنا.", "I need help. I am here.")
        for _ in 0..<3 { tts.speak(line, utteranceId: "locator") }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func prepareHelpRequest() async {
        let coordinate = await location.fetchOnce()?.coordinate
        let mapsLink = coordinate.map { LocationService.mapsLink(for: $0) }
        smsBody = L10n.t("أحتاج إلى مساعدة. هذا موقعي التقريبي: ",
                          "I need help. This is my approximate location: ")
            + (mapsLink ?? L10n.t("الموقع غير متاح حاليًا.", "Location is currently unavailable."))
        smsRecipients = [settings.emergencyContact]
        showMessageComposer = true
    }

    private func prepareLocationMessage() async {
        let coordinate = await location.fetchOnce()?.coordinate
        let mapsLink = coordinate.map { LocationService.mapsLink(for: $0) }
        smsBody = L10n.t("موقعي التقريبي: ", "My approximate location: ")
            + (mapsLink ?? L10n.t("الموقع غير متاح حاليًا.", "Location is currently unavailable."))
        smsRecipients = [settings.emergencyContact]
        showMessageComposer = true
    }
}

private struct MessageComposer: UIViewControllerRepresentable {
    let body: String
    let recipients: [String]
    let onResult: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = body
        controller.recipients = recipients
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void
        init(onResult: @escaping (MessageComposeResult) -> Void) { self.onResult = onResult }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            onResult(result)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
