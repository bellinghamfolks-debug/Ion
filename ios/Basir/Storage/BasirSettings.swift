// BasirSettings.swift
// Centralised user-preference store. Wraps UserDefaults for everything
// EXCEPT the Gemini API key (which goes into Keychain via
// KeychainStore.swift).
//
// Observable so SwiftUI views can react to settings changes.

import Foundation
import SwiftUI

@MainActor
final class BasirSettings: ObservableObject {
    static let shared = BasirSettings()

    // MARK: - Language
    @AppStorage("language_raw") private var languageRaw: String = AppLanguage.arabic.rawValue

    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .arabic }
        set { languageRaw = newValue.rawValue; objectWillChange.send() }
    }

    // MARK: - Speech / accessibility
    @AppStorage("speech_enabled") var speechEnabled: Bool = true
    @AppStorage("vibration_enabled") var vibrationEnabled: Bool = true
    @AppStorage("tts_rate") var ttsRate: Double = 1.0       // 0.5 .. 1.5
    @AppStorage("font_step") var fontStep: Int = 0          // 0 .. 4

    // MARK: - Appearance
    // "system" | "light" | "dark"
    @AppStorage("appearance") var appearance: String = "system"

    // MARK: - Privacy
    @AppStorage("privacy_mode") var privacyMode: Bool = false
    @AppStorage("auto_save_results") var autoSaveResults: Bool = true

    // MARK: - AI mode + quality presets
    @AppStorage("ai_mode") var aiMode: String = "direct"    // "direct" | "proxy"
    @AppStorage("quick_quality") var quickQuality: String = "balanced"
    @AppStorage("doc_quality") var docQuality: String = "best"
    @AppStorage("ai_server_url") var proxyURL: String = ""
    @AppStorage("ai_app_token") var proxyToken: String = ""

    // MARK: - Translation
    @AppStorage("translate_src") var translateSource: String = "auto"
    @AppStorage("translate_tgt") var translateTarget: String = "en"

    // MARK: - Emergency
    @AppStorage("emergency_contact") var emergencyContact: String = ""

    // Note: the Gemini API key is NOT here. Use:
    //   KeychainStore.geminiKey()
    //   KeychainStore.setGeminiKey(_:)

    private init() {}

    var isConfigured: Bool {
        if aiMode == "direct" {
            return !KeychainStore.geminiKey().isEmpty
        }
        return NetworkTransport.safeProxyEndpoint(from: proxyURL) != nil
    }

    /// Current Gemini routing and task-level execution policy. Every task
    /// has its own model candidates, thinking level, temperature, timeout,
    /// output budget, validation profile, and repair behavior.
    func policy(for task: TaskKind) -> AITaskPolicy {
        AITaskPolicyCatalog.policy(for: task)
    }

    func modelsForQuality(_ quality: String) -> [String] {
        AIModelRouter.models(for: quality)
    }

    func modelForQuality(_ quality: String) -> String {
        modelsForQuality(quality).first ?? "gemini-3.5-flash"
    }

    func modelsFor(task: TaskKind) -> [String] {
        policy(for: task).modelCandidates(
            quickQuality: quickQuality,
            documentQuality: docQuality
        )
    }

    func modelFor(task: TaskKind) -> String {
        modelsFor(task: task).first ?? "gemini-3.5-flash"
    }
}
