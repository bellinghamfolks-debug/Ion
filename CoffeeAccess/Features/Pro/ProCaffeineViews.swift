import Charts
import SwiftUI
import UIKit

/// Version 3 sections of the caffeine screen: health presets, what is still
/// in the body, a gradual reduction plan, Ramadan and the hourly chart.
struct CaffeinePlusSections: View {
    @Environment(AppModel.self) var model
    @State var planWeeks = 4
    @State var planTarget = 200

    var body: some View {
        let history = model.activeProfile.history
        let spilled = Set(model.data.life.pro.spilled)
        let remaining = CaffeineEstimator.remaining(history: history, spilled: spilled, decafBeans: model.decafBeanIDs)
        Section {
            LabeledContent(L("caffeine.inBody"), value: L("caffeine.mg", remaining))
            if let below = CaffeineEstimator.time(below: 50, history: history, spilled: spilled, decafBeans: model.decafBeanIDs) {
                Text(L("caffeine.below50", below.formatted(date: .omitted, time: .shortened))).font(.footnote)
            }
        } footer: { Text(L("caffeine.inBody.footer")) }

        Section {
            ForEach(CaffeineLimitPreset.allCases) { preset in
                Button {
                    model.updateSettings { $0.caffeineLimitMg = preset.rawValue }
                    Announcer.shared.announce(L("limit.set", preset.rawValue))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("limit.row", preset.title, preset.rawValue)).foregroundStyle(Theme.textPrimary)
                        Text(preset.source).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityAddTraits(model.settings.caffeineLimitMg == preset.rawValue ? .isSelected : [])
            }
        } header: { Text(L("limit.presets")) } footer: { Text(L("limit.footer")) }

        Section {
            if let plan = model.data.life.pro.reduction {
                LabeledContent(L("reduction.thisWeek"), value: L("caffeine.mg", plan.limit()))
                LabeledContent(L("reduction.week"), value: L("reduction.weekOf", min(plan.week() + 1, plan.weeks), plan.weeks))
                if plan.isFinished() { Text(L("reduction.finished", plan.targetMg)).font(.footnote) }
                Button(L("reduction.stop"), role: .destructive) { model.updateData { $0.life.pro.reduction = nil } }
            } else {
                Stepper(value: $planTarget, in: 0...400, step: 25) {
                    LabeledContent(L("reduction.target"), value: L("caffeine.mg", planTarget))
                }
                Stepper(value: $planWeeks, in: 2...12) {
                    LabeledContent(L("reduction.weeks"), value: "\(planWeeks)")
                }
                Button(L("reduction.start")) {
                    let average = Self.dailyAverage(history, spilled: spilled, decaf: model.decafBeanIDs)
                    let start = max(average, planTarget + 25)
                    model.updateData { $0.life.pro.reduction = ReductionPlan(startMg: start, targetMg: planTarget, weeks: planWeeks) }
                    Announcer.shared.announce(L("reduction.started", start, planTarget, planWeeks))
                }
            }
        } header: { Text(L("reduction.title")) } footer: { Text(L("reduction.footer")) }

        Section {
            Picker(L("ramadan.mode"), selection: model.binding(\.ramadanMode)) {
                Text(L("ramadan.auto")).tag(0)
                Text(L("ramadan.on")).tag(1)
                Text(L("ramadan.off")).tag(2)
            }
            if model.ramadanActive { Text(L("ramadan.advice")).font(.footnote) }
            Toggle(L("water.reminderToggle"), isOn: model.binding(\.waterReminder))
        } footer: { Text(L("ramadan.footer")) }

        Section {
            NavigationLink { HourlyChartView() } label: { Label(L("screen.hourly"), systemImage: "chart.bar.xaxis") }
            NavigationLink { MonthlyReportView() } label: { Label(L("screen.monthly"), systemImage: "calendar.badge.clock") }
        }
    }

    /// Average over the last 14 days that had cups.
    static func dailyAverage(_ history: [BrewRecord], spilled: Set<UUID>, decaf: Set<UUID>) -> Int {
        let start = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = history.filter { $0.completed && $0.date >= start && !spilled.contains($0.id) }
        let days = max(1, Set(recent.map { Calendar.current.startOfDay(for: $0.date) }).count)
        return recent.reduce(0) { $0 + CaffeineEstimator.milligrams(for: $1, decafBeans: decaf) } / days
    }
}

/// Cups by hour of day over the last month. Swift Charts gives VoiceOver an
/// audio graph of it.
struct HourlyChartView: View {
    @Environment(AppModel.self) var model

    struct Bar: Identifiable { let hour: Int; let cups: Int; var id: Int { hour } }

    var body: some View {
        let hours = CaffeineEstimator.byHour(model.activeProfile.history)
        let bars = hours.enumerated().map { Bar(hour: $0.offset, cups: $0.element) }
        let peak = bars.max { $0.cups < $1.cups }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("hourly.intro")).foregroundStyle(Theme.textSecondary)
                Chart(bars) { bar in
                    BarMark(x: .value(L("hourly.hour"), bar.hour), y: .value(L("hourly.cups"), bar.cups))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(L("hourly.at", bar.hour))
                        .accessibilityValue(L("hourly.cupsValue", bar.cups))
                }
                .chartXScale(domain: 0...23)
                .frame(height: 240)
                .padding(14)
                .card()
                if let peak, peak.cups > 0 {
                    Text(L("hourly.peak", peak.hour, peak.cups)).font(.headline)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("screen.hourly"))
    }
}

/// The last 30 days: cups, caffeine, beans, cost, savings, energy and care.
struct MonthlyReportView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let report = MonthlyReport.make(data: model.data, cafePrice: model.settings.cafePrice)
        ProForm(title: L("screen.monthly")) {
            Section {
                LabeledContent(L("monthly.cups"), value: "\(report.cups)")
                if let top = report.topDrink { LabeledContent(L("monthly.top"), value: top.name) }
                LabeledContent(L("monthly.caffeine"), value: L("caffeine.mg", report.averageCaffeine))
                LabeledContent(L("monthly.beans"), value: L("stock.grams", report.beansGrams))
            }
            Section {
                if let cost = report.homeCost {
                    LabeledContent(L("monthly.cost"), value: CostPerCup.text(cost))
                } else {
                    Text(L("monthly.noPrice")).font(.footnote)
                }
                if let savings = report.savings {
                    LabeledContent(L("monthly.savings"), value: CostPerCup.text(savings))
                }
                TextField(L("monthly.cafePrice"), value: model.binding(\.cafePrice), format: .number).keyboardType(.decimalPad)
            } header: { Text(L("monthly.money")) } footer: { Text(L("monthly.money.footer")) }
            Section {
                LabeledContent(L("monthly.energy"), value: L("monthly.kwh", report.energyKWh))
                LabeledContent(L("monthly.energyCost"), value: CostPerCup.text(report.energyKWh * model.data.life.pro.electricityPrice))
                TextField(L("monthly.electricityPrice"), value: model.proBinding(\.electricityPrice), format: .number).keyboardType(.decimalPad)
            } header: { Text(L("monthly.energyHeader")) } footer: { Text(L("monthly.energy.footer")) }
            Section {
                LabeledContent(L("monthly.care"), value: "\(report.careDone)")
                LabeledContent(L("monthly.alarms"), value: "\(report.alarms)")
            }
        }
    }
}
