import SwiftUI

struct MachineView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MachineStatusCard()
                    alarmsSection
                    if model.settings.linkKind == .demo { demoSection }
                    maintenanceSection
                    statisticsSection
                    toolsSection
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(L("tab.machine"))
            .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
            .navigationDestination(for: MachineRoute.self) { route in
                switch route {
                case .diagnostics: DiagnosticsView()
                case .statistics: StatisticsView()
                case .settings: MachineSettingsView()
                case .beans: BeansView()
                case .screenReader: MachineScreenReaderView()
                case .troubleshooting: TroubleshootingView()
                case .health: HealthStatusView()
                }
            }
        }
    }

    @ViewBuilder
    private var alarmsSection: some View {
        let alarms = model.snapshot.alarms
        if model.connection.isConnected, !alarms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("machine.alarms"))
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm)
                }
            }
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("machine.levels"))
            Text(L("machine.demo.note"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            let engine = model.demoLink?.engine ?? DemoMachineEngine()
            let _ = model.demoRevision
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                LevelGauge(title: L("level.water"), symbol: "drop.fill", level: engine.waterLevel)
                LevelGauge(title: L("level.beans"), symbol: "leaf.fill", level: engine.beanLevel)
                LevelGauge(title: L("level.grounds"), symbol: "trash.fill", level: engine.groundsLevel, warnWhenLow: false)
            }
            VStack(spacing: 10) {
                if model.snapshot.power == .off {
                    Button(L("action.turnOn")) { Task { await model.powerOn() } }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(L("demo.turnOff")) { Task { await model.powerOff() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(L("demo.refillWater")) { model.demo { $0.refillWater() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("demo.refillBeans")) { model.demo { $0.refillBeans() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("demo.emptyGrounds")) { model.demo { $0.emptyGrounds() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("demo.cleanCarafe")) { model.demo { $0.cleanMilkCarafe() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("demo.descale")) { model.demo { $0.completeDescaling() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("machine.maintenance"))
            NavigationLink(value: MachineRoute.health) {
                HStack(spacing: 14) {
                    Image(systemName: "heart.text.square.fill").font(.title3).foregroundStyle(Theme.accent).frame(width: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("health.title")).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(L("health.subtitle")).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                }
                .padding(14).frame(minHeight: 64).card()
            }
            .buttonStyle(.plain)
            ForEach(MaintenanceGuideID.allCases) { guide in
                NavigationLink(value: guide) {
                    HStack(spacing: 14) {
                        Image(systemName: guide.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guide.title).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(L("guide.duration", guide.minutes, guide.stepCount))
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    }
                    .padding(14)
                    .frame(minHeight: 64)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statisticsSection: some View {
        let completed = model.activeProfile.history.filter(\.completed)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("machine.statistics"))
            NavigationLink(value: MachineRoute.statistics) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("stats.total", completed.count)).font(.headline).foregroundStyle(Theme.textPrimary)
                        if let last = completed.first {
                            Text(L("stats.last", last.recipe.displayName, last.date.formatted(.relative(presentation: .named))))
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.forward").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                }
                .padding(14)
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private func toolLink(_ route: MachineRoute, title: String, symbol: String, hint: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 14)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("machine.tools"))
            toolLink(.settings, title: L("machineSettings.title"), symbol: "slider.horizontal.3", hint: L("machineSettings.hint"))
            toolLink(.beans, title: L("beans.title"), symbol: "leaf.circle.fill", hint: L("beans.hint"))
            toolLink(.screenReader, title: L("reader.title"), symbol: "text.viewfinder", hint: L("reader.hint"))
            toolLink(.troubleshooting, title: L("trouble.title"), symbol: "questionmark.circle.fill", hint: L("trouble.hint"))
            toolLink(.diagnostics, title: L("diagnostics.title"), symbol: "stethoscope", hint: L("diagnostics.hint"))
            Button(L("action.reconnect")) { model.reconnect() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}

enum MachineRoute: Hashable {
    case diagnostics, statistics, settings, beans, screenReader, troubleshooting, health
}

struct AlarmRow: View {
    let alarm: MachineAlarm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(alarm.title, systemImage: alarm.blocksBrewing ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.headline)
                .foregroundStyle(alarm.blocksBrewing ? Theme.danger : Theme.warning)
            Text(alarm.advice)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            if let guide = alarm.maintenanceGuide {
                NavigationLink(value: guide) { Text(L("action.openGuide", guide.title)) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
