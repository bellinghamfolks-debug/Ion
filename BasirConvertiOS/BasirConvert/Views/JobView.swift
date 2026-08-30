import SwiftUI

struct JobView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var library: OutputLibraryStore
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var showCancelConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BasirHeroCard(title: navigationTitle,
                                      subtitle: statusSubtitle,
                                      systemImage: statusIcon)
                        statusCard
                        switch viewModel.status {
                        case .running:
                            runningContent
                        case .queued, .waitingForNetwork:
                            waitingContent
                        case .paused:
                            pausedContent
                        case .completed:
                            completedContent(partial: false)
                        case .partial:
                            completedContent(partial: true)
                        case .failed, .cancelled:
                            failureContent
                        case .idle:
                            EmptyView()
                        }
                    }
                    .appScreenContent(bottomPadding: 28)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
            }
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(viewModel.status == .running)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { NetworkStatusPill() }
                if viewModel.status != .running {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(l10n.t("إغلاق", "Close")) { viewModel.dismissJob() }
                            .fontWeight(.semibold)
                            .foregroundStyle(BasirPalette.cyan)
                    }
                }
            }
        }
        .sheet(item: bindingURL($previewURL)) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        .sheet(item: bindingURL($shareURL)) { ActivityShareView(urls: [$0.url]) }
        .sheet(item: bindingURL($exportURL)) { ExportDocumentPicker(urls: [$0.url]) }
        .confirmationDialog(
            l10n.t("إلغاء هذه المهمة؟", "Cancel this task?"),
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(l10n.t("إلغاء المهمة", "Cancel task"), role: .destructive) {
                OperationFeedback.warningImpact()
                viewModel.cancel()
            }
            Button(l10n.t("متابعة المعالجة", "Keep processing"), role: .cancel) { }
        } message: {
            Text(l10n.t("سيتوقف العمل الجاري، وسيبقى الملف المصدر محفوظًا لإعادة المحاولة.",
                        "Current processing will stop. The source file will be kept for retry."))
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: statusIcon).font(.title).foregroundStyle(statusColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(navigationTitle).font(.headline)
                Text(viewModel.sourceName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BasirPalette.secondaryText)
                    .lineLimit(3)
                if let metadata = viewModel.selectedJob?.sourceMetadata {
                    Text(metadataSummary(metadata))
                        .font(.caption)
                        .foregroundStyle(BasirPalette.tertiaryText)
                }
                if let job = viewModel.selectedJob {
                    Text(modelSummary(job))
                        .font(.caption)
                        .foregroundStyle(BasirPalette.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .glassSurface(accent: statusColor)
        .accessibilityElement(children: .combine)
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionTitle(title: viewModel.progress.stage.label(l10n), systemImage: "hourglass")
            if let fraction = viewModel.progress.fraction {
                ProgressView(value: fraction) {
                    Text(l10n.t("التقدم", "Progress"))
                } currentValueLabel: {
                    Text("\(viewModel.progress.current) / \(viewModel.progress.total)")
                }
                .tint(BasirPalette.cyan)
            } else { ProgressView().tint(BasirPalette.cyan).frame(maxWidth: .infinity) }
            if let detail = viewModel.progress.detail, !detail.isEmpty {
                Text(localizedDetail(detail)).font(.headline).foregroundStyle(.white)
            }
            if viewModel.progress.totalBytes > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: viewModel.progress.transferredBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: viewModel.progress.totalBytes, countStyle: .file))")
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    metric(l10n.t("الوقت المنقضي", "Elapsed"), format(viewModel.elapsedTime))
                    if let remaining = viewModel.estimatedRemaining {
                        metric(l10n.t("المتبقي تقديريًا", "Estimated left"), format(remaining))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if viewModel.progress.succeeded > 0 || viewModel.progress.failed > 0 || (viewModel.progress.skipped ?? 0) > 0 {
                Text(l10n.t(
                    "أُدرجت \(viewModel.progress.succeeded) • فارغة متخطاة \(viewModel.progress.skipped ?? 0) • حفظ احتياطي \(viewModel.progress.failed)",
                    "Retained \(viewModel.progress.succeeded) • blank skipped \(viewModel.progress.skipped ?? 0) • fallback \(viewModel.progress.failed)"
                ))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            }
            HStack {
                Button { viewModel.pause() } label: {
                    Label(l10n.t("إيقاف مؤقت", "Pause"), systemImage: "pause.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                Button(role: .destructive) { showCancelConfirmation = true } label: {
                    Label(l10n.t("إلغاء", "Cancel"), systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            }
        }
        .glassSurface()
    }

    private var waitingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionTitle(title: viewModel.progress.stage.label(l10n), systemImage: "wifi.slash")
            Text(viewModel.errorMessage ?? l10n.t("ستبدأ المهمة تلقائيًا عندما يصبح الاتصال مناسبًا.",
                                                   "The task will start automatically when the connection is suitable."))
                .foregroundStyle(BasirPalette.secondaryText)
            Button { viewModel.resume() } label: {
                Label(l10n.t("المحاولة الآن", "Try now"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(BasirPalette.cyan)
        }
        .glassSurface(accent: .orange)
    }

    private var pausedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("تم حفظ تقدمك. عند الاستئناف، سيكمل بصير من آخر جزء انتهى منه.",
                        "Progress is saved. Basir will reuse completed pages when you resume."))
                .foregroundStyle(BasirPalette.secondaryText)
            PrimaryActionButton(title: l10n.t("استئناف المهمة", "Resume task"), systemImage: "play.fill") {
                viewModel.resume()
            }
            Button(role: .destructive) { showCancelConfirmation = true } label: {
                Label(l10n.t("إلغاء المهمة", "Cancel task"), systemImage: "stop.circle")
            }
            .buttonStyle(.bordered).tint(.red)
        }
        .glassSurface(accent: .orange)
    }

    private func completedContent(partial: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionTitle(
                title: partial ? l10n.t("نتيجة جزئية جاهزة", "Partial result ready")
                    : l10n.t("ملف Word جاهز", "Word file ready"),
                systemImage: partial ? "exclamationmark.circle.fill" : "checkmark.seal.fill"
            )
            if let job = viewModel.selectedJob {
                completionAccounting(job)
                if !job.failedItems.isEmpty {
                    Text(l10n.t(
                        "صفحات احتاجت حفظًا احتياطيًا بعد تعذر إعادة بنائها دلاليًا: \(pageRanges(job.failedItems))",
                        "Pages retained with a lossless fallback after semantic reconstruction failed: \(pageRanges(job.failedItems))"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    Button { viewModel.retryFailedItems() } label: {
                        Label(l10n.t("إعادة محاولة صفحات الحفظ الاحتياطي", "Retry fallback pages"), systemImage: "arrow.clockwise.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
            if let result = viewModel.resultURL {
                Text(result.lastPathComponent).font(.headline).fixedSize(horizontal: false, vertical: true)
                resultActions(result)
            }
            helpLink
        }
        .glassSurface(accent: partial ? .orange : .green)
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(viewModel.status == .failed ? Color.red.opacity(0.85) : .white)
            }
            PrimaryActionButton(title: l10n.t("إعادة المحاولة بنفس الملف", "Retry with the same file"),
                                systemImage: "arrow.clockwise") { viewModel.retry() }
            helpLink
        }
        .glassSurface(accent: viewModel.status == .failed ? .red : .orange)
    }

    private func resultActions(_ url: URL) -> some View {
        VStack(spacing: 10) {
            PrimaryActionButton(title: l10n.t("معاينة ملف Word", "Preview Word file"), systemImage: "eye.fill") {
                previewURL = url
            }
            smallAction(l10n.t("مشاركة", "Share"), "square.and.arrow.up") { shareURL = url }
            SecondaryActionButton(title: l10n.t("حفظ في تطبيق الملفات", "Save to Files"),
                                  systemImage: "folder.badge.plus") { exportURL = url }
        }
    }

    private func smallAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).tint(BasirPalette.cyan)
    }

    @ViewBuilder private var helpLink: some View {
        if let diagnostic = viewModel.diagnosticURL {
            ShareLink(item: diagnostic) {
                Label(l10n.t("مشاركة معلومات المساعدة", "Share support information"), systemImage: "lifepreserver")
            }
            .buttonStyle(.bordered).tint(BasirPalette.cyan)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(BasirPalette.tertiaryText)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var navigationTitle: String {
        switch viewModel.status {
        case .idle: return l10n.t("المهمة", "Task")
        case .queued: return l10n.t("بانتظار البدء", "Queued")
        case .waitingForNetwork: return l10n.t("بانتظار الشبكة", "Waiting for network")
        case .running: return l10n.t("جارٍ تنفيذ المهمة", "Working")
        case .paused: return l10n.t("متوقفة مؤقتًا", "Paused")
        case .partial: return l10n.t("نتيجة جزئية", "Partial result")
        case .completed: return l10n.t("اكتملت العملية", "Completed")
        case .failed: return l10n.t("لم تكتمل العملية", "Could not complete")
        case .cancelled: return l10n.t("أُلغيت المهمة", "Task cancelled")
        }
    }

    private var statusSubtitle: String {
        switch viewModel.status {
        case .running: return l10n.t("يمكنك إيقاف المهمة مؤقتًا، وسيُحفظ تقدمها تلقائيًا.",
                                     "You can pause; checkpoints will remain saved.")
        case .completed, .partial: return l10n.t("عاين النتيجة قبل فتحها أو مشاركتها.",
                                                 "Preview the result before opening or sharing it.")
        case .waitingForNetwork, .queued: return l10n.t("لن يبدأ الرفع حتى يصبح الاتصال مناسبًا.",
                                                        "Uploading will not begin until the connection is suitable.")
        case .paused: return l10n.t("الملف والتقدم محفوظان على جهازك.", "The source and progress are safely stored.")
        default: return l10n.t("يمكنك إعادة المحاولة من دون اختيار الملف مرة أخرى.",
                               "You can retry without choosing the file again.")
        }
    }

    private var statusIcon: String {
        switch viewModel.status {
        case .running: return "hourglass.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        case .paused: return "pause.circle.fill"
        case .waitingForNetwork: return "wifi.slash"
        case .queued: return "clock.fill"
        case .idle: return "doc"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .completed: return .green
        case .failed: return .red
        case .partial, .paused, .waitingForNetwork: return .orange
        default: return BasirPalette.cyan
        }
    }

    private func modelSummary(_ job: BasirJob) -> String {
        let requested = AIModelChoice(rawValue: job.options.effectivePreferredModel)?.title(l10n)
            ?? job.options.effectivePreferredModel
        if let executed = job.executedModel, !executed.isEmpty {
            return l10n.t("النموذج: \(requested) • نُفذ: \(executed)",
                          "Model: \(requested) • executed: \(executed)")
        }
        return l10n.t("النموذج المطلوب: \(requested)", "Requested model: \(requested)")
    }

    private func completionAccounting(_ job: BasirJob) -> some View {
        let sourceTotal = job.sourceMetadata?.itemCount ?? job.progress.total
        let retained = job.progress.succeeded
        let skipped = job.skippedBlankItems.count
        let accounted = retained + skipped
        let exact = sourceTotal <= 0 || accounted == sourceTotal
        return VStack(alignment: .leading, spacing: 5) {
            Text(l10n.t(
                "المصدر \(sourceTotal) • أُدرجت \(retained) • فارغة متخطاة \(skipped) • المحاسبة \(accounted)/\(sourceTotal)",
                "Source \(sourceTotal) • retained \(retained) • blank skipped \(skipped) • accounted \(accounted)/\(sourceTotal)"
            ))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(exact ? BasirPalette.secondaryText : Color.red)

            if !job.skippedBlankItems.isEmpty {
                Text(l10n.t(
                    "الصفحات الفارغة التي تم تخطيها: \(pageRanges(job.skippedBlankItems))",
                    "Blank source pages skipped: \(pageRanges(job.skippedBlankItems))"
                ))
                .font(.caption)
                .foregroundStyle(BasirPalette.tertiaryText)
            }
            if !exact {
                Label(
                    l10n.t(
                        "تحذير: أرقام الصفحات لا تتطابق مع المصدر. لا تعتمد النتيجة.",
                        "Warning: page accounting does not match the source. Do not rely on this result."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pageRanges(_ values: [Int]) -> String {
        let pages = Array(Set(values)).sorted()
        guard let first = pages.first else { return "—" }
        var ranges: [String] = []
        var start = first
        var previous = first
        for page in pages.dropFirst() {
            if page == previous + 1 {
                previous = page
                continue
            }
            ranges.append(start == previous ? "\(start)" : "\(start)–\(previous)")
            start = page
            previous = page
        }
        ranges.append(start == previous ? "\(start)" : "\(start)–\(previous)")
        return ranges.joined(separator: l10n.isArabic ? "، " : ", ")
    }

    private func metadataSummary(_ metadata: DocumentMetadata) -> String {
        var parts = [metadata.humanReadableSize]
        if let count = metadata.itemCount { parts.append(l10n.t("\(count) صفحة أو عنصر", "\(count) page(s) or item(s)")) }
        if let width = metadata.pixelWidth, let height = metadata.pixelHeight { parts.append("\(width)×\(height)") }
        return parts.joined(separator: " • ")
    }

    private func localizedDetail(_ detail: String) -> String {
        if detail.hasPrefix("page "), let number = detail.split(separator: " ").last {
            return l10n.t("الصفحة \(number)", "Page \(number)")
        }
        if detail.hasPrefix("slide "), let number = detail.split(separator: " ").last {
            return l10n.t("الشريحة \(number)", "Slide \(number)")
        }
        return detail
    }

    private func format(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "—"
    }

    private struct URLItem: Identifiable { let id = UUID(); let url: URL }
    private func bindingURL(_ source: Binding<URL?>) -> Binding<URLItem?> {
        Binding<URLItem?>(
            get: { source.wrappedValue.map { URLItem(url: $0) } },
            set: { source.wrappedValue = $0?.url }
        )
    }
}

