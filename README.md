# Basir — iOS

> عينك الذكية في كل مكان · Your smart eye, everywhere

Basir is an iOS assistant for blind and low-vision users. It uses
Google Gemini for scene description, document reading, translation,
voice conversation, math extraction, and emergency communication.

This repository is the **iOS port** of Basir. The Android version
lives in a separate repository.

- **Version**: 0.2
- **Target**: iOS 17.0+
- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Source files**: 31 Swift files, ~4,190 lines
- **Dependencies**: none (pure Apple frameworks)

---

## Repository layout

```
.
├── codemagic.yaml           cloud CI/CD for macOS-less developers
├── project.yml              XcodeGen specification
├── README.md                this file
├── Basir/                   main iOS app target
│   ├── BasirApp.swift          @main
│   ├── ContentView.swift       root TabView
│   ├── Info.plist              privacy descriptions
│   ├── Helpers/L10n.swift      bilingual t(arabic:english:)
│   ├── Networking/
│   │   ├── GeminiClient.swift           async/await Gemini REST client
│   │   ├── GeminiPrompts.swift          prompts + math extraction
│   │   └── UserFriendlyErrorMapper.swift
│   ├── Storage/
│   │   ├── BasirSettings.swift          @AppStorage preferences
│   │   └── KeychainStore.swift          hardware-encrypted API key
│   ├── Speech/
│   │   ├── SpeechSynthesizer.swift      AVSpeechSynthesizer wrapper
│   │   └── SpeechRecognizer.swift       SFSpeechRecognizer wrapper
│   ├── Location/LocationService.swift   CLLocationManager for emergency
│   ├── Memory/ArchiveStore.swift        Codable JSON personal data
│   ├── Documents/PdfReader.swift        PDFKit text extraction
│   └── Views/
│       ├── HomeView · VisionView · DocumentsView · MoreView   (4 tabs)
│       ├── AskBasirView · TranslateView · DescribeImageView
│       ├── MathExtractView · WalkingModeView · VoiceConversationView
│       ├── DocumentConvertView · EmergencyView
│       ├── MemoryView · ArchiveView
│       ├── SettingsView · AboutView · LegalScreens
└── ShareExtension/          system share-sheet target (separate target)
    ├── ShareViewController.swift
    └── Info.plist
```

---

## Features

| Feature | Status |
|---|:---:|
| Ask Basir (text Q&A + voice dictation) | ✅ |
| Continuous voice conversation | ✅ |
| Translation between 20 languages | ✅ |
| Math extraction (Arabic + English with LaTeX) | ✅ |
| Image description (4 modes) | ✅ |
| Walking mode | ✅ |
| PDF conversion + translation (≤60 pages) | ✅ |
| Emergency SMS + location share | ✅ |
| Personal memory (people / products / places) | ✅ |
| Archive of past results with filtering | ✅ |
| Share extension (receive from other apps) | ✅ |
| Settings + Keychain-encrypted Gemini key | ✅ |
| Terms of Service + Privacy Policy (v2) | ✅ |
| Bilingual Arabic/English UI with RTL | ✅ |
| VoiceOver headings + announcements | ✅ |

### What iOS itself prevents

Some Android features don't translate cleanly because iOS enforces
stricter platform rules. We work around each where possible.

| Android feature | iOS reality | Workaround |
|---|---|---|
| Background PDF conversion for hours | Foreground-only, ~30s when backgrounded | Cap single-shot at 60 pages; user keeps app open |
| Silent SMS sending | Not allowed | MFMessageComposeViewController; user taps Send |
| Cross-app file access without scoping | Security-scoped URLs only | Copy to sandbox before processing |
| Background camera capture | Not allowed | Tap-per-frame walking mode |

---

## Building locally (requires macOS + Xcode 15+)

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Open in Xcode
open Basir.xcodeproj

# 4. Build & run on iOS Simulator
# Cmd+R in Xcode, or:
xcodebuild build \
  -project Basir.xcodeproj \
  -scheme Basir \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

---

## Building in the cloud (no Mac needed)

This repo includes `codemagic.yaml` for **Codemagic** — hosted macOS
build instances. Free tier: 500 build minutes/month.

1. Sign in at [codemagic.io](https://codemagic.io) with GitHub.
2. **Add application** → select this repository.
3. Codemagic auto-detects `codemagic.yaml` and offers these workflows:
   - `ios-simulator-build` (auto-triggered on push to main/master/develop/feature/**)
   - `ios-unsigned-ipa` (auto-triggered on push — builds the iPhone arm64 `.ipa`)
   - `ios-sideload-ipa` (auto-triggered on push — IPA for **free Apple ID 7-day install**, Share Extension stripped; see [`INSTALL-iPhone-7days.md`](INSTALL-iPhone-7days.md))
   - `ios-app-store-build` (commented out — uncomment after uploading Apple Developer credentials)
4. First run will take 4-6 minutes. Subsequent runs cache better.

Artifacts:
- Simulator build → `Basir.app` (for iOS Simulator only)
- Unsigned IPA → `Basir-unsigned.ipa` (proves Release links for arm64)
- Sideload IPA → `Basir-sideload.ipa` (install on a real iPhone with a free Apple ID via Sideloadly/AltStore — valid 7 days)
- Signed IPA (App Store workflow) → TestFlight upload

---

## App Store submission (later)

1. Buy an Apple Developer Program membership ($99/year).
2. Create an App Store Connect app entry for bundle id `com.basir.ai`.
3. Generate an iOS Distribution certificate + provisioning profile.
4. Upload them to Codemagic (Teams → Integrations).
5. Uncomment the `ios-app-store-build` workflow in `codemagic.yaml`.
6. Push to `release/ios` branch → automatic TestFlight upload.
7. Add internal testers in App Store Connect → TestFlight tab.
8. After internal testing: submit to App Store Review.

---

## Security

- Gemini API key stored in **iOS Keychain** with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Backed by the
  Secure Enclave on supported devices (iPhone 5s+).
- `NSAllowsArbitraryLoads=false` — HTTPS only in release.
- No analytics SDKs, no ad SDKs, no third-party dependencies.
- Personal data (memory + archive) stored locally in
  `Documents/basir_archive.json`. No cloud sync.

---

## Privacy

The app declares the minimum iOS permissions required:

| Permission | Used for | Asked when |
|---|---|---|
| Camera | Walking mode + describe image | First image capture |
| Microphone | Voice dictation + conversation | First voice action |
| Speech Recognition | Voice dictation + conversation | First voice action |
| Location (When in Use) | Emergency mode location share | First emergency action |
| Photo Library | Pick existing image to analyze | First gallery pick |

No background location, no always-on permissions, no analytics.

---

## Contact

- 📧 ubdallahalrashdee@gmail.com
- 👤 عبدالله الراشدي · Abdullah Al-Rashidi

---

## License

All rights reserved. Contact the developer for licensing inquiries.
