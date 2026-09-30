import Foundation
import Testing

@testable import HubCore

/// Uses the real login Keychain, under a throwaway service name removed at the end.
struct KeychainSecretStoreTests {
  @Test func writesReadsReplacesAndRemovesTheSecret() throws {
    let store = KeychainSecretStore(service: "com.exiztenz.DTHub.tests.\(UUID())", account: "secret")
    defer { try? store.write(nil) }

    #expect(store.read() == nil)
    try store.write("first")
    #expect(store.read() == "first")
    try store.write("second")
    #expect(store.read() == "second")
    try store.write("")
    #expect(store.read() == nil)
  }
}
