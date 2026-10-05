import SwiftUI

/// Three short steps: what the app does, how to reach the machine, your name.
struct OnboardingView: View {
    @Environment(AppModel.self) var model
    @State var page = 0
    @State var name = ""
    @State var linkKind: MachineLinkKind = .bluetooth
    @AccessibilityFocusState var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch page {
                    case 0: welcome
                    case 1: connection
                    default: profile
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .screenBackground()
        .onAppear { titleFocused = true }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                DrinkIllustration(beverage: .espresso).frame(width: 90)
                DrinkIllustration(beverage: .cappuccino).frame(width: 110)
                DrinkIllustration(beverage: .latteMacchiato).frame(width: 90)
            }
            .frame(maxWidth: .infinity)
            title(L("onboarding.welcome.title"))
            Text(L("onboarding.welcome.body")).font(.body).foregroundStyle(Theme.textPrimary)
            ForEach(1...4, id: \.self) { index in
                Label(L("onboarding.feature.\(index)"), systemImage: ["cup.and.saucer.fill", "slider.horizontal.3", "bell.badge.fill", "mic.fill"][index - 1])
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(L("onboarding.connection.title"))
            Text(L("onboarding.connection.body")).font(.body).foregroundStyle(Theme.textPrimary)
            ForEach(MachineLinkKind.allCases) { kind in
                Button {
                    linkKind = kind
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: linkKind == kind ? "largecircle.fill.circle" : "circle")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(kind.detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .card(raised: linkKind == kind)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(linkKind == kind ? [.isButton, .isSelected] : .isButton)
            }
            Text(L("onboarding.connection.note")).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(L("onboarding.profile.title"))
            Text(L("onboarding.profile.body")).font(.body).foregroundStyle(Theme.textPrimary)
            TextField(L("profile.name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.done)
                .onSubmit(finish)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button(L("guide.previous")) { go(page - 1) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(page < 2 ? L("guide.next") : L("onboarding.start")) {
                page < 2 ? go(page + 1) : finish()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(Theme.background)
    }

    private func go(_ next: Int) {
        page = next
        titleFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { titleFocused = true }
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { model.renameProfile(model.data.activeProfileID, to: trimmed) }
        model.switchLink(to: linkKind)
        model.updateSettings { $0.hasCompletedOnboarding = true }
    }
}
