import XCTest
@testable import iDiagnostics

final class SessionRepositoryTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("session.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testRoundTripPreservesSessionExactly() throws {
        let repository = DiskSessionRepository(fileURL: fileURL)
        var session = sampleSession()
        session.record(DiagnosticResult(
            category: .microphone,
            outcome: .pass,
            summaryAr: "سليم",
            metrics: [.init(label: "مدة العينة", value: "4 ثوانٍ")],
            evidence: .mixed
        ))

        try repository.save(session)
        XCTAssertEqual(try repository.load(), session)
    }

    func testCorruptSessionIsQuarantined() throws {
        let repository = DiskSessionRepository(fileURL: fileURL)
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertThrowsError(try repository.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.contains("corrupt-") })
    }

    func testRemoveIsIdempotent() throws {
        let repository = DiskSessionRepository(fileURL: fileURL)
        try repository.remove()
        try repository.save(sampleSession())
        try repository.remove()
        try repository.remove()
        XCTAssertNil(try repository.load())
    }

    private func sampleSession() -> DiagnosticSession {
        DiagnosticSession(device: DeviceSnapshot(
            modelIdentifier: "iPhone16,2",
            marketingName: "iPhone 15 Pro Max",
            systemName: "iOS",
            systemVersion: "18.0",
            appVersion: "2.0.0",
            generatedAt: Date(timeIntervalSince1970: 1)
        ))
    }
}
