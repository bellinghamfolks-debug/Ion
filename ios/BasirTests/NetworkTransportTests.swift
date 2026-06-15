import XCTest
@testable import Basir

final class NetworkTransportTests: XCTestCase {
    func testProxyRequiresHTTPSOutsideLocalhost() {
        XCTAssertNil(NetworkTransport.safeProxyEndpoint(from: "http://example.com"))
        XCTAssertEqual(
            NetworkTransport.safeProxyEndpoint(from: "https://example.com")?.absoluteString,
            "https://example.com/api/basir")
        XCTAssertEqual(
            NetworkTransport.safeProxyEndpoint(from: "https://example.com/custom/")?.absoluteString,
            "https://example.com/custom/api/basir")
    }

    func testLocalDevelopmentMayUseHTTP() {
        XCTAssertEqual(
            NetworkTransport.safeProxyEndpoint(from: "http://localhost:8080")?.absoluteString,
            "http://localhost:8080/api/basir")
    }

    func testProxyRejectsEmbeddedCredentials() {
        XCTAssertNil(NetworkTransport.safeProxyEndpoint(from: "https://user:secret@example.com"))
    }

    func testProxyDropsQueryAndFragment() {
        XCTAssertEqual(
            NetworkTransport.safeProxyEndpoint(
                from: "https://example.com/base?token=leak#fragment")?.absoluteString,
            "https://example.com/base/api/basir")
    }
}
