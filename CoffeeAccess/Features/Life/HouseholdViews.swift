import SwiftUI
import Observation

/// The household: a name and a usual drink for each person.
struct HouseholdView: View {
    @Environment(AppModel.self) var model
    @State var editing: HouseholdMember?

    var body: some View {
        List {
            Section {
                ForEach(model.data.life.household) { member in
                    Button { editing = member } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.isGuest == true ? L("family.guestName", member.name) : member.name)
                                .font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(member.recipe.spokenSummary).font(.footnote).foregroundStyle(Theme.textSecondary)
                            if member.lactoseFree == true {
                                Label(L("family.lactoseFree"), systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(Theme.warning)
                            }
                        }
                    }
                    .accessibilityAction(named: Text(L("action.delete"))) { delete(member) }
                }
                .onDelete { offsets in
                    model.updateData { $0.life.household.remove(atOffsets: offsets) }
                }
            } footer: {
                Text(L("family.footer"))
            }
            Section {
                Button {
                    editing = HouseholdMember(name: "", recipe: model.data.recipe(for: .cappuccino))
                } label: { Label(L("family.add"), systemImage: "person.badge.plus") }
                Button {
                    editing = HouseholdMember(name: "", recipe: model.data.recipe(for: .cappuccino), isGuest: true)
                } label: { Label(L("family.addGuest"), systemImage: "person.crop.circle.badge.plus") }
            }
            MemberCaffeineSection()
            Section {
                NavigationLink { GuestMenuView() } label: { Label(L("screen.guestMenu"), systemImage: "list.number") }
                NavigationLink { HostingPlannerView() } label: { Label(L("screen.hosting"), systemImage: "person.3") }
                NavigationLink { OfficeTallyView() } label: { Label(L("screen.office"), systemImage: "building.2") }
                NavigationLink { ChildProfilesView() } label: { Label(L("screen.children"), systemImage: "figure.and.child.holdinghands") }
            }
        }
        .toolbar { ToolbarItem(placement: .primaryAction) { HelpButton(topic: .household) } }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("family.title"))
        .sheet(item: $editing) { member in
            HouseholdEditor(member: member) { saved in
                model.updateData { data in
                    if let index = data.life.household.firstIndex(where: { $0.id == saved.id }) {
                        data.life.household[index] = saved
                    } else {
                        data.life.household.append(saved)
                    }
                }
                Announcer.shared.announce(L("family.saved", saved.name))
            }
        }
    }

    private func delete(_ member: HouseholdMember) {
        model.updateData { $0.life.household.removeAll { $0.id == member.id } }
        Announcer.shared.announce(L("announce.favoriteDeleted", member.name))
    }
}

/// Name, drink, strength and size for one person.
struct HouseholdEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var member: HouseholdMember
    let onSave: (HouseholdMember) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("family.name"), text: $member.name)
                RecipePicker(recipe: $member.recipe)
                Toggle(L("family.lactoseFree"), isOn: Binding(get: { member.lactoseFree == true }, set: { member.lactoseFree = $0 ? true : nil }))
                Toggle(L("family.isGuest"), isOn: Binding(get: { member.isGuest == true }, set: { member.isGuest = $0 ? true : nil }))
            }
            .navigationTitle(L("family.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action.save")) {
                        var saved = member
                        saved.name = String(member.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
                        saved.recipe.customName = ""
                        saved.recipe = saved.recipe.normalized()
                        guard !saved.name.isEmpty else { return }
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// A compact picker for a drink with its strength and size, used where a
/// full drink screen would be too much (household, schedules).
struct RecipePicker: View {
    @Binding var recipe: Recipe

    var body: some View {
        Picker(L("picker.drink"), selection: Binding(get: { recipe.beverage }, set: { recipe = Recipe.standard($0) })) {
            ForEach(BeverageCategory.allCases) { category in
                Section(category.title) {
                    ForEach(BeverageCatalog.beverages(in: category)) { Text($0.name).tag($0) }
                }
            }
        }
        if recipe.spec.hasAroma {
            Picker(L("param.aroma"), selection: Binding(get: { recipe.aroma ?? .normal }, set: { recipe.aroma = $0 })) {
                ForEach(Aroma.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        if let range = recipe.coffeeRange {
            Stepper(value: Binding(get: { recipe.coffeeML ?? range.standard }, set: { recipe.coffeeML = range.clamp($0) }),
                    in: range.min...range.max, step: range.step) {
                LabeledContent(L("param.coffee"), value: L("unit.ml", recipe.coffeeML ?? range.standard))
            }
        }
        if let range = recipe.milkRange {
            Stepper(value: Binding(get: { recipe.milkSeconds ?? range.standard }, set: { recipe.milkSeconds = range.clamp($0) }),
                    in: range.min...range.max, step: range.step) {
                LabeledContent(L("param.milk"), value: L("unit.seconds", recipe.milkSeconds ?? range.standard))
            }
        }
        if let range = recipe.waterRange {
            Stepper(value: Binding(get: { recipe.waterML ?? range.standard }, set: { recipe.waterML = range.clamp($0) }),
                    in: range.min...range.max, step: range.step) {
                LabeledContent(L("param.water"), value: L("unit.ml", recipe.waterML ?? range.standard))
            }
        }
        if recipe.spec.supportsToGo {
            Toggle(L("summary.toGo"), isOn: Binding(get: { recipe.toGo }, set: { recipe = recipe.withToGo($0) }))
        }
        if recipe.spec.supportsDouble, !recipe.toGo {
            Toggle(L("double.title"), isOn: Binding(get: { recipe.double == true }, set: { recipe.double = $0 ? true : nil }))
        }
    }
}

// MARK: - Family queue

/// "Who wants coffee?": drinks made one after another, waiting for the next
/// cup to be in place before each one.
@MainActor
@Observable
final class FamilyQueue {
    static let shared = FamilyQueue()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let recipe: Recipe
        var memberID: UUID? = nil
        /// Say "lactose-free milk" before this person's milk drink.
        var lactoseFree = false
    }

    var items: [Item] = []
    var index = 0
    var waitingForCup = false
    var isRunning = false

    var current: Item? { items[safe: index] }

    func start(_ items: [Item], model: AppModel) {
        guard !items.isEmpty else { return }
        self.items = items
        index = 0
        isRunning = true
        waitingForCup = true
        announceNext()
    }

    /// The person put the cup in place: make the current drink.
    func cupReady(model: AppModel) {
        guard isRunning, let item = current else { return }
        waitingForCup = false
        Task {
            let started = await model.brew(item.recipe)
            if !started { waitingForCup = true }
        }
    }

    /// Called by the model when a drink ends.
    func sessionEnded(_ outcome: BrewSession.Outcome) {
        guard isRunning, !waitingForCup else { return }
        guard outcome == .finished else {
            waitingForCup = true
            Announcer.shared.announce(L("queue.retry"))
            return
        }
        index += 1
        if index >= items.count {
            isRunning = false
            Announcer.shared.success()
            Announcer.shared.announce(L("queue.done"))
        } else {
            waitingForCup = true
            announceNext()
        }
    }

    func cancel() {
        isRunning = false
        items = []
    }

    private func announceNext() {
        guard let item = current else { return }
        var text = L("queue.next", item.recipe.displayName, item.name)
        if item.lactoseFree, item.recipe.spec.usesMilk { text += L("sentence.separator") + L("queue.lactose", item.name) }
        Announcer.shared.announce(text, priority: .high)
    }
}

struct FamilyQueueView: View {
    @Environment(AppModel.self) var model
    @State var selected: Set<UUID> = []
    @State var smartOrder = true

    /// The chosen people in the best order (black, hot milk, cold milk) when asked.
    private func planned(_ members: [HouseholdMember]) -> [HouseholdMember] {
        smartOrder ? QueuePlanner.ordered(members, recipe: { $0.recipe }) : members
    }
    private var queue: FamilyQueue { FamilyQueue.shared }

    var body: some View {
        let members = model.data.life.household
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if queue.isRunning, let item = queue.current {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("queue.progress", queue.index + 1, queue.items.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(L("queue.nowFor", item.recipe.displayName, item.name))
                            .font(.display(.title2, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if item.lactoseFree, item.recipe.spec.usesMilk {
                            Label(L("queue.lactose", item.name), systemImage: "exclamationmark.triangle")
                                .font(.headline).foregroundStyle(Theme.warning)
                        }
                        if queue.waitingForCup {
                            Button(L("queue.cupReady")) { queue.cupReady(model: model) }
                                .buttonStyle(PrimaryButtonStyle())
                                .accessibilityInputLabels([L("queue.cupReady"), L("voice.ready")])
                        } else {
                            Text(L("queue.making")).foregroundStyle(Theme.textSecondary)
                        }
                        Button(L("queue.cancel"), role: .destructive) { queue.cancel() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(18)
                    .card(raised: true)
                } else {
                    Text(L("queue.intro"))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(members) { member in
                        Button {
                            if selected.contains(member.id) { selected.remove(member.id) } else { selected.insert(member.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(member.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    Text(member.recipe.displayName).font(.footnote).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .card()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(member.id) ? .isSelected : [])
                    }
                    let chosen = members.filter { selected.contains($0.id) }
                    Toggle(L("queue.smartOrder"), isOn: $smartOrder).tint(Theme.accent)
                    QueuePlanSection(recipes: planned(chosen).map { ($0.name, $0.recipe) })
                    Button(L("queue.start", selected.count)) {
                        let items = planned(chosen).map {
                            FamilyQueue.Item(name: $0.name, recipe: $0.recipe, memberID: $0.id, lactoseFree: $0.lactoseFree == true)
                        }
                        queue.start(items, model: model)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selected.isEmpty)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("queue.title"))
        .onAppear { if selected.isEmpty { selected = Set(members.map(\.id)) } }
    }
}
