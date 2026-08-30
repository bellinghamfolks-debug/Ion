import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let fallbackAppGroup = "group.com.basir.convert.ios"
    private let maximumFileBytes: Int64 = 200 * 1024 * 1024
    private var isArabic: Bool { Locale.preferredLanguages.first?.hasPrefix("ar") == true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = text("جارٍ استلام العناصر…", "Receiving items…")
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -20)
        ])
        persistAttachments()
    }

    private func persistAttachments() {
        guard let root = sharedContainerURL() else {
            finish(
                message: text(
                    "لم تُمنح بصير صلاحية استقبال المشاركات عند توقيع التطبيق. أعد توقيع النسخة مع الاحتفاظ بصلاحية App Groups.",
                    "Basir was not granted shared-container access during signing. Re-sign the app while preserving its App Groups entitlement."
                ),
                error: true
            )
            return
        }
        let inbox = root.appendingPathComponent("SharedIncoming", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: inbox.path
            )
        } catch {
            finish(message: text("تعذر تجهيز مجلد الاستلام.", "Could not prepare the receiving folder."), error: true)
            return
        }

        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        guard !providers.isEmpty else {
            finish(message: text("لم يصل أي ملف أو صورة.", "No file or image was received."), error: true)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var saved = 0
        var tooLarge = 0
        for provider in providers {
            guard let identifier = preferredIdentifier(for: provider) else { continue }
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, _ in
                guard let self else { group.leave(); return }
                if let url {
                    let result = self.copy(url, provider: provider, typeIdentifier: identifier, to: inbox)
                    lock.lock()
                    if result == .saved { saved += 1 }
                    if result == .tooLarge { tooLarge += 1 }
                    lock.unlock()
                    group.leave()
                    return
                }
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, !data.isEmpty else { return }
                    if Int64(data.count) > self.maximumFileBytes {
                        lock.lock(); tooLarge += 1; lock.unlock()
                        return
                    }
                    do {
                        let destination = self.destinationURL(
                            sourceName: provider.suggestedName,
                            typeIdentifier: identifier,
                            inbox: inbox
                        )
                        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        lock.lock(); saved += 1; lock.unlock()
                    } catch { }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if saved > 0 {
                let message = self.text(
                    "تم إرسال \(saved) من العناصر إلى بصير. افتح التطبيق للمتابعة.",
                    "Sent \(saved) item(s) to Basir. Open the app to continue."
                )
                self.finish(message: message, error: false)
            } else if tooLarge > 0 {
                self.finish(
                    message: self.text("حجم العنصر أكبر من 200 ميجابايت.", "The item is larger than 200 MB."),
                    error: true
                )
            } else {
                self.finish(
                    message: self.text("تعذر استلام العناصر المرسلة.", "The shared items could not be received."),
                    error: true
                )
            }
        }
    }

    private enum CopyResult { case saved, tooLarge, failed }

    private func copy(
        _ source: URL,
        provider: NSItemProvider,
        typeIdentifier: String,
        to inbox: URL
    ) -> CopyResult {
        do {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile != false else { return .failed }
            guard Int64(values.fileSize ?? 0) <= maximumFileBytes else { return .tooLarge }
            let preferredName = provider.suggestedName?.isEmpty == false
                ? provider.suggestedName : source.lastPathComponent
            let destination = destinationURL(
                sourceName: preferredName,
                typeIdentifier: typeIdentifier,
                inbox: inbox
            )
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            return .saved
        } catch {
            return .failed
        }
    }

    private func destinationURL(sourceName: String?, typeIdentifier: String, inbox: URL) -> URL {
        var name = sanitize(sourceName ?? "")
        let typeExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin"
        if name.isEmpty { name = text("مستند", "Document") }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            name += ".\(typeExtension)"
        }
        return inbox.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    private func preferredIdentifier(for provider: NSItemProvider) -> String? {
        let identifiers = [
            UTType.pdf.identifier,
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.doc",
            "org.openxmlformats.presentationml.presentation",
            "com.microsoft.powerpoint.ppt",
            UTType.image.identifier,
            UTType.fileURL.identifier,
            UTType.data.identifier
        ]
        return identifiers.first { provider.hasItemConformingToTypeIdentifier($0) }
    }

    private func sharedContainerURL() -> URL? {
        var identifiers = runtimeApplicationGroups()
        identifiers.append(fallbackAppGroup)
        var visited = Set<String>()
        for identifier in identifiers where visited.insert(identifier).inserted {
            if let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                return url
            }
        }
        return nil
    }

    private func runtimeApplicationGroups() -> [String] {
        // Xcode 26 no longer exposes SecTask entitlement inspection to Swift.
        // The extension already falls back to its declared App Group identifier.
        return []
    }

    private func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:\n\r\t\0")
        let components = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        return String(components.joined(separator: "-").prefix(140))
    }

    private func text(_ arabic: String, _ english: String) -> String {
        isArabic ? arabic : english
    }

    private func finish(message: String, error: Bool) {
        spinner.stopAnimating()
        statusLabel.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 3.2 : 1.4)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

