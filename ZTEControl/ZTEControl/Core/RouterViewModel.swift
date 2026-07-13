import Foundation
import Combine

/// Drives the UI: owns the client, tracks connection state, and exposes async
/// actions for status refresh and band / mode locking.
@MainActor
final class RouterViewModel: ObservableObject {
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var connection: Connection = .disconnected
    @Published private(set) var status: RouterStatus?
    @Published private(set) var busy = false
    @Published var lastMessage: String?

    // Band-lock selections (mirrored into the UI).
    @Published var selectedLTE: Set<Int> = []
    @Published var selectedNR5G: Set<Int> = []
    @Published var mode: NetworkMode = .auto

    private let settings: RouterSettings
    private var client: ZTEClient?

    init(settings: RouterSettings = .shared) { self.settings = settings }

    var isConnected: Bool { connection == .connected }

    /// Connect + login using the stored host/password.
    func connect() async {
        guard let base = settings.baseURL else {
            connection = .failed("عنوان الراوتر غير صحيح."); return
        }
        connection = .connecting
        let client = ZTEClient(baseURL: base)
        self.client = client
        do {
            try await client.login(password: settings.password)
            connection = .connected
            DiagnosticsLog.shared.add(.note, "تم تسجيل الدخول بنجاح.")
            await refresh()
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let client else { return }
        do {
            let s = try await client.fetchStatus()
            status = s
            // Reflect any active lock back into the pickers.
            if let m = s.raw["lte_band_lock"] { selectedLTE = RadioBand.bands(fromHexMask: m) }
        } catch {
            lastMessage = "تعذّر تحديث الحالة: \(error.localizedDescription)"
        }
    }

    func applyMode() async {
        await run("تم ضبط وضع الشبكة.") { try await $0.setNetworkMode(self.mode) }
    }

    func applyBandLock() async {
        await run("تم تثبيت النطاقات. انتظر إعادة الاتصال.") {
            try await $0.lockBands(lte: self.selectedLTE, nr5g: self.selectedNR5G)
        }
    }

    func clearLock() async {
        await run("تم إلغاء التثبيت (اختيار تلقائي).") {
            self.selectedLTE = []; self.selectedNR5G = []
            try await $0.clearBandLock()
        }
    }

    func sendRaw(goformId: String, fields: [String: String]) async {
        await run("تم إرسال الأمر.") { _ = try await $0.sendRaw(goformId: goformId, fields: fields) }
    }

    private func run(_ okMessage: String, _ op: @escaping (ZTEClient) async throws -> Void) async {
        guard let client else { lastMessage = "غير متصل بالراوتر."; return }
        busy = true; defer { busy = false }
        do {
            try await op(client)
            lastMessage = okMessage
            // Give the modem a moment, then refresh signal.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await refresh()
        } catch {
            lastMessage = error.localizedDescription
        }
    }
}
