import SwiftUI

struct MachineView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let health = MachineHealth(model: model)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MachineHero()
                    MachineStatusCard()
                    NavigationLink(value: MachineRoute.health) { HealthOverviewCard(health: health) }
                        .buttonStyle(.plain)
                    if let machine = model.data.life.activeMachine {
                        NavigationLink(value: MachineRoute.machines) {
                            NavigationRowCard(title: machine.name, subtitle: L("machines.current", model.data.life.machines.count), symbol: "cup.and.saucer")
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: MachineRoute.setup) {
                            NavigationRowCard(title: L("setup.title"), subtitle: L("setup.subtitle"), symbol: "sparkles")
                        }
                        .buttonStyle(.plain)
                    }
                    CareForecastCard()
                    closerLook(health)
                    alarmsSection
                    beanCard
                    weekTiles
                    manualCard
                    if model.settings.linkKind == .demo { demoSection }
                    maintenanceSection
                    toolsSection
                }
                .padding(20)
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
                case .help: HelpView()
                case .setup: MachineSetupView()
                case .machines: MachinesView()
                case .hardness: HardnessTestView()
                case .descale: DescaleRunView()
                case .signals: SignalLookupView()
                case .tour: MachineTourView()
                }
            }
        }
    }

    private func closerLook(_ health: MachineHealth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("health.closerLook"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(health.items) { item in
                    NavigationLink(value: item.guide) { HealthTile(item: item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// The bean bag in use, as on the machine's Bean Adapt.
    private var beanCard: some View {
        let bean = model.data.activeBean
        return NavigationLink(value: MachineRoute.beans) {
            HStack(spacing: 16) {
                BeanBagIllustration(roast: bean?.roast ?? .medium)
                    .frame(width: 84)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceRaised))
                VStack(alignment: .leading, spacing: 6) {
                    Label(bean == nil ? L("bean.card.none") : L("bean.card.set"), systemImage: "leaf.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(bean?.name ?? L("beans.title"))
                        .font(.display(.title2, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(bean == nil ? L("action.add") : L("action.edit"))
                        .font(.subheadline.weight(.medium))
                        .underline()
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("beans.title"))
            .accessibilityValue(bean.map { L("bean.card.spoken", $0.name, $0.recommendedGrind) } ?? L("bean.card.none"))
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
    }

    /// "Brewed this week" and the free Bean Adapt slots, side by side.
    private var weekTiles: some View {
        let totals = DrinkStatistics(history: model.activeProfile.history).weekTotals()
        let difference = totals.this - totals.previous
        let slots = BeanProfile.maxCount - model.data.beanProfiles.count
        return HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: MachineRoute.statistics) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("stats.brewedThisWeek"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(totals.this)")
                        .font(.system(.largeTitle).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Label(difference == 0 ? L("stats.sameAsLastWeek")
                          : (difference > 0 ? L("stats.moreThanLastWeek", difference) : L("stats.lessThanLastWeek", -difference)),
                          systemImage: difference >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.sky))
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                .card()
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            NavigationLink(value: MachineRoute.beans) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent))
                        .accessibilityHidden(true)
                    Text(L("beans.slots", slots))
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                .card()
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }

    /// Manuals: the in-app quick start and the step-by-step care guides.
    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MachineIllustration()
                    .frame(width: 64)
                    .accessibilityHidden(true)
                Text(L("manual.title"))
                    .font(.display(.title3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            NavigationLink(value: MachineRoute.help) { manualRow(L("manual.quickStart"), symbol: "book") }
                .buttonStyle(.plain)
            NavigationLink(value: MaintenanceGuideID.descaling) { manualRow(L("manual.care"), symbol: "wrench.and.screwdriver") }
                .buttonStyle(.plain)
            NavigationLink(value: MachineRoute.troubleshooting) { manualRow(L("trouble.title"), symbol: "questionmark.circle") }
                .buttonStyle(.plain)
        }
        .padding(18)
        .card()
    }

    private func manualRow(_ title: String, symbol: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Rectangle().fill(Theme.textPrimary).frame(width: 1, height: 22).accessibilityHidden(true)
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceRaised))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
            ForEach(MaintenanceGuideID.allCases) { guide in
                NavigationLink(value: guide) {
                    NavigationRowCard(title: guide.title,
                                      subtitle: L("guide.duration", guide.minutes, guide.stepCount),
                                      symbol: guide.symbol)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toolLink(_ route: MachineRoute, title: String, symbol: String, hint: String) -> some View {
        NavigationLink(value: route) {
            NavigationRowCard(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("machine.tools"))
            toolLink(.settings, title: L("machineSettings.title"), symbol: "slider.horizontal.3", hint: L("machineSettings.hint"))
            toolLink(.descale, title: L("descale.run.title"), symbol: "timer", hint: L("descale.run.subtitle"))
            toolLink(.hardness, title: L("hardness.title"), symbol: "testtube.2", hint: L("hardness.subtitle"))
            toolLink(.signals, title: L("signal.title"), symbol: "lightbulb.max", hint: L("signal.hint"))
            toolLink(.tour, title: L("tour.title"), symbol: "figure.walk.motion", hint: L("tour.hint"))
            toolLink(.machines, title: L("machines.title"), symbol: "square.stack.3d.up", hint: L("machines.hint"))
            toolLink(.setup, title: L("setup.title"), symbol: "sparkles", hint: L("setup.subtitle"))
            toolLink(.statistics, title: L("machine.statistics"), symbol: "chart.bar", hint: L("stats.hint"))
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
    case diagnostics, statistics, settings, beans, screenReader, troubleshooting, health, help
    case setup, machines, hardness, descale, signals, tour
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
