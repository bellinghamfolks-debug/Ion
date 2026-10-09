import SwiftUI
import UIKit

/// A numbered drinks menu to send to guests, and their replies read back
/// into the order queue.
struct GuestMenuView: View {
    @Environment(AppModel.self) var model
    @State var reply = ""
    @State var parsed: [Int] = []

    var body: some View {
        let choices = GuestMenu.choices(favorites: model.activeProfile.favorites, data: model.data)
        let text = GuestMenu.text(choices, host: model.activeProfile.name)
        ProForm(title: L("screen.guestMenu"), help: .hosting) {
            Section {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, recipe in
                    Text("\(index + 1). \(recipe.displayName)")
                }
                ShareLink(item: text) { Label(L("guestMenu.send"), systemImage: "square.and.arrow.up") }
                if let whatsapp = URL(string: "whatsapp://send?text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Button { UIApplication.shared.open(whatsapp) } label: { Label(L("guestMenu.whatsapp"), systemImage: "message") }
                }
            } footer: { Text(L("guestMenu.footer.app")) }
            Section {
                TextField(L("guestMenu.reply"), text: $reply, axis: .vertical)
                Button(L("guestMenu.read")) {
                    parsed = GuestMenu.parse(reply, count: choices.count)
                    Announcer.shared.announce(parsed.isEmpty ? L("guestMenu.noNumbers") : L("guestMenu.found", parsed.count))
                }
                if !parsed.isEmpty {
                    ForEach(Array(parsed.enumerated()), id: \.offset) { _, index in
                        Text(choices[safe: index]?.displayName ?? "")
                    }
                    Button(L("guestMenu.toQueue", parsed.count)) {
                        let items = parsed.compactMap { choices[safe: $0] }.enumerated().map { number, recipe in
                            FamilyQueue.Item(name: L("guestMenu.guest", number + 1), recipe: recipe)
                        }
                        FamilyQueue.shared.start(QueuePlanner.ordered(items, recipe: { $0.recipe }), model: model)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text(HostingPlan.make(parsed.compactMap { choices[safe: $0] }, learned: model.data.life.pro.learnedSeconds).sentence)
                        .font(.footnote)
                }
            } header: { Text(L("guestMenu.replies")) } footer: { Text(L("guestMenu.replyFooter")) }
        }
    }
}

/// How much a gathering needs, from a count of each drink.
struct HostingPlannerView: View {
    @Environment(AppModel.self) var model
    @State var counts: [BeverageID: Int] = [.cappuccino: 2, .espresso: 2]

    private let menu: [BeverageID] = [.espresso, .americano, .cappuccino, .caffeLatte, .flatWhite, .latteMacchiato,
                                      .icedCaffeLatte, .coldBrew, .hotMilk, .herbalTea]

    var body: some View {
        let recipes = counts.flatMap { beverage, count in Array(repeating: model.data.recipe(for: beverage), count: count) }
        let plan = HostingPlan.make(recipes, learned: model.data.life.pro.learnedSeconds)
        ProForm(title: L("screen.hosting"), help: .hosting) {
            Section(L("hosting.drinks")) {
                ForEach(menu, id: \.self) { beverage in
                    Stepper(value: Binding(get: { counts[beverage] ?? 0 }, set: { counts[beverage] = $0 }), in: 0...20) {
                        LabeledContent(beverage.name, value: "\(counts[beverage] ?? 0)")
                    }
                }
            }
            Section(L("hosting.plan")) {
                LabeledContent(L("hosting.cups"), value: "\(plan.cups)")
                LabeledContent(L("hosting.beans"), value: L("stock.grams", plan.beansGrams))
                LabeledContent(L("hosting.milkAmount"), value: L("unit.ml", plan.milkML))
                LabeledContent(L("hosting.water"), value: L("unit.ml", plan.waterML))
                LabeledContent(L("hosting.time"), value: L("hosting.minutes", plan.minutes))
                LabeledContent(L("hosting.refills"), value: "\(plan.tankRefills)")
                LabeledContent(L("hosting.groundsEmpties"), value: "\(plan.groundsEmpties)")
                Text(plan.sentence).font(.footnote)
            }
        }
    }
}

/// Cups per person at the office and what each owes.
struct OfficeTallyView: View {
    @Environment(AppModel.self) var model
    @State var newName = ""

    var body: some View {
        let office = model.data.life.pro.office
        ProForm(title: L("screen.office")) {
            Section {
                ForEach(office.people) { person in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(person.name).font(.headline)
                            Text(L("office.owes", person.cups, CostPerCup.text(office.owed(by: person)))).font(.footnote)
                        }
                        Spacer()
                        Button { change(person, by: 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel(L("office.addCup", person.name))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: Text(L("office.addCup", person.name))) { change(person, by: 1) }
                    .accessibilityAction(named: Text(L("office.removeCup", person.name))) { change(person, by: -1) }
                }
                .onDelete { offsets in model.updateData { $0.life.pro.office.people.remove(atOffsets: offsets) } }
                HStack {
                    TextField(L("office.name"), text: $newName)
                    Button(L("action.add")) {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        model.updateData { $0.life.pro.office.people.append(OfficePerson(name: name)) }
                        newName = ""
                    }
                }
            } footer: { Text(L("office.footer")) }
            Section {
                TextField(L("office.price"), value: model.proBinding(\.office.pricePerCup), format: .number).keyboardType(.decimalPad)
                LabeledContent(L("office.total"), value: L("office.totalValue", office.totalCups, CostPerCup.text(Double(office.totalCups) * office.pricePerCup)))
                ShareLink(item: office.text()) { Label(L("office.share"), systemImage: "square.and.arrow.up") }
                Button(L("office.reset"), role: .destructive) {
                    model.updateData { data in
                        for index in data.life.pro.office.people.indices { data.life.pro.office.people[index].cups = 0 }
                        data.life.pro.office.since = Date()
                    }
                }
            }
        }
    }

    private func change(_ person: OfficePerson, by delta: Int) {
        model.updateData { data in
            guard let index = data.life.pro.office.people.firstIndex(where: { $0.id == person.id }) else { return }
            data.life.pro.office.people[index].cups = max(0, data.life.pro.office.people[index].cups + delta)
        }
        let cups = model.data.life.pro.office.people.first { $0.id == person.id }?.cups ?? 0
        Announcer.shared.announce(L("office.cups", person.name, cups))
    }
}

/// Which profiles are children's: no caffeinated drinks on them.
struct ChildProfilesView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        ProForm(title: L("screen.children")) {
            Section {
                ForEach(model.data.profiles) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { model.data.life.pro.childProfiles.contains(profile.id) },
                        set: { on in
                            model.updateData { data in
                                data.life.pro.childProfiles.removeAll { $0 == profile.id }
                                if on { data.life.pro.childProfiles.append(profile.id) }
                            }
                        }))
                }
            } footer: { Text(L("children.footer")) }
            Section {
                Toggle(L("settingsLock.toggle"), isOn: model.binding(\.settingsLock))
            } footer: { Text(L("settingsLock.footer")) }
        }
    }
}

/// Today's caffeine for each person in the household, from the queue.
struct MemberCaffeineSection: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let today = model.data.life.pro.memberCups.filter { Calendar.current.isDateInToday($0.date) }
        if !today.isEmpty {
            Section(L("family.caffeine")) {
                ForEach(model.data.life.household) { member in
                    let mg = today.filter { $0.memberID == member.id }.reduce(0) { $0 + $1.mg }
                    if mg > 0 { LabeledContent(member.name, value: L("caffeine.mg", mg)) }
                }
            }
        }
    }
}

/// The queue's plan: best order, waiting times and the water tank.
struct QueuePlanSection: View {
    @Environment(AppModel.self) var model
    let recipes: [(name: String, recipe: Recipe)]

    var body: some View {
        if !recipes.isEmpty {
            let learned = model.data.life.pro.learnedSeconds
            let waits = QueuePlanner.waits(recipes.map(\.recipe), learned: learned)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("queue.plan")).font(.headline).foregroundStyle(Theme.textPrimary)
                ForEach(Array(recipes.enumerated()), id: \.offset) { index, item in
                    Text(L("queue.wait", item.name, item.recipe.displayName, max(1, waits[index] / 60)))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let refill = QueuePlanner.refillBefore(recipes.map(\.recipe)) {
                    Label(L("queue.refill", refill), systemImage: "drop.triangle").font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
                } else {
                    Label(L("queue.tankOK"), systemImage: "drop").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityElement(children: .combine)
        }
    }
}
