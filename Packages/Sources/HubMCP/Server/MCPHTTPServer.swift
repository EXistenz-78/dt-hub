import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

public enum MCPServerError: Error, Equatable {
  case portInUse(UInt16)
  case alreadyRunning
  case failed(String)
}

/// What the HTTP layer needs from the tools; every closure may hop to the main actor.
struct MCPBackend: Sendable {
  var token: @Sendable () async -> String
  var instructions: String
  var tools: @Sendable () async -> [Tool]
  var call: @Sendable (String, [String: Value]) async -> CallTool.Result
  var clientCountChanged: @Sendable (Int) -> Void
}

/// Streamable-HTTP MCP endpoint at http://127.0.0.1:<port>/mcp. One MCP `Server` per client session, all sharing the
/// tool backend. Adapted from DT_MCP_Client's `MCPHTTPServer` (MIT, see NOTICE), with the request guard of spec §6.
actor MCPHTTPCore {
  static let endpoint = "/mcp"

  private let backend: MCPBackend
  private var port: UInt16 = 0
  private var group: MultiThreadedEventLoopGroup?
  private var channel: Channel?
  private var sessions: [String: Session] = [:]

  private struct Session {
    let server: Server
    let transport: StatefulHTTPServerTransport
    var lastAccess: Date
  }

  private let idleSeconds: Int
  private var pruner: Task<Void, Never>?

  init(backend: MCPBackend, sessionIdleSeconds: Int = 300) {
    self.backend = backend
    idleSeconds = sessionIdleSeconds
  }

  var isRunning: Bool { channel != nil }

  func start(port: UInt16) async throws(MCPServerError) {
    guard channel == nil else { throw .alreadyRunning }
    self.port = port
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 64)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(HTTPHandler(core: self))
        }
      }
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    do {
      channel = try await bootstrap.bind(host: "127.0.0.1", port: Int(port)).get()
      self.group = group
      startPruning()
    } catch {
      try? await group.shutdownGracefully()
      if let io = error as? IOError, io.errnoCode == EADDRINUSE { throw .portInUse(port) }
      throw .failed(error.localizedDescription)
    }
  }

  /// Most clients just close the socket: a session nobody has used for a while is dropped (a live client starts a new one).
  private func startPruning() {
    pruner?.cancel()
    let tick = max(0.5, Double(idleSeconds) / 4)
    pruner = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(tick))
        await self?.pruneIdleSessions()
      }
    }
  }

  private func pruneIdleSessions() async {
    let limit = TimeInterval(idleSeconds)
    let stale = sessions.filter { Date().timeIntervalSince($0.value.lastAccess) > limit }
    guard !stale.isEmpty else { return }
    for (id, session) in stale {
      sessions[id] = nil
      await session.transport.disconnect()
    }
    backend.clientCountChanged(sessions.count)
  }

  func stop() async {
    pruner?.cancel()
    pruner = nil
    for (_, session) in sessions { await session.transport.disconnect() }
    sessions.removeAll()
    backend.clientCountChanged(0)
    try? await channel?.close()
    channel = nil
    try? await group?.shutdownGracefully()
    group = nil
  }

  func notifyToolsChanged() async {
    for (_, session) in sessions {
      try? await session.server.notify(ToolListChangedNotification.message())
    }
  }

  var clientCount: Int { sessions.count }

  fileprivate func handle(_ request: HTTPRequest) async -> HTTPResponse {
    let guardian = RequestGuard(token: await backend.token(), port: port)
    switch guardian.check(
      authorization: request.header(HTTPHeaderName.authorization), host: request.header(HTTPHeaderName.host),
      origin: request.header(HTTPHeaderName.origin))
    {
    case .allow: break
    case .unauthorized:
      return .error(statusCode: 401, .invalidRequest("Unauthorized"), extraHeaders: [HTTPHeaderName.wwwAuthenticate: "Bearer"])
    case .forbiddenHost: return .error(statusCode: 403, .invalidRequest("Forbidden host"))
    case .forbiddenOrigin: return .error(statusCode: 403, .invalidRequest("Forbidden origin"))
    }

    let sid = request.header(HTTPHeaderName.sessionID)
    if let sid, var session = sessions[sid] {
      session.lastAccess = Date()
      sessions[sid] = session
      let response = await session.transport.handleRequest(request)
      if request.method.uppercased() == "DELETE", response.statusCode == 200 {
        sessions[sid] = nil
        backend.clientCountChanged(sessions.count)
      }
      return response
    }
    if request.method.uppercased() == "POST", let body = request.body, Self.isInitialize(body) {
      return await newSession(for: request)
    }
    if sid != nil { return .error(statusCode: 404, .invalidRequest("Session not found or expired")) }
    return .error(statusCode: 400, .invalidRequest("Missing \(HTTPHeaderName.sessionID) header"))
  }

  static func isInitialize(_ body: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
    return object["method"] as? String == "initialize" && object["id"] != nil
  }

  private struct FixedID: SessionIDGenerator {
    let id: String
    func generateSessionID() -> String { id }
  }

  private func newSession(for request: HTTPRequest) async -> HTTPResponse {
    let id = UUID().uuidString
    let transport = StatefulHTTPServerTransport(sessionIDGenerator: FixedID(id: id))
    let server = Server(
      name: "DT Hub", version: "1.0", instructions: backend.instructions,
      capabilities: .init(tools: .init(listChanged: true)))
    let backend = self.backend
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: await backend.tools()) }
    await server.withMethodHandler(CallTool.self) { params in await backend.call(params.name, params.arguments ?? [:]) }
    do {
      try await server.start(transport: transport)
      sessions[id] = Session(server: server, transport: transport, lastAccess: Date())
      backend.clientCountChanged(sessions.count)
      let response = await transport.handleRequest(request)
      if case .error = response {
        sessions[id] = nil
        backend.clientCountChanged(sessions.count)
        await transport.disconnect()
      }
      return response
    } catch {
      await transport.disconnect()
      return .error(statusCode: 500, .internalError("Failed to create session"))
    }
  }
}

// MARK: - NIO adapter

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let core: MCPHTTPCore
  private var head: HTTPRequestHead?
  private var body = ByteBuffer()

  init(core: MCPHTTPCore) { self.core = core }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let h):
      head = h
      body.clear()
    case .body(var b):
      // Tool calls are small; anything over 8 MiB is refused.
      if body.readableBytes + b.readableBytes > 8 * 1024 * 1024 {
        context.close(promise: nil)
        return
      }
      body.writeBuffer(&b)
    case .end:
      guard let h = head else { return }
      head = nil
      let bytes = body.readableBytes > 0 ? Data(body.readableBytesView) : nil
      nonisolated(unsafe) let ctx = context
      Task { await self.respond(head: h, body: bytes, context: ctx) }
    }
  }

  private func respond(head h: HTTPRequestHead, body: Data?, context ctx: ChannelHandlerContext) async {
    let path = h.uri.split(separator: "?").first.map(String.init) ?? h.uri
    guard path == MCPHTTPCore.endpoint else {
      return await write(.error(statusCode: 404, .invalidRequest("Not Found")), h.version, ctx)
    }
    var headers: [String: String] = [:]
    for (n, v) in h.headers { headers[n] = headers[n].map { $0 + ", " + v } ?? v }
    let request = HTTPRequest(method: h.method.rawValue, headers: headers, body: body, path: path)
    await write(await core.handle(request), h.version, ctx)
  }

  private func write(_ response: HTTPResponse, _ version: HTTPVersion, _ ctx: ChannelHandlerContext) async {
    nonisolated(unsafe) let ctx = ctx
    let loop = ctx.eventLoop
    let status = HTTPResponseStatus(statusCode: response.statusCode)
    let headers = response.headers

    func makeHead() -> HTTPResponseHead {
      var h = HTTPResponseHead(version: version, status: status)
      for (n, v) in headers { h.headers.add(name: n, value: v) }
      return h
    }

    if case .stream(let stream, _) = response {
      loop.execute {
        ctx.write(self.wrapOutboundOut(.head(makeHead())), promise: nil)
        ctx.flush()
      }
      do {
        for try await chunk in stream {
          loop.execute {
            var buffer = ctx.channel.allocator.buffer(capacity: chunk.count)
            buffer.writeBytes(chunk)
            ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
          }
        }
      } catch {}
      loop.execute { ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil) }
    } else {
      let data = response.bodyData
      loop.execute {
        ctx.write(self.wrapOutboundOut(.head(makeHead())), promise: nil)
        if let data {
          var buffer = ctx.channel.allocator.buffer(capacity: data.count)
          buffer.writeBytes(data)
          ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      }
    }
  }
}

// MARK: - Public facade

/// The server the app starts and stops: connects the HTTP layer to the tool registry and the token.
@MainActor
public final class MCPHTTPServer {
  private let registry: ToolRegistry
  private let core: MCPHTTPCore
  public private(set) var isRunning = false
  public private(set) var connectedClients = 0
  public var onClientCountChanged: ((Int) -> Void)?

  public init(
    registry: ToolRegistry, tokens: TokenStore, instructions: String = AgentInstructions.short, sessionIdleSeconds: Int = 300
  ) {
    self.registry = registry
    let registry = registry
    var backend = MCPBackend(
      token: { tokens.token() }, instructions: instructions,
      tools: { await MainActor.run { registry.visibleTools().map(\.tool) } },
      call: { name, arguments in
        let result = await registry.call(name, arguments: arguments)
        return CallTool.Result(
          content: result.outputs.map { output in
            switch output {
            case .text(let text): .text(text: text, annotations: nil, _meta: nil)
            case .image(let data, let mime):
              .image(data: data.base64EncodedString(), mimeType: mime, annotations: nil, _meta: nil)
            }
          }, isError: result.isError)
      },
      clientCountChanged: { _ in })
    let box = ClientCountBox()
    backend.clientCountChanged = { count in box.fire(count) }
    core = MCPHTTPCore(backend: backend, sessionIdleSeconds: sessionIdleSeconds)
    box.owner = { [weak self] count in
      Task { @MainActor in self?.clientsChanged(count) }
    }
    registry.onListChanged = { [core] in Task { await core.notifyToolsChanged() } }
  }

  public func start(port: UInt16) async throws(MCPServerError) {
    try await core.start(port: port)
    isRunning = true
  }

  public func stop() async {
    await core.stop()
    isRunning = false
  }

  private func clientsChanged(_ count: Int) {
    connectedClients = count
    if count == 0 { registry.context.jobs.clientDisconnected() } else { registry.context.jobs.clientConnected() }
    onClientCountChanged?(count)
  }
}

private final class ClientCountBox: @unchecked Sendable {
  var owner: (@Sendable (Int) -> Void)?
  func fire(_ count: Int) { owner?(count) }
}
