import SwiftUI
import UIKit

extension AppModel {
    /// A two-way binding to one app setting, saved on every change.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.updateSettings { $0[keyPath: keyPath] = value } })
    }

    /// A two-way binding into version 3 data, saved on every change.
    func proBinding<Value>(_ keyPath: WritableKeyPath<ProData, Value>) -> Binding<Value> {
        Binding(get: { self.data.life.pro[keyPath: keyPath] }, set: { value in self.updateData { $0.life.pro[keyPath: keyPath] = value } })
    }
}

/// Lists in the version 3 screens share the app's look.
struct ProForm<Content: View>: View {
    let title: String
    var help: HelpTopic?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form { content() }
            .tint(Theme.accent)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let help { HelpButton(topic: help) }
                }
            }
    }
}

/// The "?" button: a short explanation of the screen, read in full by VoiceOver.
struct HelpButton: View {
    let topic: HelpTopic
    @State var showing = false

    var body: some View {
        Button { showing = true } label: { Image(systemName: "questionmark.circle") }
            .accessibilityLabel(L("help.button"))
            .accessibilityHint(topic.title)
            .accessibilityInputLabels([L("help.button"), L("help.voice")])
            .sheet(isPresented: $showing) {
                NavigationStack {
                    ScrollView {
                        Text(topic.body)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .screenBackground()
                    .navigationTitle(topic.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("action.done")) { showing = false } } }
                }
                .presentationDetents([.medium, .large])
            }
    }
}

/// Machine state as a shape as well as a colour: circle ready, triangle
/// needs attention, square stopped. Readable without colour vision.
struct StatusShape: View {
    enum Kind { case ready, attention, stopped, unknown }
    let kind: Kind

    init(snapshot: MachineSnapshot, connected: Bool) {
        if !connected || snapshot.power == .unknown { kind = .unknown }
        else if !snapshot.blockingAlarms.isEmpty { kind = .stopped }
        else if !snapshot.alarms.isEmpty || snapshot.power != .ready { kind = .attention }
        else { kind = .ready }
    }

    var body: some View {
        Group {
            switch kind {
            case .ready: Image(systemName: "circle.fill").foregroundStyle(Theme.success)
            case .attention: Image(systemName: "triangle.fill").foregroundStyle(Theme.warning)
            case .stopped: Image(systemName: "square.fill").foregroundStyle(Theme.danger)
            case .unknown: Image(systemName: "questionmark.diamond.fill").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.title3)
        .accessibilityHidden(true)
    }

    var legend: String {
        switch kind {
        case .ready: return L("shape.ready")
        case .attention: return L("shape.attention")
        case .stopped: return L("shape.stopped")
        case .unknown: return L("shape.unknown")
        }
    }
}

/// A file shared through the share sheet (backup, spreadsheet).
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

enum ExportWriter {
    static func write(_ text: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func write(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// The app's version as people see it: "3.0.0 (3)".
enum AppVersion {
    static var marketing: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static var full: String { "\(marketing) (\(build))" }
}
