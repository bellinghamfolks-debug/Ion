import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) var model
    @State var confirmForget = false

    var body: some View {
        NavigationStack {
            SettingsLockGate {
                settingsForm
            }
        }
    }

    private var settingsForm: some View {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Theme.profileColors[model.activeProfile.colorIndex % Theme.profileColors.count])
                            .frame(width: 56, height: 56)
                            .overlay(Text(String(model.activeProfile.name.prefix(1))).font(.title2.bold()).foregroundStyle(.white))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.data.guestMode ? L("guest.title") : model.activeProfile.name)
                                .font(.display(.title2, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(L("account.subtitle"))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    NavigationLink { StatisticsView() } label: {
                        Label(L("account.habits"), systemImage: "chart.bar")
                    }
                    NavigationLink { CoffeeJourneyView() } label: {
                        Label(L("journey.title"), systemImage: "sparkles")
                    }
                    NavigationLink { BeansView() } label: {
                        Label(L("beans.title"), systemImage: "leaf")
                    }
                    NavigationLink { GoalsView() } label: { Label(L("goals.title"), systemImage: "flag.checkered") }
                    NavigationLink { WeeklySummaryView() } label: { Label(L("weekly.title"), systemImage: "calendar") }
                    NavigationLink { TastingJournalView() } label: { Label(L("journal.title"), systemImage: "book") }
                    NavigationLink { CaffeineView() } label: { Label(L("caffeine.title"), systemImage: "bolt.heart") }
                    NavigationLink { HouseholdView() } label: { Label(L("family.title"), systemImage: "person.2") }
                    NavigationLink { ScheduleListView() } label: { Label(L("schedule.title"), systemImage: "alarm") }
                    NavigationLink { CompareDrinksView() } label: { Label(L("compare.title"), systemImage: "arrow.left.arrow.right") }
                    NavigationLink { GlobalSearchView() } label: { Label(L("globalSearch.title"), systemImage: "magnifyingglass") }
                    ProLinks([(.monthly, "calendar.badge.clock"), (.organizer, "tag"), (.combos, "square.stack.3d.down.right"),
                              (.cups, "cup.and.saucer"), (.teaTimer, "timer")])
                }

                Group {
                Section {
                    ProLinks([(.accessibility3, "accessibility"), (.voPractice, "hand.tap")])
                } header: {
                    Text(L("settings.v3.accessibility"))
                }

                Section {
                    Toggle(L("settings.offlineQueue"), isOn: model.binding(\.offlineQueue))
                    Toggle(L("settings.cupPrewarm"), isOn: model.binding(\.cupPrewarm))
                    Toggle(L("settings.quietReconnect"), isOn: model.binding(\.quietReconnect))
                    Toggle(L("settings.leftOn"), isOn: model.binding(\.leftOnReminder))
                    Toggle(L("settings.followProfile"), isOn: model.binding(\.followMachineProfile))
                    Toggle(L("settings.locationSwitch"), isOn: model.binding(\.locationSwitch))
                    Toggle(L("settings.waterReminder"), isOn: model.binding(\.waterReminder))
                } header: {
                    Text(L("settings.v3.smart"))
                } footer: {
                    Text(L("settings.v3.smart.footer"))
                }

                Section {
                    ProLinks([(.backup, "externaldrive"), (.historyEditor, "clock.arrow.circlepath"), (.privacy, "hand.raised"),
                              (.children, "figure.and.child.holdinghands")])
                } header: {
                    Text(L("settings.v3.data"))
                }

                Section {
                    ProLinks([(.academy, "graduationcap"), (.glossary, "character.book.closed"), (.whatsNew, "sparkles"), (.report, "ladybug")])
                } header: {
                    Text(L("settings.v3.learn"))
                }
                }

                Section {
                    Picker(L("settings.connection"), selection: linkBinding) {
                        ForEach(MachineLinkKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Text(model.settings.linkKind.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    LabeledContent(L("settings.status"), value: model.connection.title)
                    if model.settings.linkKind == .bluetooth {
                        Button(L("settings.forgetMachine"), role: .destructive) { confirmForget = true }
                    }
                } header: {
                    Text(L("settings.machine"))
                }

                Section(L("settings.profiles")) {
                    ForEach(model.data.profiles) { profile in
                        NavigationLink {
                            ProfileEditor(profileID: profile.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Theme.profileColors[profile.colorIndex % Theme.profileColors.count])
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                                Text(profile.name)
                                Spacer()
                                if profile.id == model.data.activeProfileID {
                                    Text(L("settings.profile.active")).font(.footnote).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                Section(L("settings.brewing")) {
                    Toggle(L("settings.confirm"), isOn: settingBinding(\.confirmBeforeBrewing))
                    Toggle(L("settings.guest"), isOn: Binding(get: { model.data.guestMode }, set: { model.setGuestMode($0) }))
                    Toggle(L("settings.prebrew"), isOn: settingBinding(\.preBrewReminders))
                    Toggle(L("settings.carafe"), isOn: settingBinding(\.carafeCleanPrompt))
                    Toggle(L("settings.liveActivities"), isOn: settingBinding(\.liveActivities))
                }

                Section {
                    Toggle(L("settings.simpleMode"), isOn: settingBinding(\.simpleMode))
                    Toggle(L("settings.soundCues"), isOn: settingBinding(\.soundCues))
                    Toggle(L("settings.quantityTones"), isOn: settingBinding(\.quantityTones))
                    Toggle(L("settings.timeTheme"), isOn: settingBinding(\.timeOfDayTheme))
                } header: {
                    Text(L("settings.experience"))
                } footer: {
                    Text(L("settings.experience.footer"))
                }

                Section {
                    Toggle(L("settings.icloud"), isOn: settingBinding(\.iCloudSync))
                    if model.settings.iCloudSync, let last = CloudSync.shared.lastSyncText {
                        LabeledContent(L("settings.icloud.last"), value: last)
                    }
                } header: {
                    Text(L("settings.icloud.header"))
                } footer: {
                    Text(L("settings.icloud.footer"))
                }

                Section {
                    Toggle(L("settings.notifyReady"), isOn: settingBinding(\.notifyWhenReady))
                    Toggle(L("reminder.brewingUnitWeekly.title"), isOn: settingBinding(\.remindBrewingUnitWeekly))
                    Toggle(L("reminder.carafeDaily.title"), isOn: settingBinding(\.remindCarafeDaily))
                    Toggle(L("reminder.filterMonthly.title"), isOn: settingBinding(\.remindFilterMonthly))
                } header: {
                    Text(L("settings.notifications"))
                } footer: {
                    Text(L("settings.notifications.footer"))
                }

                Section {
                    Toggle(L("settings.announcePhases"), isOn: settingBinding(\.announcePhases))
                    Toggle(L("settings.announceProgress"), isOn: settingBinding(\.announceProgress))
                    Toggle(L("settings.announceAlarms"), isOn: settingBinding(\.announceAlarms))
                    Toggle(L("settings.haptics"), isOn: settingBinding(\.haptics))
                    Toggle(L("settings.speakWithoutVoiceOver"), isOn: settingBinding(\.speakWithoutVoiceOver))
                } header: {
                    Text(L("settings.feedback"))
                } footer: {
                    Text(L("settings.feedback.footer"))
                }

                Section {
                    Button(L("settings.language")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: {
                    Text(L("settings.language.footer"))
                }

                Section(L("settings.about")) {
                    NavigationLink(L("about.title")) { AboutView() }
                    NavigationLink(L("accessibility.title")) { AccessibilityStatementView() }
                    NavigationLink(L("help.title")) { HelpView() }
                    NavigationLink(L("trouble.title")) { TroubleshootingView() }
                }
            }
            .tint(Theme.accent)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("tab.settings"))
            .confirmationDialog(L("settings.forgetMachine.confirm"), isPresented: $confirmForget, titleVisibility: .visible) {
                Button(L("settings.forgetMachine"), role: .destructive) {
                    model.bluetoothLink?.forgetMachine()
                    model.reconnect()
                }
                Button(L("action.cancel"), role: .cancel) {}
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { HelpButton(topic: .settings) } }
    }

    private var linkBinding: Binding<MachineLinkKind> {
        Binding(get: { model.settings.linkKind }, set: { model.switchLink(to: $0) })
    }

    private func settingBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}

struct ProfileEditor: View {
    @Environment(AppModel.self) var model
    let profileID: Int
    @State var name = ""

    init(profileID: Int) {
        self.profileID = profileID
    }

    private var profile: UserProfile? { model.data.profiles.first { $0.id == profileID } }

    var body: some View {
        Form {
            Section(L("profile.name")) {
                TextField(L("profile.name"), text: $name)
                    .submitLabel(.done)
                    .onSubmit { model.renameProfile(profileID, to: name) }
                Button(L("action.save")) {
                    model.renameProfile(profileID, to: name)
                    Announcer.shared.announce(L("announce.saved"))
                }
            }
            Section(L("profile.color")) {
                ForEach(Theme.profileColors.indices, id: \.self) { index in
                    Button {
                        model.setProfileColor(profileID, colorIndex: index)
                    } label: {
                        HStack {
                            Circle().fill(Theme.profileColors[index]).frame(width: 28, height: 28)
                            Text(L("profile.color.\(index)"))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if profile?.colorIndex == index { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                    .accessibilityAddTraits(profile?.colorIndex == index ? .isSelected : [])
                }
            }
            Section {
                if model.data.activeProfileID != profileID {
                    Button(L("profile.makeActive")) { model.selectProfile(profileID) }
                }
                LabeledContent(L("profile.favoritesCount"), value: "\(profile?.favorites.count ?? 0)")
                LabeledContent(L("profile.customCount"), value: "\(profile?.personalDefaults.count ?? 0)")
            }
        }
        .navigationTitle(profile?.name ?? "")
        .onAppear { name = profile?.name ?? "" }
    }
}
