import Testing

@testable import HubMCP

struct RequestGuardTests {
  let guardian = RequestGuard(token: "secret-token", port: 8765)

  @Test(arguments: ["127.0.0.1:8765", "localhost:8765", "[::1]:8765", "LOCALHOST:8765"])
  func acceptsBearerTokenWithLoopbackHost(host: String) {
    #expect(guardian.check(authorization: "Bearer secret-token", host: host, origin: nil) == .allow)
  }

  @Test(arguments: [nil, "Bearer wrong", "Bearer secret-token ", "bearer secret-token", "secret-token", "Bearer  secret-token"])
  func rejectsMissingOrWrongToken(header: String?) {
    #expect(guardian.check(authorization: header, host: "127.0.0.1:8765", origin: nil) == .unauthorized)
  }

  @Test(arguments: ["evil.com", "127.0.0.1.evil.com", "evil.com:8765", "10.0.0.5:8765", ""])
  func rejectsForeignHost(host: String) {
    #expect(guardian.check(authorization: "Bearer secret-token", host: host, origin: nil) == .forbiddenHost)
  }

  @Test func rejectsMissingHost() {
    #expect(guardian.check(authorization: "Bearer secret-token", host: nil, origin: nil) == .forbiddenHost)
  }

  @Test(arguments: ["https://example.com", "null", "http://localhost:8765"])
  func rejectsAnyBrowserOrigin(origin: String) {
    #expect(guardian.check(authorization: "Bearer secret-token", host: "127.0.0.1:8765", origin: origin) == .forbiddenOrigin)
  }

  @Test func allowsMissingOrigin() {
    #expect(guardian.check(authorization: "Bearer secret-token", host: "localhost:8765", origin: nil) == .allow)
  }
}
