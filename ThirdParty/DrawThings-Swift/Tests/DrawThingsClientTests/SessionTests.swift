import Foundation
import Testing
@testable import DrawThingsClient

@Suite("DrawThingsSession")
@MainActor
struct SessionTests {
    @Test func startsIdle() throws {
        let session = try DrawThingsSession(address: "127.0.0.1:1")
        #expect(!session.isConnected)
        #expect(!session.isGenerating)
        #expect(session.progress == nil)
        #expect(session.preview == nil)
        #expect(session.lastResult == nil)
    }

    @Test func failedConnectionIsReported() async throws {
        // Port 1 on loopback refuses connections immediately.
        let session = try DrawThingsSession(address: "127.0.0.1:1", options: ConnectionOptions(security: .plaintext, requestTimeout: .seconds(5)))
        await session.connect()
        #expect(!session.isConnected)
        #expect(session.lastError is DrawThingsError)
    }

    @Test func invalidAddressThrows() {
        #expect(throws: ServerEndpointError.self) { try DrawThingsSession(address: "host:99999") }
    }
}
