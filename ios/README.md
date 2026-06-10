# Basir for iOS | بصير لنظام iOS

Current app version: **4.4.0**
Build number: **64**
Target: **iOS 17.0 or later**
Language: **Swift 5.9+**
UI: **SwiftUI**

## Interface and accessibility

- A shared semantic design system keeps cards, status messages, controls, spacing, and colors consistent across every screen.
- All primary interface copy is bilingual Arabic and English and changes with the in-app language setting.
- Dynamic Type, dark mode, increased contrast, right-to-left layout, meaningful VoiceOver labels, and minimum touch-target sizes are supported throughout the app.
- Long legal documents are divided into navigable headings, paragraphs, and bullet points instead of one inaccessible text block.
- The Share Extension has its own accessible confirmation screen and no longer depends on an unrelated compose interface or a storyboard.

## Current feature set

### Talk

- Ask Basir by typing or one-shot voice dictation.
- Translate text between supported languages.

### Vision

- Detailed image or scene description.
- Focused image alt text.
- Screenshot reading.
- Currency and receipt assistance.
- Math extraction with spoken notation and LaTeX for review.
- One-shot walking description from a captured image.

### Documents

- Select a PDF of up to 500 pages, a Word file (DOCX), a PowerPoint file (PPTX), or a TXT or CSV file.
- Extract readable text locally on the device. PDF uses Apple's PDFKit; DOCX uses Basir's `DocxReader`; PPTX uses Basir's `PptxReader`. Both DOCX and PPTX rely on a built-in zero-dependency ZIP reader (`Documents/ZipReader.swift`) that does not require any external library.
- PDF and scanned-image conversion is isolated one page at a time. A failed page cannot erase the surrounding pages. The screen shows page-level progress, supports true cancellation of the active request, and preserves completed work as a clearly labelled partial result.
- Each PDF page combines its local text layer, a high-resolution page image, a strict structured-output schema, validation of critical numbers and identifiers, and a second-pass retry when needed. A failed digital page falls back to local text; a failed scanned page is embedded as an accessible page image instead of disappearing.
- Optional math mode (`Convert math inside the document`) instructs Gemini to render every equation as spoken text plus a `[LaTeX:]` trailer, using the same vocabulary as the dedicated math card.
- Display the result as copyable, shareable text.
- Optionally export the result as a real Word file (DOCX). The writer creates genuine headings, lists, tables, hyperlinks, mixed RTL/LTR runs, page breaks, rich text, and images with alternative text.
- Ask follow-up questions about the last converted document. The document and question remain in the untrusted data channel, separate from the model's system instructions.

### More

- Continuous voice conversation.
- Help-message preparation with optional precise map coordinates shown for review before sending.
- Local saved items for people, products, medications, and places.
- Local results archive and optional activity history.
- Settings, About, Terms and Conditions, and Privacy Policy.

## Connection behavior

iOS now supports the same two connection modes as Android:

- **Direct mode** — HTTPS requests go from the device to Google Gemini using a user-provided API key stored in the iOS Keychain. The default for new installs.
- **Proxy mode** — requests go through a user-configured HTTPS proxy server that holds the Gemini API key. The shared wire format matches `server/index.js` and Android's `ProxyAiProvider`, so a single self-hosted proxy can serve both apps. An optional shared client token can be sent in the `X-Basir-Client-Token` header.

The active mode and proxy URL/token are configurable from Settings → AI connection mode. iOS does not validate the proxy operator's identity or policy — the user is responsible for choosing a server they trust.

Content selected for an AI task is sent to Google Gemini (direct) or to the configured proxy (proxy). Review the in-app Privacy Policy before using personal, confidential, or sensitive content.

## Safety behavior

- AI output may be incorrect, incomplete, or delayed.
- Walking mode describes one image and is not an independent mobility tool.
- Help messages are never sent automatically. The system message composer opens so the user can review the recipient, text, and location and then tap Send.
- Basir does not contact official emergency services.

## Build with XcodeGen

The repository includes `ios/project.yml`.

1. Install Xcode 15 or later.
2. Install XcodeGen.
3. From the `ios` folder, run `xcodegen generate`.
4. Open the generated Xcode project.
5. Set a valid development team and unique bundle identifiers for the app and share extension.
6. Test permissions, VoiceOver, and real-device camera, microphone, speech recognition, location, and message-composer behavior.

## Privacy and App Store preparation

Before submission:

- Publish a public privacy-policy URL matching the in-app policy.
- Complete App Privacy details for the app and all third-party processing.
- Keep the privacy-policy URL and support contact functional.
- Review the app’s Gemini use against Google’s current terms and licensing restrictions.
- Obtain final legal review in Saudi Arabia.

## Source map

- `Basir/ContentView.swift`: root tabs.
- `Basir/Design/BasirDesignSystem.swift`: shared visual language, controls, result cards, status banners, and accessible screen containers.
- `Basir/Views`: user-facing screens and bilingual interface copy.
- `Basir/Networking/AITaskPolicy.swift`: the 23-task execution-policy catalogue, model routing, thinking levels, budgets, retries, and validation profiles.
- `Basir/Networking/GeminiClient.swift`: hardened direct Gemini client, current structured-output transport, model fallback, and usage parsing.
- `Basir/Networking/GeminiPrompts.swift`: central trusted prompt catalogue and randomized untrusted-data envelopes.
- `Basir/Networking/AIResponseSchemas.swift`: bounded JSON schemas for structured visual, document, OCR, table, medical, and legal tasks.
- `Basir/Networking/AIResponseValidator.swift`: semantic validation, critical-value preservation, safety checks, and screen-reader rendering.
- `Basir/Networking/AIEngineMetrics.swift`: privacy-preserving local execution metrics with no prompt, document, image, or response content.
- `Basir/Helpers/StructuredDocConverter.swift`: page-isolated conversion, validation, retry, and fallbacks.
- `Basir/Documents/DocxWriter.swift`: accessible OOXML generation.
- `BasirTests`: prompt, networking, and DOCX regression tests.
- `scripts/verify_project.py`: repository safety and parser checks.
- `Basir/Storage/KeychainStore.swift`: API-key storage.
- `Basir/Memory/ArchiveStore.swift`: local saved data and history.
- `Basir/Views/LegalScreens.swift`: in-app legal documents.
- `ShareExtension`: share-extension target.
