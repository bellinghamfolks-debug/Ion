import SwiftUI
import UIKit

/// Sends a message to the Basir team. The server saves it and e-mails it to
/// the team inbox with Reply-To set to the sender, then returns a reference.
struct ContactFormView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @AppStorage("contact_name") private var name = ""
    @AppStorage("contact_email") private var email = ""
    @State private var category = "question"
    @State private var subject = ""
    @State private var message = ""
    @State private var includeDeviceInfo = true
    @State private var invalidFields: Set<String> = []
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var reference: String?
    @AccessibilityFocusState private var focusedStatus: Bool

    private static let categories: [(key: String, ar: String, en: String)] = [
        ("question", "استفسار عام", "General question"),
        ("technical", "مشكلة تقنية", "Technical problem"),
        ("quality", "جودة التحويل", "Conversion quality"),
        ("accessibility", "إمكانية الوصول", "Accessibility"),
        ("suggestion", "اقتراح", "Suggestion"),
        ("privacy", "الخصوصية أو حذف البيانات", "Privacy or data deletion"),
        ("other", "أخرى", "Other")
    ]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    if let reference {
                        successCard(reference)
                    } else {
                        form
                    }
                }
                .appScreenContent(bottomPadding: 28)
            }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("تواصل معنا", "Contact us"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.l) {
            Text(l10n.t("راسل فريق بصير", "Write to the Basir team"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(l10n.t("لديك سؤال أو ملاحظة؟ أرسلها إلى فريق بصير، وسنرد على بريدك الإلكتروني.",
                        "Have a question or feedback? Send it to the Basir team, and we’ll reply by email."))
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                InlineMessage(text: errorMessage, isError: true)
                    .accessibilityFocused($focusedStatus)
            }

            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                field(l10n.t("الاسم", "Name"), key: "name", text: $name, content: .name)
                field(l10n.t("البريد الإلكتروني", "Email address"), key: "email", text: $email,
                      content: .emailAddress, keyboard: .emailAddress)
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("نوع الرسالة", "Message type")).font(.headline)
                    Picker(l10n.t("نوع الرسالة", "Message type"), selection: $category) {
                        ForEach(Self.categories, id: \.key) { item in
                            Text(l10n.t(item.ar, item.en)).tag(item.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(BasirPalette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BasirSpacing.s)
                    .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                field(l10n.t("الموضوع (اختياري)", "Subject (optional)"), key: "subject", text: $subject)
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("الرسالة", "Message")).font(.headline)
                    TextEditor(text: $message)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(BasirSpacing.s)
                        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(invalidFields.contains("message") ? BasirPalette.danger : BasirPalette.stroke,
                                        lineWidth: invalidFields.contains("message") ? 2 : 1)
                        }
                        .accessibilityLabel(l10n.t("الرسالة", "Message"))
                        .accessibilityHint(l10n.t("اكتب 10 أحرف على الأقل، وتجنب تضمين كلمات المرور.", "Use at least 10 characters and leave out passwords."))
                    if invalidFields.contains("message") {
                        Text(l10n.t("اكتب رسالة من 10 أحرف على الأقل.", "Write at least 10 characters."))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BasirPalette.danger)
                    }
                }
                Toggle(isOn: $includeDeviceInfo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("تضمين إصدار التطبيق ونوع الجهاز", "Include app version and device type"))
                        Text(deviceSummary)
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                    }
                }
                .tint(BasirPalette.accent)
            }
            .glassSurface()

            Text(l10n.t("نستخدم بياناتك للرد عليك فقط.", "We use your details only to reply to you."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)

            if isSending {
                ProgressView(l10n.t("جارٍ الإرسال…", "Sending…"))
                    .frame(maxWidth: .infinity)
            } else {
                PrimaryActionButton(title: l10n.t("إرسال الرسالة", "Send message"), systemImage: "paperplane.fill") {
                    Task { await send() }
                }
            }
        }
    }

    private func field(_ title: String, key: String, text: Binding<String>,
                       content: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextField(title, text: text)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .environment(\.layoutDirection, keyboard == .emailAddress ? .leftToRight : l10n.layoutDirection)
                .padding(BasirSpacing.m)
                .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(invalidFields.contains(key) ? BasirPalette.danger : BasirPalette.stroke,
                                lineWidth: invalidFields.contains(key) ? 2 : 1)
                }
                .accessibilityValue(invalidFields.contains(key) ? l10n.t("يحتاج إلى تصحيح", "Needs correction") : "")
            if invalidFields.contains(key) {
                Text(fieldError(key))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BasirPalette.danger)
            }
        }
    }

    private func fieldError(_ key: String) -> String {
        switch key {
        case "name": return l10n.t("اكتب اسمك (حرفان على الأقل).", "Enter your name (at least 2 characters).")
        case "email": return l10n.t("أدخل عنوان بريد إلكتروني صحيحًا، مثل name@example.com.", "Enter a valid email address, such as name@example.com.")
        default: return l10n.t("راجع هذا الحقل.", "Check this field.")
        }
    }

    private func successCard(_ reference: String) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(BasirPalette.success)
                .accessibilityHidden(true)
            Text(l10n.t("أُرسلت رسالتك", "Message sent"))
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedStatus)
            Text(l10n.t("شكرًا لتواصلك. سيطّلع فريق بصير على رسالتك ويرد على بريدك الإلكتروني.",
                        "Thanks for getting in touch. The Basir team will review your message and reply by email."))
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(l10n.t("الرقم المرجعي: \(reference)", "Reference number: \(reference)"))
                .font(.headline)
                .textSelection(.enabled)
            SecondaryActionButton(title: l10n.t("تم", "Done"), systemImage: "checkmark") { dismiss() }
        }
        .glassSurface(accent: BasirPalette.success)
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var deviceSummary: String {
        var system = utsname()
        uname(&system)
        let model = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return "Basir \(appVersion) • \(model) • iOS \(UIDevice.current.systemVersion)"
    }

    private func send() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var invalid: Set<String> = []
        if trimmedName.count < 2 { invalid.insert("name") }
        if trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#, options: .regularExpression) == nil {
            invalid.insert("email")
        }
        if trimmedMessage.count < 10 { invalid.insert("message") }
        invalidFields = invalid
        guard invalid.isEmpty else {
            showError(l10n.t("راجع الاسم والبريد الإلكتروني ونص الرسالة، ثم أعد الإرسال.", "Check your name, email address, and message, then send again."))
            return
        }
        guard let url = BasirPublicLinks.endpoint("/api/public/contact") else {
            showError(l10n.t("تعذر الوصول إلى خادم بصير.", "The Basir server could not be reached."))
            return
        }
        isSending = true
        defer { isSending = false }
        let payload: [String: String] = [
            "name": trimmedName,
            "email": trimmedEmail,
            "category": category,
            "subject": subject.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": trimmedMessage,
            "language": l10n.language.rawValue,
            "source": "app",
            "app_version": includeDeviceInfo ? appVersion : "",
            "device": includeDeviceInfo ? deviceSummary : ""
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            switch status {
            case 200 where json?["ok"] as? Bool == true:
                reference = json?["reference"] as? String ?? "—"
                errorMessage = nil
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("وصلت رسالتك. الرقم المرجعي \(reference ?? "")",
                                                      "Your message was sent. Reference \(reference ?? "")"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focusedStatus = true }
            case 422:
                invalidFields = Set((json?["fields"] as? [String]) ?? [])
                showError(l10n.t("راجع الاسم والبريد الإلكتروني ونص الرسالة، ثم أعد الإرسال.", "Check your name, email address, and message, then send again."))
            case 429:
                showError(l10n.t("بلغت الحد المؤقت لإرسال الرسائل. حاول مجددًا بعد بضع دقائق.",
                                 "You’ve reached the temporary message limit. Try again in a few minutes."))
            default:
                showError(l10n.t("تعذر إرسال الرسالة الآن. حاول مرة أخرى بعد قليل.",
                                 "The message could not be sent right now. Please try again shortly."))
            }
        } catch {
            showError(l10n.t("لا يوجد اتصال بالإنترنت. تحقق من الشبكة ثم حاول مرة أخرى.",
                             "There is no internet connection. Check your network and try again."))
        }
    }

    private func showError(_ text: String) {
        errorMessage = text
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focusedStatus = true }
    }
}
