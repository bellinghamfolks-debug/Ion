import Foundation
import UIKit

enum DeviceIdentity {
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
        }
        return identifier
    }

    static var marketingName: String {
        knownModels[modelIdentifier] ?? "iPhone (\(modelIdentifier))"
    }

    static func snapshot(now: Date = Date()) -> DeviceSnapshot {
        DeviceSnapshot(
            modelIdentifier: modelIdentifier,
            marketingName: marketingName,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            generatedAt: now
        )
    }

    private static let knownModels: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (الجيل الثاني)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (الجيل الثالث)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e"
    ]
}
