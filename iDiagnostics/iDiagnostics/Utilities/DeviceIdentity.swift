import UIKit

/// Resolves the hardware model identifier (e.g. "iPhone15,3") and a best-effort
/// marketing name. iOS has no public API for the marketing name, so unknown
/// identifiers fall back to the raw identifier rather than guessing wrongly.
enum DeviceIdentity {
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            if let value = element.value as? Int8, value != 0 {
                partial.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        // On the Simulator the real model is in an env var.
        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
        }
        return identifier
    }

    static var marketingName: String {
        marketingNames[modelIdentifier] ?? modelIdentifier
    }

    @MainActor
    static func snapshot() -> DeviceSnapshot {
        DeviceSnapshot(
            modelIdentifier: modelIdentifier,
            marketingName: marketingName,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            generatedAt: Date()
        )
    }

    /// A compact map of recent identifiers. Extend as new models ship;
    /// anything missing falls back to the identifier itself.
    private static let marketingNames: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
    ]
}
