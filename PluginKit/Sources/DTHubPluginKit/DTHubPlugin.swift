import AppKit
import Foundation

/// What a plug-in says about itself (the JSON `dthubManifest` returns).
public struct DTHubManifest: Codable, Sendable {
  public var id: String
  public var name: String
  public var version: String
  /// The contract version this plug-in was made for.
  public var contract: Int
  /// An SF Symbol name for the tab.
  public var symbol: String
  /// Model families it works with; nil = all.
  public var families: [String]?

  public init(
    id: String, name: String, version: String = "1.0", contract: Int = DTHubContract.current,
    symbol: String = "puzzlepiece.extension", families: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.contract = contract
    self.symbol = symbol
    self.families = families
  }
}

public enum DTHubContract {
  public static let current = 1
}

/// JSON messages are objects with a `type`.
public enum DTHubMessage {
  public static func type(of data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }

  public static func bare(_ type: String) -> Data { Data(#"{"type":"\#(type)"}"#.utf8) }
}

/// App → plug-in: where the app stands (message type `context`).
public struct DTHubContext: Decodable, Sendable {
  public var model: String?
  public var family: String?
  /// A folder to exchange image files through.
  public var tempFolder: String
}

/// The app side of the channel, given to the plug-in at start.
@MainActor
public final class DTHubHost {
  private let object: NSObject

  init(object: NSObject) { self.object = object }

  /// Sends a JSON message to the app and waits for its JSON answer.
  public func send(_ message: Data) async -> Data? {
    await withCheckedContinuation { continuation in
      let once = Once(continuation)
      let reply: @convention(block) (Data) -> Void = { once.finish($0) }
      _ = object.perform(NSSelectorFromString("dthubSend:reply:"), with: message, with: reply)
      Task {
        try? await Task.sleep(for: .seconds(5))
        once.finish(nil)
      }
    }
  }

  /// Asks the app to show a line to the user.
  public func notice(_ text: String, isError: Bool = false) {
    let body: [String: Any] = ["type": "notice", "text": text, "isError": isError]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    Task { _ = await send(data) }
  }
}

final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data?, Never>?

  init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

  func finish(_ data: Data?) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: data)
  }
}

/// A DT Hub plug-in.
@MainActor
public protocol DTHubPlugin: AnyObject {
  var manifest: DTHubManifest { get }
  /// The tab of the plug-in (usually an `NSHostingController` with a SwiftUI view).
  func makeViewController() -> NSViewController
  /// Called once, after the manifest and the view are made.
  func start(host: DTHubHost)
  /// A message from the app; the answer is JSON (nil = `{"type":"ok"}`). An unknown type should
  /// get `nil` or `{"type":"unsupported"}`.
  func handle(_ message: Data) async -> Data?
}

/// The principal class of a plug-in bundle. Subclass it, give the subclass an Objective-C name
/// (`@objc(MyPluginEntry)`), put that name in `NSPrincipalClass`, and override `makePlugin()`.
@MainActor
open class DTHubPluginEntry: NSObject {
  private var plugin: (any DTHubPlugin)?

  public required override init() { super.init() }

  open func makePlugin() -> any DTHubPlugin { fatalError("override makePlugin()") }

  private func made() -> any DTHubPlugin {
    if let plugin { return plugin }
    let plugin = makePlugin()
    self.plugin = plugin
    return plugin
  }

  @objc public func dthubManifest() -> Data {
    (try? JSONEncoder().encode(made().manifest)) ?? Data()
  }

  @objc public func dthubMakeViewController() -> NSViewController {
    made().makeViewController()
  }

  @objc public func dthubStart(_ host: NSObject) {
    made().start(host: DTHubHost(object: host))
  }

  @objc public func dthubHandle(_ message: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    let plugin = made()
    Task { @MainActor in
      reply(await plugin.handle(message) ?? DTHubMessage.bare("ok"))
    }
  }
}
