import SwiftUI

/// Three very large buttons for anyone who wants just coffee: the usual
/// drink, the last drink again, and the machine's state read aloud. Leaving
/// simple mode needs a deliberate long press, so it is not left by accident.
struct SimpleModeView: View {
    @Environment(AppModel.self) var model
    @State var pendingBrew: Recipe?
    @State var confirmExit = false

    var body: some View {
        let usual = model.usualRecipe
        VStack(spacing: 18) {
            Text(L("simple.title"))
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(model.connection.isConnected ? model.snapshot.spokenStatus : model.connection.title)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            bigButton(L("simple.usual", usual.displayName), symbol: "cup.and.saucer.fill", prominent: true) {
                pendingBrew = usual
            }
            if let last = model.lastRecipe {
                bigButton(L("simple.last", last.displayName), symbol: "arrow.uturn.backward", prominent: false) {
                    pendingBrew = last
                }
            }
            bigButton(L("simple.status"), symbol: "speaker.wave.2.fill", prominent: false) {
                let text = model.connection.isConnected ? model.snapshot.spokenStatus : model.connection.title
                Announcer.shared.announce(text, priority: .high)
                if !UIAccessibility.isVoiceOverRunning { Tones.shared.cue(model.snapshot.isReadyToBrew ? .ready : .problem) }
            }
            Spacer(minLength: 0)
            Text(L("simple.exitHint"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .onLongPressGesture(minimumDuration: 1.5) { confirmExit = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { confirmExit = true }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .brewConfirmation(recipe: $pendingBrew)
        .confirmationDialog(L("simple.exit"), isPresented: $confirmExit, titleVisibility: .visible) {
            Button(L("simple.exit")) { model.updateSettings { $0.simpleMode = false } }
            Button(L("action.cancel"), role: .cancel) {}
        }
    }

    private func bigButton(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 40, weight: .semibold)).accessibilityHidden(true)
                Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(prominent ? Theme.accent : Theme.surface))
        }
        .buttonStyle(.plain)
    }
}
