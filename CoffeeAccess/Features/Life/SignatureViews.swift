import SwiftUI

struct SignatureListView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(SignatureRecipeID.allCases) { id in
                    NavigationLink(value: HomeRoute.signature(id)) { SignatureTile(recipeID: id) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("signature.section"))
    }
}

/// A recipe with steps the machine cannot do: ingredients to tick, steps
/// before, the machine's part, then steps after, one at a time.
struct SignatureRecipeView: View {
    @Environment(AppModel.self) var model
    let recipeID: SignatureRecipeID
    @State var checked: Set<Int> = []
    @State var stepIndex = 0
    @State var confirmBrew = false
    @AccessibilityFocusState var stepFocused: Bool

    private enum Step: Equatable { case manual(String), machine }

    private var steps: [Step] {
        recipeID.beforeSteps.map(Step.manual) + [.machine] + recipeID.afterSteps.map(Step.manual)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipeID.title)
                            .font(.display(.largeTitle))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(recipeID.summary)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    DrinkIllustration(beverage: recipeID.spec.base, showsSteam: false)
                        .frame(width: 100)
                        .accessibilityHidden(true)
                }
                ingredients
                stepCard
                Text(L("signature.base", recipeID.recipe.spokenSummary))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(recipeID.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("brew.confirm.title", recipeID.title), isPresented: $confirmBrew, titleVisibility: .visible) {
            Button(L("action.brewNow")) { Task { await brewAndAdvance() } }
            Button(L("action.cancel"), role: .cancel) {}
        } message: {
            Text(recipeID.recipe.spokenSummary)
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("signature.ingredients"))
            ForEach(Array(recipeID.ingredients.enumerated()), id: \.offset) { index, text in
                Button {
                    if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text(text).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checked.contains(index) ? .isSelected : [])
                .accessibilityHint(L("signature.ingredient.hint"))
            }
        }
    }

    private var stepCard: some View {
        let step = steps[min(stepIndex, steps.count - 1)]
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("signature.stepOf", stepIndex + 1, steps.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            switch step {
            case .manual(let text):
                Text(text)
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($stepFocused)
            case .machine:
                Text(L("signature.machineStep", recipeID.recipe.beverage.name))
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityFocused($stepFocused)
                Button { confirmBrew = true } label: { Label(L("action.brewNow"), systemImage: "cup.and.saucer.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 12) {
                Button(L("guide.previous")) { move(-1) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(stepIndex == 0)
                if stepIndex + 1 < steps.count {
                    Button(L("guide.next")) { move(1) }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(L("signature.enjoy")) { Announcer.shared.announce(L("signature.enjoy.spoken")) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(18)
        .card(raised: true)
    }

    private func move(_ delta: Int) {
        stepIndex = max(0, min(steps.count - 1, stepIndex + delta))
        stepFocused = true
    }

    private func brewAndAdvance() async {
        await model.brewSignature(recipeID)
        if stepIndex + 1 < steps.count { stepIndex += 1 }
    }
}
