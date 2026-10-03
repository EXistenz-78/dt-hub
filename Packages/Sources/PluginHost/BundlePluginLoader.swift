import AppKit
import Foundation
import HubCore
import HubKit

/// Loads a `.dthubplugin` bundle into the app (plug-in design §3, §5): its code through `Bundle`, its
/// manifest, tab and messages through the selectors of the principal class.
@MainActor
public final class BundlePluginLoader: PluginLoading {
  public init() {}

  public func load(_ url: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin {
    guard let bundle = Bundle(url: url) else { throw .unreadable }
    do {
      try bundle.loadAndReturnError()
    } catch {
      throw .loadFailed(error.localizedDescription)
    }
    guard let entryClass = bundle.principalClass as? NSObject.Type else { throw .noEntryPoint }
    let entry = entryClass.init()
    let selectors = ["dthubManifest", "dthubMakeViewController", "dthubStart:", "dthubHandle:reply:"]
    guard selectors.allSatisfy({ entry.responds(to: NSSelectorFromString($0)) }) else { throw .noEntryPoint }

    guard let data = entry.perform(NSSelectorFromString("dthubManifest"))?.takeUnretainedValue() as? Data,
      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
    else { throw .noEntryPoint }
    guard manifest.id == info.identifier else { throw .manifestMismatch(manifest.id) }
    guard PluginContract.supported.contains(manifest.contract) else { throw .contractNotSupported(manifest.contract) }
    guard
      let controller = entry.perform(NSSelectorFromString("dthubMakeViewController"))?.takeUnretainedValue()
        as? NSViewController
    else { throw .noEntryPoint }

    let hostObject = PluginHostObject(host: host, pluginID: manifest.id)
    _ = entry.perform(NSSelectorFromString("dthubStart:"), with: hostObject)
    return BundleLoadedPlugin(manifest: manifest, entry: entry, controller: controller, hostObject: hostObject)
  }
}

/// A loaded plug-in: the app talks to its principal class.
@MainActor
final class BundleLoadedPlugin: LoadedPlugin {
  let manifest: PluginManifest
  let viewController: AnyObject
  private let entry: NSObject
  private let hostObject: PluginHostObject

  init(manifest: PluginManifest, entry: NSObject, controller: NSViewController, hostObject: PluginHostObject) {
    self.manifest = manifest
    self.entry = entry
    self.viewController = controller
    self.hostObject = hostObject
  }

  /// An answer that did not come in 5 seconds is nil.
  func send(_ message: Data) async -> Data? {
    await withCheckedContinuation { continuation in
      let once = OnceReply(continuation)
      let reply: @convention(block) (Data) -> Void = { once.finish($0) }
      _ = entry.perform(NSSelectorFromString("dthubHandle:reply:"), with: message, with: reply)
      Task {
        try? await Task.sleep(for: .seconds(5))
        once.finish(nil)
      }
    }
  }
}

/// The object the plug-in calls into (`dthubSend:reply:`), possibly from any thread.
final class PluginHostObject: NSObject, @unchecked Sendable {
  private weak var host: (any PluginHosting)?
  private let pluginID: String

  @MainActor
  init(host: any PluginHosting, pluginID: String) {
    self.host = host
    self.pluginID = pluginID
  }

  @objc func dthubSend(_ message: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    Task { @MainActor [weak self] in
      guard let self, let host = self.host else { return reply(PluginMessageType.bare(PluginMessageType.unsupported)) }
      reply(host.receive(message, from: self.pluginID))
    }
  }
}

/// Resumes a continuation once, whichever of the answer and the timeout comes first.
final class OnceReply: @unchecked Sendable {
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
