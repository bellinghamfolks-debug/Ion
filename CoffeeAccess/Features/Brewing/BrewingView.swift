import SwiftUI

/// Full-screen view while a drink is prepared: the cup fills, the current
/// phase is spoken, and a large Stop button is always one tap away.
struct BrewingView: View {
    @Environment(AppModel.self) var model
    @AccessibilityFocusState var headingFocused: Bool
    @State var savedFavorite = false

    private var session: BrewSession? { model.session }

    var body: some View {
        VStack(spacing: 24) {
            if let session {
                Spacer(minLength: 8)
                DrinkIllustration(beverage: session.recipe.beverage, fill: max(0.05, session.progress), toGo: session.recipe.toGo)
                    .frame(maxWidth: 260)
                titleBlock(session)
                progressBlock(session)
                Spacer(minLength: 8)
                buttons(session)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear { headingFocused = true }
        .onChange(of: session?.outcome) { _, _ in headingFocused = true }
    }

    private func titleBlock(_ session: BrewSession) -> some View {
        VStack(spacing: 8) {
            Text(headline(session))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(session.recipe.spokenSummary)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let ice = session.recipe.iceLevel, session.isRunning {
                Label(L("brew.ice.hint", ice.cubes), systemImage: "snowflake")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func headline(_ session: BrewSession) -> String {
        switch session.outcome {
        case .running: return session.activity == .idle ? L("brew.preparing", session.recipe.displayName) : session.activity.title
        case .finished: return L("brew.finished", session.recipe.displayName)
        case .stopped: return L("brew.stopped")
        case .failed(let reason): return L("brew.failed", reason)
        }
    }

    @ViewBuilder
    private func progressBlock(_ session: BrewSession) -> some View {
        if session.isRunning {
            VStack(spacing: 8) {
                ProgressView(value: session.progress)
                    .tint(Theme.accent)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                Text(L("unit.percent", Int(session.progress * 100)))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("brew.progress"))
            .accessibilityValue(L("unit.percent", Int(session.progress * 100)))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    @ViewBuilder
    private func buttons(_ session: BrewSession) -> some View {
        if session.isRunning {
            Button(role: .destructive) {
                Task { await model.stopBrewing() }
            } label: {
                Label(L("action.stop"), systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle(role: .destructive))
            .accessibilityHint(L("brew.stop.hint"))
        } else {
            VStack(spacing: 12) {
                if session.outcome == .finished, !savedFavorite,
                   !model.activeProfile.favorites.contains(where: { matches($0, session.recipe) }) {
                    Button(L("brew.saveFavorite")) {
                        var favorite = session.recipe
                        favorite.id = UUID()
                        model.updateData { _ = $0.saveFavorite(favorite) }
                        savedFavorite = true
                        Announcer.shared.announce(L("announce.favoriteSaved", favorite.displayName))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if case .failed = session.outcome {
                    Button(L("action.tryAgain")) {
                        let recipe = session.recipe
                        model.dismissSession()
                        Task { await model.brew(recipe) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(L("action.done")) { model.dismissSession() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func matches(_ a: Recipe, _ b: Recipe) -> Bool {
        var copy = a
        copy.id = b.id
        return copy.normalized() == b.normalized()
    }
}
