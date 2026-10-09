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
            if let session, session.isRunning, model.settings.giantBrewing {
                GiantBrewingPanel(session: session) { Task { await model.stopBrewing() } }
            } else if let session {
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
        // Two-finger double-tap stops the drink at once, from anywhere here.
        .accessibilityAction(.magicTap) {
            if session?.isRunning == true { Task { await model.stopBrewing() } }
        }
        .onAppear { headingFocused = true }
        .onChange(of: session?.outcome) { _, _ in headingFocused = true }
    }

    private func titleBlock(_ session: BrewSession) -> some View {
        VStack(spacing: 8) {
            Text(headline(session))
                .font(.display(.largeTitle, weight: .semibold))
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
            .accessibilityInputLabels([L("action.stop"), L("voice.stop")])
        } else {
            VStack(spacing: 12) {
                if session.outcome == .finished, let sequence = model.sequence, let next = sequence.current {
                    VStack(alignment: .leading, spacing: 8) {
                        if let instruction = sequence.nextInstructionForCurrent {
                            Text(instruction).font(.headline).foregroundStyle(Theme.textPrimary)
                        }
                        Button(L("sequence.continue", next.displayName)) { Task { await model.continueSequence() } }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityInputLabels([L("sequence.continue", next.displayName), L("voice.next")])
                        Button(L("sequence.cancel")) { model.cancelSequence() }
                            .buttonStyle(TextLinkButtonStyle())
                    }
                    .padding(14)
                    .card(raised: true)
                }
                if session.outcome == .finished, session.recipe.spec.isTea || session.recipe.beverage == .hotWater, model.sequence == nil {
                    NavigationLink { TeaTimerView() } label: { Label(L("screen.teaTimer"), systemImage: "timer") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if session.outcome == .finished, !model.data.guestMode, let record = model.lastFinishedRecord,
                   record.recipe.beverage == session.recipe.beverage {
                    RatingCard(recordID: record.id, recipe: session.recipe)
                }
                if session.outcome == .finished, session.recipe.spec.usesMilk, model.data.life.carafeCleanPending {
                    HStack(spacing: 10) {
                        Text(L("carafe.after")).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Button(L("carafe.cleaned")) { model.markCarafeCleaned() }.buttonStyle(PillButtonStyle())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: Text(L("carafe.cleaned"))) { model.markCarafeCleaned() }
                }
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

/// Three quick questions after a cup: liked it? strength right? a note.
struct RatingCard: View {
    @Environment(AppModel.self) var model
    let recordID: UUID
    let recipe: Recipe
    @State var note = ""
    @State var showingNote = false

    var body: some View {
        let rating = model.rating(for: recordID)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("rating.question")).font(.headline).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                choice(L("rating.liked"), symbol: "hand.thumbsup", selected: rating?.liked == true) {
                    model.rate(recordID) { $0.liked = true }
                    Announcer.shared.announce(L("rating.thanks"))
                }
                choice(L("rating.disliked"), symbol: "hand.thumbsdown", selected: rating?.liked == false) {
                    model.rate(recordID) { $0.liked = false }
                    Announcer.shared.announce(L("rating.thanks"))
                }
            }
            if recipe.spec.hasAroma {
                HStack(spacing: 8) {
                    ForEach(StrengthFeedback.allCases, id: \.self) { feedback in
                        choice(feedback.title, symbol: nil, selected: rating?.strength == feedback) {
                            model.rate(recordID) { $0.strength = feedback }
                            model.applyStrengthFeedback(feedback, to: recipe)
                        }
                    }
                }
            }
            if showingNote {
                TextField(L("rating.note.placeholder"), text: $note, axis: .vertical)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    .onSubmit(saveNote)
                Button(L("action.save"), action: saveNote).buttonStyle(PillButtonStyle())
            } else {
                Button(L("rating.note.add")) {
                    note = rating?.note ?? ""
                    showingNote = true
                }
                .buttonStyle(TextLinkButtonStyle())
            }
        }
        .padding(14)
        .card(raised: true)
    }

    private func saveNote() {
        model.rate(recordID) { $0.note = note.trimmingCharacters(in: .whitespacesAndNewlines) }
        showingNote = false
        Announcer.shared.announce(L("rating.note.saved"))
    }

    private func choice(_ title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: selected ? symbol + ".fill" : symbol) } else { Text(title) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Theme.onInk : Theme.textPrimary)
            .background(Capsule().fill(selected ? Theme.ink : Theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
