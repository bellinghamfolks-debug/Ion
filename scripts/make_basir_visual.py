from pathlib import Path
import plistlib

root = Path("ios")

# Independent visual-edition identifiers.
project = root / "project.yml"
text = project.read_text()
text = text.replace("PRODUCT_BUNDLE_IDENTIFIER: com.basir.ai.share", "PRODUCT_BUNDLE_IDENTIFIER: com.basir.visual.share")
text = text.replace("PRODUCT_BUNDLE_IDENTIFIER: com.basir.ai.tests", "PRODUCT_BUNDLE_IDENTIFIER: com.basir.visual.tests")
text = text.replace("PRODUCT_BUNDLE_IDENTIFIER: com.basir.ai", "PRODUCT_BUNDLE_IDENTIFIER: com.basir.visual")
project.write_text(text)

for rel in [
    "Basir/Basir.entitlements",
    "ShareExtension/BasirShare.entitlements",
    "Basir/Helpers/ShareInbox.swift",
    "ShareExtension/ShareViewController.swift",
]:
    path = root / rel
    if path.exists():
        path.write_text(path.read_text().replace("group.com.basir.shared", "group.com.basir.visual.shared"))

# Host app metadata and Open In file registrations.
info_path = root / "Basir/Info.plist"
with info_path.open("rb") as f:
    info = plistlib.load(f)
info["CFBundleDisplayName"] = "بصير المرئي"
info["CFBundleShortVersionString"] = "4.4.1"
info["CFBundleVersion"] = "65"
info["CFBundleURLTypes"] = [{
    "CFBundleURLName": "com.basir.visual.share",
    "CFBundleTypeRole": "Editor",
    "CFBundleURLSchemes": ["basirvisual"],
}]
info["LSSupportsOpeningDocumentsInPlace"] = True
info["CFBundleDocumentTypes"] = [
    {"CFBundleTypeName": "Basir Images", "CFBundleTypeRole": "Editor", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.image"]},
    {"CFBundleTypeName": "Basir PDF Documents", "CFBundleTypeRole": "Editor", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["com.adobe.pdf"]},
    {"CFBundleTypeName": "Basir Text Documents", "CFBundleTypeRole": "Editor", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.plain-text", "public.comma-separated-values-text", "public.rtf"]},
    {"CFBundleTypeName": "Basir Office Documents", "CFBundleTypeRole": "Editor", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["org.openxmlformats.wordprocessingml.document", "org.openxmlformats.presentationml.presentation"]},
]
with info_path.open("wb") as f:
    plistlib.dump(info, f, sort_keys=False)

share_info_path = root / "ShareExtension/Info.plist"
with share_info_path.open("rb") as f:
    share_info = plistlib.load(f)
share_info["CFBundleDisplayName"] = "بصير المرئي"
share_info["CFBundleShortVersionString"] = "4.4.1"
share_info["CFBundleVersion"] = "65"
with share_info_path.open("wb") as f:
    plistlib.dump(share_info, f, sort_keys=False)

# No deliberate accessibility exclusion in this edition.
# Keep the platform and source project's normal VoiceOver behavior unchanged.
# Do not hide the hierarchy, suppress announcements, or replace accessibility APIs.
# CI sync marker: neutral-accessibility build.

# Support direct file:// Open In without replacing the existing ShareInbox implementation.
(root / "Basir/Helpers/BasirVisualFileOpen.swift").write_text(r'''import Foundation

@MainActor
extension ShareInbox {
    func handleVisualExternalURL(_ url: URL) {
        if !url.isFileURL { handle(url); return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let images: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp"]
        let texts: Set<String> = ["txt", "csv", "md", "markdown", "json", "xml", "html", "htm", "log", "rtf"]
        let docs: Set<String> = ["pdf", "docx", "pptx"]
        guard images.contains(ext) || texts.contains(ext) || docs.contains(ext) else { return }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else { return }

        let task = images.contains(ext) ? "describe_image" : (docs.contains(ext) ? "convert" : "ask")
        let destination = container.appendingPathComponent("share-\(task)-\(UUID().uuidString).\(ext)")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            pending = Incoming(task: task, fileURL: destination, fileExtension: ext)
        } catch { }
    }
}
''')

app = root / "Basir/BasirApp.swift"
source = app.read_text().replace(
    ".onOpenURL { shareInbox.handle($0) }",
    ".onOpenURL { shareInbox.handleVisualExternalURL($0) }",
)
app.write_text(source)

shared_item = root / "Basir/Views/SharedItemView.swift"
source = shared_item.read_text()
source = source.replace(
    '["jpg", "jpeg", "png", "heic", "heif", "gif"].contains(incoming.fileExtension)',
    '["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp"].contains(incoming.fileExtension)',
)
source = source.replace(
    'private var isText: Bool { incoming.fileExtension == "txt" }',
    'private var isText: Bool { ["txt", "csv", "md", "markdown", "json", "xml", "html", "htm", "log", "rtf"].contains(incoming.fileExtension) }',
)
source = source.replace(
    'private var isDocument: Bool { incoming.fileExtension == "pdf" }',
    'private var isDocument: Bool { ["pdf", "docx", "pptx"].contains(incoming.fileExtension) }',
)
shared_item.write_text(source)

# Share Extension identifiers only. Accessibility behavior remains untouched.
share_controller = root / "ShareExtension/ShareViewController.swift"
source = share_controller.read_text()
source = source.replace('components.scheme = "basir"', 'components.scheme = "basirvisual"')
source = source.replace('domain: "com.basir.ai.share"', 'domain: "com.basir.visual.share"')
share_controller.write_text(source)

# Hard build-time invariants.
assert "PRODUCT_BUNDLE_IDENTIFIER: com.basir.visual" in project.read_text()
assert "handleVisualExternalURL" in app.read_text()
assert "group.com.basir.visual.shared" in (root / "Basir/Basir.entitlements").read_text()
assert ".accessibilityHidden(true)" not in (root / "Basir/ContentView.swift").read_text()
assert "accessibilityElementsHidden = true" not in share_controller.read_text()
assert not (root / "Basir/Helpers/BasirVisualAccessibility.swift").exists()
assert not (root / "ShareExtension/BasirShareVisualAccessibility.swift").exists()
print("Basir Visual transformation complete: normal accessibility behavior preserved")
