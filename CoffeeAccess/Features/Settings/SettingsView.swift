import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) var model
    @State var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
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
                }
            }
            .tint(Theme.accent)
            .navigationTitle(L("tab.settings"))
            .confirmationDialog(L("settings.forgetMachine.confirm"), isPresented: $confirmForget, titleVisibility: .visible) {
                Button(L("settings.forgetMachine"), role: .destructive) {
                    model.bluetoothLink?.forgetMachine()
                    model.reconnect()
                }
                Button(L("action.cancel"), role: .cancel) {}
            }
        }
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
