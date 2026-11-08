import Darwin
import Foundation
import MCP
import Testing

@testable import HubMCP

func freePort() -> UInt16 {
  let fd = socket(AF_INET, SOCK_STREAM, 0)
  defer { close(fd) }
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_addr.s_addr = inet_addr("127.0.0.1")
  addr.sin_port = 0
  var len = socklen_t(MemoryLayout<sockaddr_in>.size)
  withUnsafeMutablePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      _ = bind(fd, $0, len)
      _ = getsockname(fd, $0, &len)
    }
  }
  return UInt16(bigEndian: addr.sin_port)
}

@MainActor
struct ServerIntegrationTests {
  let tokens = TokenStore(storage: InMemorySecretStorage())

  func edit() -> ToolSpec {
    ToolSpec(name: "edit_probe", description: "probe", level: .edit) { _, _ in [.text("ok")] }
  }

  nonisolated func client(port: UInt16, token: String) -> (Client, HTTPClientTransport) {
    let transport = HTTPClientTransport(
      endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!, streaming: true,
      requestModifier: { request in
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
      })
    return (Client(name: "test", version: "1"), transport)
  }

  func rawPost(port: UInt16, headers: [String: String]) async throws -> Int {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    return (response as! HTTPURLResponse).statusCode
  }

  @Test func rejectsRequestWithoutToken() async throws {
    let h = Harness()
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    #expect(try await rawPost(port: port, headers: [:]) == 401)
    #expect(try await rawPost(port: port, headers: ["Authorization": "Bearer nope"]) == 401)
    await server.stop()
  }

  @Test func rejectsForeignOrigin() async throws {
    let h = Harness()
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    let status = try await rawPost(
      port: port, headers: ["Authorization": "Bearer \(tokens.token())", "Origin": "https://example.com"])
    #expect(status == 403)
    await server.stop()
  }

  @Test func clientListsOnlyReadToolsInReadOnlyMode() async throws {
    let h = Harness(mode: .readOnly, extraSpecs: [edit()])
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    let (c, transport) = client(port: port, token: tokens.token())
    _ = try await c.connect(transport: transport)
    let names = try await c.listTools().tools.map(\.name)
    #expect(names.contains("get_app_state"))
    #expect(!names.contains("edit_probe"))
    await c.disconnect()
    await server.stop()
  }

  @Test func clientCallsGetAppStateAndSeesInstructions() async throws {
    let h = Harness()
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    let (c, transport) = client(port: port, token: tokens.token())
    let initialized = try await c.connect(transport: transport)
    #expect(initialized.instructions?.contains("get_app_state") == true)
    let (content, isError) = try await c.callTool(name: "get_app_state", arguments: [:])
    #expect(isError != true)
    guard case .text(let text, _, _)? = content.first else { Issue.record("no text"); return }
    #expect(text.contains("readOnly"))
    await c.disconnect()
    await server.stop()
  }

  @Test func portInUseThrowsPortInUse() async throws {
    let h = Harness()
    let first = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let second = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await first.start(port: port)
    await #expect(throws: MCPServerError.portInUse(port)) { try await second.start(port: port) }
    #expect(second.isRunning == false)
    await first.stop()
  }

  @Test func stopClosesTheListener() async throws {
    let h = Harness()
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    await server.stop()
    #expect(server.isRunning == false)
    await #expect(throws: (any Error).self) { _ = try await rawPost(port: port, headers: [:]) }
  }

  @Test func listChangedIsDeliveredWhenModeChanges() async throws {
    let h = Harness(mode: .readOnly, extraSpecs: [edit()])
    let server = MCPHTTPServer(registry: h.registry, tokens: tokens)
    let port = freePort()
    try await server.start(port: port)
    let (c, transport) = client(port: port, token: tokens.token())
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    await c.onNotification(ToolListChangedNotification.self) { _ in continuation.yield() }
    _ = try await c.connect(transport: transport)
    try await Task.sleep(for: .milliseconds(300))
    h.settings.value.mode = .editFields
    h.registry.hostDidChange()
    let got = await withTaskGroup(of: Bool.self) { group in
      group.addTask { for await _ in stream { return true }; return false }
      group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
    #expect(got)
    await c.disconnect()
    await server.stop()
  }
}
