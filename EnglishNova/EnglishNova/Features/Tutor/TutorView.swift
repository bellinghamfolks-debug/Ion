import SwiftUI

struct TutorView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @StateObject private var model = TutorViewModel()
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected && container.settings.tutorProvider != .device {
                Label(L("لا يوجد اتصال بالإنترنت. سيستخدم التطبيق المدرّب المحلي."), systemImage: "wifi.slash")
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.messages) { message in
                            MessageBubble(
                                message: message,
                                isSpeaking: textToSpeech.isSpeaking,
                                onSpeak: { model.speak(message, container: container) },
                                onStop: { model.stopSpeaking(container: container) }
                            )
                            .id(message.id)
                        }

                        if model.isSending {
                            ProgressView(L("جارٍ إعداد الرد"))
                                .accessibilityLabel(L("المدرّب يجهز الرد"))
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField(L("اكتب سؤالًا أو جملة"), text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
                    Task { await model.send(container: container, level: session.selectedLevel) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
                .accessibilityLabel(L("إرسال"))
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle(L("المدرّب"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.startNewConversation(container: container)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(L("بدء محادثة جديدة"))

                Button {
                    Task { await model.loadHistory(container: container) }
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(L("سجل المحادثات"))
            }
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView(model: model)
                .environmentObject(container)
        }
        .task { await model.loadHistory(container: container) }
        .onDisappear { model.stopSpeaking(container: container) }
        .alert(L("تعذر إرسال الرسالة"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L("حسنًا")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct MessageBubble: View {
    let message: TutorMessage
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onStop: () -> Void

    private var isAssistant: Bool { message.role == .assistant }

    var body: some View {
        VStack(alignment: isAssistant ? .leading : .trailing, spacing: 8) {
            Text(message.text)
                .padding(14)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.18)
                        : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            ForEach(message.corrections, id: \.self) { correction in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(correction.original) → \(correction.replacement)")
                        .font(.headline)
                        .environment(\.layoutDirection, .leftToRight)
                    Text(correction.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }

            if !message.suggestedReplies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("يمكنك أن تقول:"))
                        .font(.caption.bold())
                    ForEach(message.suggestedReplies, id: \.self) { reply in
                        Text(reply)
                            .font(.caption)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .foregroundStyle(.secondary)
            }

            if isAssistant {
                Button {
                    isSpeaking ? onStop() : onSpeak()
                } label: {
                    Label(
                        isSpeaking ? L("إيقاف الصوت") : L("سماع الرد"),
                        systemImage: isSpeaking ? "stop.circle" : "speaker.wave.2.circle"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: isAssistant ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: isAssistant ? L("سماع رد المدرّب") : L("سماع الرسالة")) {
            onSpeak()
        }
    }

    private var accessibilityText: String {
        var parts: [String] = [
            isAssistant ? L("رد المدرّب:") : L("رسالتك:"),
            message.text
        ]

        for correction in message.corrections {
            parts.append(
                Lf(
                    "تصحيح: %@ تصبح %@. %@",
                    correction.original,
                    correction.replacement,
                    correction.reason
                )
            )
        }

        if !message.suggestedReplies.isEmpty {
            parts.append(Lf("ردود مقترحة: %@", message.suggestedReplies.joined(separator: "، ")))
        }
        return parts.joined(separator: " ")
    }
}

struct ConversationHistoryView: View {
    @ObservedObject var model: TutorViewModel
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.savedConversations.isEmpty {
                    ContentUnavailableView(
                        L("لا توجد محادثات محفوظة"),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(L("ستظهر هنا محادثاتك السابقة مع المدرّب على هذا الجهاز."))
                    )
                } else {
                    List {
                        ForEach(model.savedConversations) { conversation in
                            Button {
                                model.open(conversation, container: container)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text(conversation.updatedAt, style: .date)
                                        Text(conversation.provider.titleAr)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel(
                                Lf("محادثة: %@، %@", conversation.title, conversation.provider.titleAr)
                            )
                        }
                        .onDelete { indexSet in
                            let targets = indexSet.map { model.savedConversations[$0] }
                            Task {
                                for target in targets {
                                    await model.delete(target, container: container)
                                }
                                ToastCenter.shared.show(L("تم حذف المحادثة"), style: .info)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("سجل المحادثات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("إغلاق")) { dismiss() }
                }
            }
        }
    }
}
