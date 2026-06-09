import SwiftUI

struct TutorView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @StateObject private var model = TutorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected {
                Label("وضع دون إنترنت: يعمل المصحح المحلي", systemImage: "wifi.slash")
                    .font(.caption).padding(8).frame(maxWidth: .infinity).background(.thinMaterial)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                        if model.isSending { ProgressView("يفكر المدرّس") }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("اكتب رسالتك بالإنجليزية أو العربية", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...5)
                Button {
                    Task { await model.send(container: container, level: session.selectedLevel) }
                } label: { Image(systemName: "paperplane.fill").frame(width: 44, height: 44) }
                .buttonStyle(.borderedProminent)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
                .accessibilityLabel("إرسال")
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("المدرّس التفاعلي")
        .alert("تعذر الإرسال", isPresented: .constant(model.errorMessage != nil)) {
            Button("حسنًا") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct MessageBubble: View {
    let message: TutorMessage
    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .padding(14)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            ForEach(message.corrections, id: \.self) { correction in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(correction.original) → \(correction.replacement)").font(.headline).environment(\.layoutDirection, .leftToRight)
                    Text(correction.reason).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            if !message.suggestedReplies.isEmpty {
                Text("اقتراحات: \(message.suggestedReplies.joined(separator: "، "))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "رسالتك" : "رد المدرّس")
    }
}
