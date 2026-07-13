import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var log = DiagnosticsLog.shared
    @EnvironmentObject private var model: RouterViewModel

    @State private var goformId = ""
    @State private var fieldsText = ""   // key=value per line

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("يسجّل هذا كل طلب واستجابة مع الراوتر. إن رُفض أمر، انسخ الاستجابة لنعدّل الأمر لإصدار جهازك.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("أمر مخصّص (متقدّم)") {
                    TextField("goformId (مثال: SET_LOCK_BAND)", text: $goformId)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .environment(\.layoutDirection, .leftToRight)
                    TextField("حقول key=value لكل سطر", text: $fieldsText, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .environment(\.layoutDirection, .leftToRight)
                    Button("إرسال") {
                        Task { await model.sendRaw(goformId: goformId.trimmingCharacters(in: .whitespaces),
                                                   fields: parseFields()) }
                    }
                    .disabled(!model.isConnected || goformId.isEmpty)
                }

                Section {
                    ForEach(log.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(fmt.string(from: entry.time)) \(entry.kind.rawValue)")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .environment(\.layoutDirection, .leftToRight)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    HStack {
                        Text("السجل")
                        Spacer()
                        Button("مسح") { log.clear() }.font(.caption)
                    }
                }
            }
            .navigationTitle("سجل التشخيص")
        }
    }

    private func parseFields() -> [String: String] {
        var out: [String: String] = [:]
        for line in fieldsText.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }
}
