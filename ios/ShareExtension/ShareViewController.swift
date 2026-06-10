import UIKit
import UniformTypeIdentifiers

/// Accessible, purpose-built share sheet for sending one image, PDF, or text
/// item to Basir. The previous SLComposeServiceViewController exposed an
/// unrelated composer and depended on a missing storyboard. This controller
/// keeps the action explicit and gives VoiceOver a predictable flow.
final class ShareViewController: UIViewController {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let continueButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var isCancelled = false

    private static let maximumSharedFileBytes: Int64 = 256 * 1_024 * 1_024
    private static let maximumSharedTextBytes = 2 * 1_024 * 1_024

    private var isArabic: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ar") == true
    }

    private var inputKind: InputKind? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        let providers = items.flatMap { $0.attachments ?? [] }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            return .image
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
            return .pdf
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            return .text
        }
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureLayout()
        updateForInput()
    }

    private func configureAppearance() {
        view.backgroundColor = .systemGroupedBackground
        view.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight

        iconView.image = UIImage(systemName: "doc.text.magnifyingglass")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        iconView.tintColor = Self.brandColor
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = isArabic ? .right : .left
        titleLabel.text = localized("فتح المحتوى في بصير", "Open content in Basir")
        titleLabel.accessibilityTraits = .header

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = isArabic ? .right : .left

        statusLabel.font = .preferredFont(forTextStyle: .callout)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = isArabic ? .right : .left
        statusLabel.isHidden = true

        var primary = UIButton.Configuration.filled()
        primary.title = localized("متابعة في بصير", "Continue in Basir")
        primary.image = UIImage(systemName: "arrow.up.forward.app.fill")
        primary.imagePadding = 8
        primary.cornerStyle = .large
        primary.baseBackgroundColor = Self.brandColor
        primary.baseForegroundColor = .white
        continueButton.configuration = primary
        continueButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        continueButton.titleLabel?.adjustsFontForContentSizeCategory = true
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.accessibilityHint = localized(
            "يجهز المحتوى ويفتح الأداة المناسبة داخل تطبيق بصير.",
            "Prepares the content and opens the appropriate tool in Basir."
        )

        var secondary = UIButton.Configuration.gray()
        secondary.title = localized("إلغاء", "Cancel")
        secondary.cornerStyle = .large
        cancelButton.configuration = secondary
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true
        activityIndicator.accessibilityLabel = localized("جاري تجهيز المحتوى", "Preparing content")
    }

    private func configureLayout() {
        let header = UIStackView(arrangedSubviews: [iconView, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 14

        let statusRow = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 10

        let stack = UIStackView(arrangedSubviews: [header, messageLabel, statusRow, continueButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 58),
            iconView.heightAnchor.constraint(equalToConstant: 58),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func updateForInput() {
        switch inputKind {
        case .image:
            messageLabel.text = localized(
                "سيُفتح وصف الصور داخل بصير. لن تبدأ المعالجة حتى يفتح التطبيق وتراجع الطلب.",
                "Basir will open image description. Processing starts only after the app opens and you review the request."
            )
        case .pdf:
            messageLabel.text = localized(
                "سيُفتح تحويل المستندات داخل بصير مع ملف PDF المحدد.",
                "Basir will open document conversion with the selected PDF."
            )
        case .text:
            messageLabel.text = localized(
                "سيُفتح النص داخل بصير لتتمكن من سؤاله أو معالجته.",
                "The text will open in Basir so you can ask about it or process it."
            )
        case nil:
            messageLabel.text = localized(
                "هذا النوع غير مدعوم. شارك صورة واحدة أو ملف PDF واحدًا أو نصًا.",
                "This item is not supported. Share one image, one PDF, or text."
            )
            continueButton.isEnabled = false
        }
    }

    @objc private func continueTapped() {
        guard inputKind != nil else { return }
        isCancelled = false
        setLoading(true)
        processFirstSupportedItem()
    }

    @objc private func cancelTapped() {
        isCancelled = true
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.basir.ai.share",
            code: NSUserCancelledError
        ))
    }

    private func setLoading(_ loading: Bool) {
        continueButton.isEnabled = !loading
        // Cancellation must remain available while a provider is loading
        // or a large file is being copied.
        cancelButton.isEnabled = true
        statusLabel.isHidden = !loading
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = localized("جاري تجهيز المحتوى…", "Preparing content…")
        loading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        if loading {
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
        }
    }

    private func processFirstSupportedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            showFailure()
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] fileURL, _ in
                guard let self, let fileURL else { self?.showFailure(); return }
                let suggestedExtension = provider.suggestedName
                    .map { URL(fileURLWithPath: $0).pathExtension } ?? ""
                let ext = Self.safeImageExtension(fileURL.pathExtension)
                    ?? Self.safeImageExtension(suggestedExtension)
                    ?? "jpg"
                self.persistAndOpen(fileURL: fileURL, ext: ext, task: "describe_image")
            }
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] fileURL, _ in
                guard let self, let fileURL else { self?.showFailure(); return }
                self.persistAndOpen(fileURL: fileURL, ext: "pdf", task: "convert")
            }
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                guard let self else { return }
                let text: String?
                if let value = item as? String {
                    text = value
                } else if let url = item as? URL {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    text = size <= Self.maximumSharedTextBytes
                        ? try? String(contentsOf: url, encoding: .utf8)
                        : nil
                } else {
                    text = nil
                }
                guard let text,
                      let data = text.data(using: .utf8),
                      data.count <= Self.maximumSharedTextBytes else {
                    self.showFailure()
                    return
                }
                self.persistAndOpen(data: data, ext: "txt", task: "ask")
            }
            return
        }

        showFailure()
    }

    private static func safeImageExtension(_ raw: String) -> String? {
        let ext = raw.lowercased()
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp"].contains(ext)
            ? ext : nil
    }

    private func persistAndOpen(fileURL: URL, ext: String, task: String) {
        guard !isCancelled,
              let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              Int64(values.fileSize ?? 0) > 0,
              Int64(values.fileSize ?? 0) <= Self.maximumSharedFileBytes,
              let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.basir.shared") else {
            showFailure(); return
        }
        let destination = container.appendingPathComponent(uniqueName(ext: ext))
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: fileURL, to: destination)
            openMainApp(task: task, filename: destination.lastPathComponent)
        } catch {
            showFailure()
        }
    }

    private func persistAndOpen(data: Data, ext: String, task: String) {
        guard !isCancelled,
              !data.isEmpty,
              Int64(data.count) <= Self.maximumSharedFileBytes,
              let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.basir.shared") else {
            showFailure(); return
        }
        let destination = container.appendingPathComponent(uniqueName(ext: ext))
        do {
            try data.write(to: destination, options: [.atomic])
            openMainApp(task: task, filename: destination.lastPathComponent)
        } catch {
            showFailure()
        }
    }

    private func uniqueName(ext: String) -> String {
        "share-\(UUID().uuidString).\(ext)"
    }

    private func openMainApp(task: String, filename: String) {
        guard !isCancelled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openMainAppOnMain(task: task, filename: filename)
        }
    }

    private func openMainAppOnMain(task: String, filename: String) {
        guard !isCancelled else { return }
        var components = URLComponents()
        components.scheme = "basir"
        components.host = "share"
        components.path = "/\(task)"
        components.queryItems = [URLQueryItem(name: "file", value: filename)]
        guard let url = components.url else { showFailure(); return }
        extensionContext?.open(url) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self.showFailure()
            }
        }
    }

    private func showFailure() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.setLoading(false)
            self.statusLabel.isHidden = false
            self.statusLabel.textColor = .systemRed
            self.statusLabel.text = self.localized(
                "تعذر تجهيز المحتوى. افتح بصير وحاول اختيار الملف من داخله.",
                "The content could not be prepared. Open Basir and choose the file from inside the app."
            )
            self.continueButton.isEnabled = true
            self.cancelButton.isEnabled = true
            UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
        }
    }

    private func localized(_ arabic: String, _ english: String) -> String {
        isArabic ? arabic : english
    }

    private static let brandColor = UIColor(red: 0.05, green: 0.31, blue: 0.67, alpha: 1)

    private enum InputKind {
        case image, pdf, text
    }
}
