#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()


def read(rel: str) -> str:
    return (root / rel).read_text(encoding='utf-8')


def write(rel: str, text: str) -> None:
    (root / rel).write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# Restore audio inputs and the preserve-symbols option in the shared model.
rel = 'BasirConvert/Models/AppModels.swift'
s = read(rel)
s = replace_once(s,
'''    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]

    static let conversionExtensions = Set(["pdf", "pptx", "ppt"])
        .union(imageExtensions)
''',
'''    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]
    static let audioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "flac", "ogg", "opus", "caf", "aif", "aiff", "mp4", "mov"
    ]

    static let conversionExtensions = Set(["pdf", "pptx", "ppt"])
        .union(imageExtensions)
        .union(audioExtensions)
''', 'audio extensions')
s = replace_once(s,
'''    let embedVisuals: Bool
    let includeMath: Bool
    let interfaceLanguage: InterfaceLanguage
''',
'''    let embedVisuals: Bool
    let includeMath: Bool
    let preserveSymbols: Bool
    let interfaceLanguage: InterfaceLanguage
''', 'conversion option field')
s = replace_once(s,
'''        embedVisuals: Bool,
        includeMath: Bool,
        interfaceLanguage: InterfaceLanguage,
''',
'''        embedVisuals: Bool,
        includeMath: Bool,
        preserveSymbols: Bool = true,
        interfaceLanguage: InterfaceLanguage,
''', 'conversion option init arg')
s = replace_once(s,
'''        self.embedVisuals = embedVisuals
        self.includeMath = includeMath
        self.interfaceLanguage = interfaceLanguage
''',
'''        self.embedVisuals = embedVisuals
        self.includeMath = includeMath
        self.preserveSymbols = preserveSymbols
        self.interfaceLanguage = interfaceLanguage
''', 'conversion option init assign')
s = replace_once(s,
'''        if effectiveEmbedVisuals { value += "|visuals" }
        if includeMath { value += "|math" }
        value += "|pdf:\(pdfQuality.rawValue)"
''',
'''        if effectiveEmbedVisuals { value += "|visuals" }
        if includeMath { value += "|math" }
        if !preserveSymbols { value += "|symbols_off" }
        value += "|pdf:\(pdfQuality.rawValue)"
''', 'encoded symbols flag')
s = replace_once(s,
'''    static var basirSupportedDocuments: [UTType] {
        [.pdf, .basirPPTX, .basirPPT, .basirDOCX, .basirDOC, .image]
    }
''',
'''    static var basirSupportedDocuments: [UTType] {
        [.pdf, .basirPPTX, .basirPPT, .basirDOCX, .basirDOC, .image, .audio, .movie]
    }
''', 'supported UTTypes')
write(rel, s)

# Persist the symbol toggle. Default ON to preserve older Basir behaviour.
rel = 'BasirConvert/Models/SettingsStore.swift'
s = read(rel)
s = replace_once(s,
'''        static let includeMath = "convert_include_math"
        static let targetLanguage = "translate_target_language"
''',
'''        static let includeMath = "convert_include_math"
        static let preserveSymbols = "convert_preserve_symbols"
        static let targetLanguage = "translate_target_language"
''', 'settings key')
s = replace_once(s,
'''    @Published var includeMath: Bool
    @Published var targetLanguageCode: String
''',
'''    @Published var includeMath: Bool
    @Published var preserveSymbols: Bool
    @Published var targetLanguageCode: String
''', 'settings property')
s = replace_once(s,
'''        includeMath = defaults.bool(forKey: Key.includeMath)
        targetLanguageCode = defaults.string(forKey: Key.targetLanguage) ?? "en"
''',
'''        includeMath = defaults.bool(forKey: Key.includeMath)
        preserveSymbols = defaults.object(forKey: Key.preserveSymbols) == nil
            ? true : defaults.bool(forKey: Key.preserveSymbols)
        targetLanguageCode = defaults.string(forKey: Key.targetLanguage) ?? "en"
''', 'settings init')
s = replace_once(s,
'''        defaults.set(includeMath, forKey: Key.includeMath)
        defaults.set(targetLanguageCode, forKey: Key.targetLanguage)
''',
'''        defaults.set(includeMath, forKey: Key.includeMath)
        defaults.set(preserveSymbols, forKey: Key.preserveSymbols)
        defaults.set(targetLanguageCode, forKey: Key.targetLanguage)
''', 'settings save')
write(rel, s)

# Restore visible symbol controls and audio selection.
rel = 'BasirConvert/Views/TaskComposerView.swift'
s = read(rel)
s = replace_once(s,
'''        isTranslation
            ? [.pdf, .basirDOCX, .basirDOC, .basirPPTX, .basirPPT, .image]
            : [.pdf, .basirPPTX, .basirPPT, .image]
''',
'''        isTranslation
            ? [.pdf, .basirDOCX, .basirDOC, .basirPPTX, .basirPPT, .image]
            : [.pdf, .basirPPTX, .basirPPT, .image, .audio, .movie]
''', 'composer content types')
s = replace_once(s,
'''            embedVisuals: settings.embedVisuals,
            includeMath: settings.includeMath,
            interfaceLanguage: l10n.language,
''',
'''            embedVisuals: settings.embedVisuals,
            includeMath: settings.includeMath,
            preserveSymbols: settings.preserveSymbols,
            interfaceLanguage: l10n.language,
''', 'composer options')
s = replace_once(s,
'''            Toggle(l10n.t("شرح المعادلات الرياضية", "Explain mathematical equations"), isOn: Binding(
                get: { settings.includeMath }, set: { settings.includeMath = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            VStack(alignment: .leading, spacing: 7) {
''',
'''            Toggle(l10n.t("شرح المعادلات الرياضية", "Explain mathematical equations"), isOn: Binding(
                get: { settings.includeMath }, set: { settings.includeMath = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            Toggle(l10n.t("الحفاظ على الرموز ومعانيها", "Preserve symbols and their meaning"), isOn: Binding(
                get: { settings.preserveSymbols }, set: { settings.preserveSymbols = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            Text(l10n.t(
                "يشمل علامات الصح والخطأ ومربعات الاختيار والتحذير والأسهم والرموز المشابهة مثل ✓ ✗ ☑ ☐ ⚠.",
                "Includes check/cross marks, checkboxes, warnings, arrows, and similar symbols such as ✓ ✗ ☑ ☐ ⚠."
            ))
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            if !isTranslation {
                Text(l10n.t(
                    "يدعم بصير أيضًا التسجيلات الصوتية من تطبيق الملفات ويحوّلها إلى تفريغ مكتوب داخل ملف Word، بما في ذلك التسجيلات الطويلة.",
                    "Basir also accepts audio recordings from Files and creates a written Word transcript, including long recordings."
                ))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 7) {
''', 'symbols UI')
s = s.replace('"اختيار ملف أو صورة", "Choose a file or image"', '"اختيار ملف أو صورة أو تسجيل صوتي", "Choose a file, image, or audio recording"')
s = s.replace('''"اختر من تطبيق الملفات أو مكتبة الصور أو الكاميرا أو ماسح المستندات أو الحافظة.",
                                "Choose from Files, Photos, Camera, the document scanner, or the clipboard."''',
'''"اختر من تطبيق الملفات، بما في ذلك التسجيلات الصوتية، أو من الصور أو الكاميرا أو ماسح المستندات أو الحافظة.",
                                "Choose from Files, including audio recordings, or from Photos, Camera, the document scanner, or the clipboard."''')
write(rel, s)

# Raise local source limit and validate common recording containers.
rel = 'BasirConvert/Services/FileAccess.swift'
s = read(rel)
s = replace_once(s, 'static let maximumSourceBytes: Int64 = 200 * 1024 * 1024',
                    'static let maximumSourceBytes: Int64 = 400 * 1024 * 1024', 'source size limit')
s = replace_once(s,
'''        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
''',
'''        case "jpg", "jpeg": return "image/jpeg"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "caf": return "audio/x-caf"
        case "aif", "aiff": return "audio/aiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
''', 'audio mime types')
s = replace_once(s,
'''        case "bmp":
            valid = header.starts(with: [0x42, 0x4D])
        default:
            valid = false
''',
'''        case "bmp":
            valid = header.starts(with: [0x42, 0x4D])
        case "m4a", "mp4", "mov":
            valid = header.count >= 12
                && String(data: header.dropFirst(4).prefix(4), encoding: .ascii) == "ftyp"
        case "mp3":
            valid = header.starts(with: Data("ID3".utf8))
                || (header.count >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0)
        case "wav":
            valid = header.count >= 12
                && String(data: header.prefix(4), encoding: .ascii) == "RIFF"
                && String(data: header.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE"
        case "aac":
            valid = header.count >= 2 && header[0] == 0xFF && (header[1] & 0xF0) == 0xF0
        case "flac":
            valid = header.starts(with: Data("fLaC".utf8))
        case "ogg", "opus":
            valid = header.starts(with: Data("OggS".utf8))
        case "caf":
            valid = header.starts(with: Data("caff".utf8))
        case "aif", "aiff":
            valid = header.count >= 12
                && String(data: header.prefix(4), encoding: .ascii) == "FORM"
                && ["AIFF", "AIFC"].contains(String(data: header.dropFirst(8).prefix(4), encoding: .ascii) ?? "")
        default:
            valid = false
''', 'audio signatures')
write(rel, s)

# Register audio/movie as content iOS may open directly in Basir.
rel = 'BasirConvert/Supporting/Info.plist'
s = read(rel)
s = replace_once(s,
'''                <string>public.image</string>
            </array>
''',
'''                <string>public.image</string>
                <string>public.audio</string>
                <string>public.movie</string>
            </array>
''', 'Info.plist document types')
write(rel, s)

# Make Quick Look preview explicitly navigable and shareable for VoiceOver.
rel = 'BasirConvert/Views/ImportControllers.swift'
s = read(rel)
pattern = re.compile(r'''struct QuickLookPreview: UIViewControllerRepresentable \{.*?\n\}\n\nstruct ExportDocumentPicker''', re.S)
match = pattern.search(s)
if not match:
    raise SystemExit('QuickLookPreview block not found')
replacement = '''struct QuickLookPreview: UIViewControllerRepresentable {
    @Environment(\\.dismiss) private var dismiss
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onClose: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        context.coordinator.previewController = preview
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.closePreview)
        )
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: context.coordinator,
            action: #selector(Coordinator.sharePreview)
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.url = url
        context.coordinator.previewController?.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        let onClose: () -> Void
        weak var previewController: QLPreviewController?

        init(url: URL, onClose: @escaping () -> Void) {
            self.url = url
            self.onClose = onClose
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        @objc func closePreview() { onClose() }

        @objc func sharePreview() {
            guard let previewController else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = share.popoverPresentationController {
                popover.sourceView = previewController.view
                popover.sourceRect = CGRect(x: previewController.view.bounds.midX,
                                            y: previewController.view.bounds.minY + 44,
                                            width: 1, height: 1)
            }
            previewController.present(share, animated: true)
        }
    }
}

struct ExportDocumentPicker'''
s = s[:match.start()] + replacement + s[match.end():]
write(rel, s)

# Remove redundant Open in Word/Pages. Share already exposes those apps when installed.
rel = 'BasirConvert/Views/JobView.swift'
s = read(rel)
s = s.replace('    @State private var openURL: URL?\n', '')
s = s.replace('        .sheet(item: bindingURL($openURL)) { OpenInApplicationView(url: $0.url) }\n', '')
s = replace_once(s,
'''            HStack {
                smallAction(l10n.t("مشاركة", "Share"), "square.and.arrow.up") { shareURL = url }
                smallAction(l10n.t("فتح في Word أو Pages", "Open in Word or Pages"), "arrow.up.forward.app") { openURL = url }
            }
''',
'''            smallAction(l10n.t("مشاركة", "Share"), "square.and.arrow.up") { shareURL = url }
''', 'remove Open in Word/Pages')
write(rel, s)

# Ensure local notifications are visible in the foreground.
rel = 'BasirConvert/App/BasirConvertApp.swift'
s = read(rel)
if 'import UserNotifications' not in s:
    s = s.replace('import UIKit\n', 'import UIKit\nimport UserNotifications\n', 1)
s = replace_once(s,
'''final class BasirAppDelegate: NSObject, UIApplicationDelegate {
    func application(
''',
'''final class BasirAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func application(
''', 'notification delegate')
write(rel, s)

# Throttle progress notifications to 25/50/75%, then send completion/failure.
rel = 'BasirConvert/Services/OperationFeedback.swift'
s = read(rel)
s = replace_once(s,
'''    static func notifyCompletion(title: String, body: String, jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
''',
'''    private static var progressBuckets: [UUID: Int] = [:]

    static func notifyProgress(title: String, body: String, jobID: UUID, current: Int, total: Int) {
        guard total > 1, current > 0, current < total else { return }
        let percentage = Int((Double(current) / Double(total) * 100).rounded(.down))
        let bucket = percentage >= 75 ? 75 : (percentage >= 50 ? 50 : (percentage >= 25 ? 25 : 0))
        guard bucket > 0, progressBuckets[jobID, default: 0] < bucket else { return }
        progressBuckets[jobID] = bucket
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-progress-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyCompletion(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["basir-progress-\(jobID.uuidString)"])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyFailure(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["basir-progress-\(jobID.uuidString)"])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-failed-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
''', 'notification methods')
write(rel, s)

rel = 'BasirConvert/ViewModels/AppViewModel.swift'
s = read(rel)
s = replace_once(s,
'''        if update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
''',
'''        if update.total > 0, settings?.notificationsEnabled == true, let l10n {
            OperationFeedback.notifyProgress(
                title: l10n.t("تقدم مهمة بصير", "Basir task progress"),
                body: l10n.t("تمت معالجة \(update.current) من \(update.total).",
                             "Processed \(update.current) of \(update.total)."),
                jobID: jobID,
                current: update.current,
                total: update.total
            )
        }
        if update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
''', 'progress notification hook')
s = replace_once(s,
'''        OperationFeedback.play(.failed, theme: settings?.soundTheme ?? .gentle)
        completeCurrentTaskAndContinue(allowNext: false)
''',
'''        OperationFeedback.play(.failed, theme: settings?.soundTheme ?? .gentle)
        if settings?.notificationsEnabled == true,
           !Self.isNetworkWaitError(error),
           let l10n {
            OperationFeedback.notifyFailure(
                title: l10n.t("تعذرت مهمة بصير", "Basir task failed"),
                body: Self.localized(error, l10n: l10n),
                jobID: jobID
            )
        }
        completeCurrentTaskAndContinue(allowNext: false)
''', 'failure notification hook')
s = s.replace('''"توجد صيغة غير مدعومة. أرسل PDF أو Word أو PowerPoint أو صورة مدعومة.",
                "One of the items is unsupported. Send PDF, Word, PowerPoint, or a supported image."''',
'''"توجد صيغة غير مدعومة. أرسل PDF أو Word أو PowerPoint أو صورة أو تسجيلًا صوتيًا مدعومًا.",
                "One of the items is unsupported. Send PDF, Word, PowerPoint, a supported image, or an audio recording."''')
write(rel, s)

# Build gate: never publish a future IPA if one of these restored features disappears again.
checks = {
    'BasirConvert/Models/AppModels.swift': ['audioExtensions', 'preserveSymbols', 'symbols_off'],
    'BasirConvert/Views/TaskComposerView.swift': ['الحفاظ على الرموز ومعانيها', '.audio, .movie'],
    'BasirConvert/Services/FileAccess.swift': ['400 * 1024 * 1024', 'case "m4a"', 'case "mp3"'],
    'BasirConvert/Views/ImportControllers.swift': ['closePreview', 'sharePreview'],
    'BasirConvert/Services/OperationFeedback.swift': ['notifyProgress', 'notifyFailure'],
}
for rel, needles in checks.items():
    text = read(rel)
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'feature gate failed: {needle!r} missing from {rel}')
for path in (root / 'BasirConvert').rglob('*.swift'):
    text = path.read_text(encoding='utf-8')
    if 'فتح في Word أو Pages' in text or 'Open in Word or Pages' in text:
        raise SystemExit(f'feature gate failed: redundant Open in Word/Pages remains in {path}')

print('BASIR_FEATURESET=ARABIC_SYMBOLS_AUDIO_NOTIFICATIONS_PREVIEW_R3')
