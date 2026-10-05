import Foundation

/// A way of talking to a machine: the real one over Bluetooth, or the demo.
@MainActor
protocol MachineLink: AnyObject {
    var kind: MachineLinkKind { get }
    /// Called on the main actor whenever the link learns something new.
    var onSnapshot: ((MachineSnapshot) -> Void)? { get set }
    var onConnection: ((ConnectionState) -> Void)? { get set }

    func connect()
    func disconnect()
    func refresh()
    func powerOn() async throws
    func brew(_ recipe: Recipe) async throws
    func stop(_ beverage: BeverageID) async throws
    func selectProfile(_ profile: Int) async throws
}
