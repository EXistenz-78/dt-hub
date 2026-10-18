import Foundation
import HubKit

/// A plug-in whose code is loaded (`PluginLoading` makes one).
@MainActor
public protocol LoadedPlugin: AnyObject {
  var manifest: PluginManifest { get }
  /// The plug-in's tab, an `NSViewController` made once at load (the app casts it).
  var viewController: AnyObject { get }
  /// App → plug-in. nil when the plug-in did not answer in time.
  func send(_ message: Data) async -> Data?
  /// Like `send`, waiting up to `timeout` for the answer (a plug-in that guides a pipeline may need seconds to prepare a pass).
  func send(_ message: Data, timeout: Duration) async -> Data?
}

extension LoadedPlugin {
  /// A plug-in that has no timeout of its own is asked as usual.
  public func send(_ message: Data, timeout: Duration) async -> Data? { await send(message) }
}

/// What a plug-in calls into: the app side of the message channel.
@MainActor
public protocol PluginHosting: AnyObject {
  /// Plug-in → app; the answer goes back to the plug-in. Async: a question for the language model takes a while.
  func receive(_ message: Data, from pluginID: String) async -> Data
}

/// Loads the code of a plug-in bundle (the app's implementation uses `Bundle`; the tests a fake).
@MainActor
public protocol PluginLoading {
  func load(_ bundle: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin
}
