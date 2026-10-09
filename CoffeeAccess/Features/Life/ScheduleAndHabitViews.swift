import SwiftUI

/// Drinks at a set time: a reminder that opens the app ready, or that makes
/// the drink from its "Make it now" button.
struct ScheduleListView: View {
    @Environment(AppModel.self) var model
    @State var editing: ScheduledBrew?

    var body: some View {
        List {
            Section {
                ForEach(model.data.life.scheduledBrews) { schedule in
                    Button { editing = schedule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("schedule.row", schedule.timeText, schedule.recipe.displayName))
                                    .font(.headline).foregroundStyle(Theme.textPrimary)
                                Text(schedule.daysText).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if !schedule.enabled {
                                Text(L("schedule.off")).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .accessibilityAction(named: Text(L("action.delete"))) { model.deleteSchedule(schedule.id) }
                }
                .onDelete { offsets in
                    for index in offsets { model.deleteSchedule(model.data.life.scheduledBrews[index].id) }
                }
            } footer: {
                Text(L("schedule.footer"))
            }
            Section {
                Button {
                    editing = ScheduledBrew(recipe: model.usualRecipe)
                } label: { Label(L("schedule.add"), systemImage: "alarm") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("schedule.title"))
        .sheet(item: $editing) { schedule in
            ScheduleEditor(schedule: schedule) { model.saveSchedule($0) }
        }
    }
}

struct ScheduleEditor: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var schedule: ScheduledBrew
    let onSave: (ScheduledBrew) -> Void

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(hour: schedule.hour, minute: schedule.minute)) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule.hour = parts.hour ?? 7
            schedule.minute = parts.minute ?? 0
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L("schedule.time"), selection: time, displayedComponents: .hourAndMinute)
                Section(L("schedule.days")) {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(ScheduledBrew.dayName(day), isOn: Binding(
                            get: { schedule.weekdays.contains(day) },
                            set: { on in
                                schedule.weekdays.removeAll { $0 == day }
                                if on { schedule.weekdays.append(day) }
                            }))
                    }
                }
                Section(L("schedule.drink")) {
                    if !model.activeProfile.favorites.isEmpty {
                        Menu(L("schedule.fromFavorites")) {
                            ForEach(model.activeProfile.favorites) { favorite in
                                Button(favorite.displayName) { schedule.recipe = favorite }
                            }
                        }
                    }
                    RecipePicker(recipe: $schedule.recipe)
                }
                Section {
                    Toggle(L("schedule.turnOn"), isOn: $schedule.turnOnFirst)
                    Toggle(L("schedule.enabled"), isOn: $schedule.enabled)
                    TextField(L("schedule.owner"), text: $schedule.ownerName)
                } footer: {
                    Text(L("schedule.honest"))
                }
            }
            .navigationTitle(L("schedule.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action.save")) {
                        onSave(schedule)
                        Announcer.shared.announce(L("schedule.saved", schedule.timeText))
                        dismiss()
                    }
                }
            }
        }
    }
}

extension ScheduledBrew {
    static func dayName(_ day: Int) -> String {
        let symbols = AppLanguage.current == .arabic ? arabicDays : Calendar.current.weekdaySymbols
        return symbols[safe: day - 1] ?? "\(day)"
    }
}

/// Two drinks side by side: amounts, strength, volume and caffeine.
struct CompareDrinksView: View {
    @Environment(AppModel.self) var model
    @State var first: BeverageID = .cappuccino
    @State var second: BeverageID = .flatWhite

    var body: some View {
        let a = model.data.recipe(for: first)
        let b = model.data.recipe(for: second)
        Form {
            Section {
                Picker(L("compare.first"), selection: $first) { ForEach(BeverageID.allCases) { Text($0.name).tag($0) } }
                Picker(L("compare.second"), selection: $second) { ForEach(BeverageID.allCases) { Text($0.name).tag($0) } }
            }
            Section(L("compare.result")) {
                row(L("param.coffee"), a.coffeeML.map { L("unit.ml", $0) }, b.coffeeML.map { L("unit.ml", $0) })
                row(L("param.milk"), a.milkSeconds.map { L("unit.ml", a.approximateMilkML) }, b.milkSeconds.map { L("unit.ml", b.approximateMilkML) })
                row(L("param.water"), a.waterML.map { L("unit.ml", $0) }, b.waterML.map { L("unit.ml", $0) })
                row(L("param.aroma"), a.aroma?.title, b.aroma?.title)
                row(L("compare.volume"), L("unit.ml", a.approximateVolumeML), L("unit.ml", b.approximateVolumeML))
                row(L("caffeine.title"), L("caffeine.mg", CaffeineEstimator.milligrams(for: a)), L("caffeine.mg", CaffeineEstimator.milligrams(for: b)))
                row(L("knowledge.ratio"), DrinkKnowledge.ratio(a), DrinkKnowledge.ratio(b))
                row(L("compare.temperature"), a.spec.isCold ? L("compare.cold") : L("compare.hot"), b.spec.isCold ? L("compare.cold") : L("compare.hot"))
            }
            Section {
                Text(DrinkKnowledge.comparison(a, b)).font(.body)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("compare.title"))
    }

    private func row(_ title: String, _ left: String?, _ right: String?) -> some View {
        let none = L("compare.none")
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack {
                Text(left ?? none).frame(maxWidth: .infinity, alignment: .leading)
                Text(right ?? none).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(L("compare.spoken", first.name, left ?? none, second.name, right ?? none))
    }
}

struct GoalsView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let profile = model.activeProfile
        List(Goal.allCases) { goal in
            let progress = goal.progress(history: profile.history, favorites: profile.favorites, life: model.data.life)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(goal.title).font(.headline)
                    Spacer()
                    if progress >= goal.target {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success).accessibilityHidden(true)
                    }
                }
                Text(goal.detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                ProgressView(value: Double(progress), total: Double(goal.target)).tint(Theme.accent)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(goal.title)
            .accessibilityValue(progress >= goal.target ? L("goal.done") : L("goal.progress", progress, goal.target))
            .accessibilityHint(goal.detail)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("goals.title"))
    }
}

struct WeeklySummaryView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let summary = WeeklySummary.make(history: model.activeProfile.history)
        Form {
            Section {
                Text(summary.sentence).font(.body)
            }
            Section {
                LabeledContent(L("weekly.cupsLabel"), value: "\(summary.cups)")
                if let top = summary.topDrink { LabeledContent(L("weekly.topLabel"), value: top.name) }
                if let hour = summary.usualHour { LabeledContent(L("weekly.hourLabel"), value: L("caffeine.cutoff.hour", hour)) }
                LabeledContent(L("weekly.caffeineLabel"), value: L("caffeine.mg", summary.averageCaffeine))
            }
            Section {
                Toggle(L("weekly.notify"), isOn: Binding(get: { model.settings.weeklySummary },
                                                         set: { value in model.updateSettings { $0.weeklySummary = value } }))
            } footer: {
                Text(L("weekly.notify.footer"))
            }
        }
        .tint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("weekly.title"))
    }
}

/// Every cup with a note or a rating, and the notes kept on each bag.
struct TastingJournalView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let records = model.activeProfile.history.filter { model.data.life.ratings[$0.id] != nil }
        List {
            if records.isEmpty && model.data.beanProfiles.allSatisfy({ $0.notes.isEmpty }) {
                Text(L("journal.empty")).foregroundStyle(Theme.textSecondary)
            }
            Section(L("journal.cups")) {
                ForEach(records) { record in
                    let rating = model.data.life.ratings[record.id]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.recipe.displayName).font(.headline)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.textSecondary)
                        if let liked = rating?.liked { Text(liked ? L("rating.liked") : L("rating.disliked")).font(.subheadline) }
                        if let strength = rating?.strength { Text(strength.title).font(.subheadline) }
                        if let note = rating?.note, !note.isEmpty { Text(note).font(.body) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section(L("journal.beans")) {
                ForEach(model.data.beanProfiles.filter { !$0.notes.isEmpty }) { bean in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bean.name).font(.headline)
                        Text(bean.notes).font(.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("journal.title"))
    }
}
