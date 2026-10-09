import SwiftUI

/// "لاتيه بارد قوي": type or dictate an order (the keyboard's microphone),
/// hear what was understood, and make it.
struct DrinkSearchView: View {
    @Environment(AppModel.self) var model
    @State var text = ""
    @State var pendingBrew: Recipe?
    @FocusState var focused: Bool

    private var match: DrinkQuery.Match? {
        DrinkQuery.parse(text) { model.data.recipe(for: $0) }
    }

    private var nameMatches: [BeverageID] {
        let query = DrinkQuery.normalize(text)
        guard query.count >= 2 else { return [] }
        return BeverageID.allCases.filter { beverage in
            DrinkQuery.names(for: beverage).contains { $0.contains(query) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField(L("search.placeholder"), text: $text)
                    .font(.title3)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { if let match { pendingBrew = match.recipe } }
                    .accessibilityHint(L("search.field.hint"))
                Text(L("search.examples"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let match {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("search.understood"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        RecipeRow(recipe: match.recipe)
                        if !match.understood.isEmpty {
                            Text(match.understood.joined(separator: L("list.separator")))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Button { pendingBrew = match.recipe } label: { Label(L("action.brewNow"), systemImage: "cup.and.saucer.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                        NavigationLink(value: DrinkRoute.favorite(match.recipe)) { Text(L("search.adjust")) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(16)
                    .card()
                    .accessibilityElement(children: .contain)
                } else if !text.isEmpty {
                    Text(L("search.noMatch"))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !nameMatches.isEmpty {
                    SectionTitle(text: L("search.drinks"))
                    ForEach(nameMatches, id: \.self) { beverage in
                        NavigationLink(value: DrinkRoute.beverage(beverage)) { RecipeRow(recipe: model.data.recipe(for: beverage)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("search.title"))
        .navigationBarTitleDisplayMode(.inline)
        .brewConfirmation(recipe: $pendingBrew)
        .onAppear { focused = true }
        .onChange(of: match?.recipe.beverage) { _, beverage in
            guard let beverage else { return }
            Announcer.shared.announce(L("search.found", beverage.name))
        }
    }
}

/// Reorder or hide home sections.
struct HomeLayoutView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        List {
            Section {
                ForEach(model.data.life.orderedHomeSections) { section in
                    let visible = !model.data.life.hiddenHomeSections.contains(section)
                    Toggle(isOn: Binding(get: { visible }, set: { value in model.updateData { $0.life.setHomeSection(section, visible: value) } })) {
                        Text(section.title)
                    }
                    .accessibilityAction(named: Text(L("action.moveUp"))) { move(section, -1) }
                    .accessibilityAction(named: Text(L("action.moveDown"))) { move(section, 1) }
                }
                .onMove { source, destination in
                    model.updateData { data in
                        var order = data.life.orderedHomeSections
                        order.move(fromOffsets: source, toOffset: destination)
                        data.life.homeOrder = order
                    }
                }
            } footer: {
                Text(L("homeLayout.footer"))
            }
            Section {
                Button(L("homeLayout.reset")) {
                    model.updateData { $0.life.homeOrder = HomeSection.allCases; $0.life.hiddenHomeSections = [] }
                    Announcer.shared.announce(L("homeLayout.resetDone"))
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("homeLayout.title"))
    }

    private func move(_ section: HomeSection, _ offset: Int) {
        model.updateData { $0.life.moveHomeSection(section, by: offset) }
        if let index = model.data.life.orderedHomeSections.firstIndex(of: section) {
            Announcer.shared.announce(L("announce.moved", section.title, index + 1))
        }
    }
}

/// Today's caffeine, the limit, the evening cut-off and the Health app.
struct CaffeineView: View {
    @Environment(AppModel.self) var model
    @State var healthMessage: String?

    var body: some View {
        let todayRecords = model.activeProfile.history.filter { $0.completed && Calendar.current.isDateInToday($0.date) }
        Form {
            Section {
                LabeledContent(L("caffeine.today"), value: L("caffeine.mg", model.caffeineToday))
                Stepper(value: Binding(get: { model.settings.caffeineLimitMg },
                                       set: { value in model.updateSettings { $0.caffeineLimitMg = value } }),
                        in: 100...800, step: 25) {
                    LabeledContent(L("caffeine.limit"), value: L("caffeine.mg", model.settings.caffeineLimitMg))
                }
                Picker(L("caffeine.cutoff"), selection: Binding(get: { model.settings.caffeineCutoffHour },
                                                                set: { value in model.updateSettings { $0.caffeineCutoffHour = value } })) {
                    Text(L("caffeine.cutoff.off")).tag(-1)
                    ForEach(12..<23, id: \.self) { hour in Text(L("caffeine.cutoff.hour", hour)).tag(hour) }
                }
            } footer: {
                Text(L("caffeine.footer"))
            }
            Section(L("caffeine.cups")) {
                if todayRecords.isEmpty {
                    Text(L("caffeine.none"))
                }
                ForEach(todayRecords) { record in
                    LabeledContent(record.recipe.displayName,
                                   value: L("caffeine.mg", CaffeineEstimator.milligrams(for: record.recipe)))
                }
            }
            Section {
                Toggle(L("caffeine.health"), isOn: Binding(get: { model.settings.writeCaffeineToHealth }, set: { value in
                    if value {
                        Task {
                            let granted = await HealthCaffeine.shared.requestAccess()
                            model.updateSettings { $0.writeCaffeineToHealth = granted }
                            healthMessage = granted ? L("caffeine.health.on") : L("caffeine.health.denied")
                            Announcer.shared.announce(healthMessage ?? "")
                        }
                    } else {
                        model.updateSettings { $0.writeCaffeineToHealth = false }
                    }
                }))
                if let healthMessage { Text(healthMessage).font(.footnote) }
            } footer: {
                Text(L("caffeine.health.footer"))
            }
        }
        .tint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("caffeine.title"))
    }
}
