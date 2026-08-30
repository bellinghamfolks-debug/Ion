import SwiftUI

private enum AppTab: Hashable {
    case convert
    case translate
    case results
    case tasks
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var outputLibrary: OutputLibraryStore
    @State private var selectedTab: AppTab = .convert

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ConvertView().toolbar { commonToolbar }
            }
            .tabItem { Label(l10n.t("التحويل", "Convert"), systemImage: "doc.richtext") }
            .accessibilityHint(l10n.t("علامة تبويب 1 من 4", "Tab 1 of 4"))
            .tag(AppTab.convert)

            NavigationStack {
                TranslateView().toolbar { commonToolbar }
            }
            .tabItem { Label(l10n.t("الترجمة", "Translate"), systemImage: "character.book.closed") }
            .accessibilityHint(l10n.t("علامة تبويب 2 من 4", "Tab 2 of 4"))
            .tag(AppTab.translate)

            NavigationStack {
                ResultLibraryView().toolbar { commonToolbar }
            }
            .tabItem { Label(l10n.t("ملفاتي", "My files"), systemImage: "folder.fill") }
            .accessibilityHint(l10n.t("علامة تبويب 3 من 4", "Tab 3 of 4"))
            .tag(AppTab.results)

            NavigationStack {
                JobQueueView().toolbar { commonToolbar }
            }
            .tabItem {
                Label(l10n.t("المهام", "Tasks"), systemImage: "list.bullet.rectangle")
            }
            .accessibilityHint(l10n.t("علامة تبويب 4 من 4", "Tab 4 of 4"))
            .badge(viewModel.pendingJobCount == 0 ? 0 : viewModel.pendingJobCount)
            .tag(AppTab.tasks)
        }
        .tint(BasirPalette.cyan)
        .toolbarBackground(Color.black.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onOpenURL { viewModel.receiveExternalURL($0, l10n: l10n) }
        .onChange(of: viewModel.routedExternalBatch?.id) { _ in selectTabForRoutedDocument() }
        .onChange(of: viewModel.routedExternalDocument?.id) { _ in selectTabForRoutedDocument() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            viewModel.importSharedInbox()
            viewModel.resumeInterruptedJobsIfNeeded()
            outputLibrary.refresh()
        }
        .onAppear {
            viewModel.attach(settings: settings, l10n: l10n, outputLibrary: outputLibrary)
            selectTabForRoutedDocument()
        }
        .confirmationDialog(
            l10n.t("ماذا تريد أن تفعل بالعناصر؟", "What would you like to do with the items?"),
            isPresented: Binding(
                get: { viewModel.externalImportBatch != nil || viewModel.externalImportCandidate != nil },
                set: { if !$0 { viewModel.cancelExternalImport() } }
            ),
            titleVisibility: .visible
        ) {
            let operations = viewModel.externalImportBatch?.operations
                ?? viewModel.externalImportCandidate?.operations
                ?? []
            if operations.contains(.convert) {
                Button(l10n.t("تحويل إلى Word", "Convert to Word")) {
                    selectedTab = .convert
                    viewModel.routeExternalImport(to: .convert, l10n: l10n)
                }
            }
            if operations.contains(.translate) {
                Button(l10n.t("ترجمة المستندات", "Translate documents")) {
                    selectedTab = .translate
                    viewModel.routeExternalImport(to: .translate, l10n: l10n)
                }
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { viewModel.cancelExternalImport() }
        } message: {
            let count = viewModel.externalImportBatch?.urls.count ?? 1
            Text(l10n.t("استلم بصير \(count) من العناصر. اختر العملية المطلوبة.",
                        "Basir received \(count) item(s) from another app."))
        }
        .alert(
            l10n.t("تعذر فتح الملف", "Could not open the file"),
            isPresented: Binding(
                get: { viewModel.externalImportError != nil },
                set: { if !$0 { viewModel.clearExternalImportError() } }
            )
        ) {
            Button(l10n.t("حسنًا", "OK")) { viewModel.clearExternalImportError() }
        } message: { Text(viewModel.externalImportError ?? "") }
        .fullScreenCover(isPresented: $viewModel.isSettingsPresented) {
            SettingsView()
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(viewModel)
                .environmentObject(NetworkMonitor.shared)
                .environment(\.layoutDirection, l10n.layoutDirection)
                .environment(\.locale, l10n.locale)
        }
        .fullScreenCover(isPresented: $viewModel.isJobPresented) {
            JobView()
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(viewModel)
                .environmentObject(outputLibrary)
                .environmentObject(NetworkMonitor.shared)
                .environment(\.layoutDirection, l10n.layoutDirection)
                .environment(\.locale, l10n.locale)
        }
    }

    private func selectTabForRoutedDocument() {
        let operation = viewModel.routedExternalBatch?.operation
            ?? viewModel.routedExternalDocument?.operation
        guard let operation else { return }
        selectedTab = operation == .convert ? .convert : .translate
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { NetworkStatusPill() }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { viewModel.isSettingsPresented = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BasirPalette.cyan)
            }
            .accessibilityLabel(l10n.t("الإعدادات", "Settings"))
            .accessibilityHint(l10n.t("تغيير اللغة وخيارات المستندات والأصوات.",
                                      "Change language, document, and sound options."))
        }
    }
}

