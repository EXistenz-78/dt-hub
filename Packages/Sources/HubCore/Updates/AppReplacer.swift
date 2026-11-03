import Foundation
import HubKit

public enum AppReplaceOutcome: Equatable, Sendable {
  /// The new app is where the running one was; it starts at the next launch.
  case replaced
  /// The folder of the running app cannot be written: the new app waits at this place, to be dragged in by hand.
  case revealed(URL)
}

/// Puts a new DT Hub in the place of the running one. The checks that touch the system are injected.
public struct AppReplacer: Sendable {
  /// Whether `codesign --verify --deep --strict` accepts the app.
  public var verifySignature: @Sendable (URL) async -> Bool
  public var move: @Sendable (URL, URL) throws -> Void
  /// Sends a folder to the Trash.
  public var trash: @Sendable (URL) -> Void

  public init(
    verifySignature: @escaping @Sendable (URL) async -> Bool,
    move: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
    trash: @escaping @Sendable (URL) -> Void
  ) {
    self.verifySignature = verifySignature
    self.move = move
    self.trash = trash
  }

  /// Checks the new app (same identifier, newer, signature intact), takes the quarantine off, then swaps it with the
  /// running one; if putting it in place fails the old one comes back. The old app goes to the Trash.
  public func replace(
    running: URL, runningIdentifier: String, runningVersion: String, with new: URL, work: URL, downloads: URL
  ) async throws(UpdateError) -> AppReplaceOutcome {
    guard let info = Self.readInfo(new), info.identifier == runningIdentifier else { throw .identityMismatch }
    guard PluginVersion(info.version) > PluginVersion(runningVersion) else { throw .notNewer }
    guard await verifySignature(new) else { throw .signature }
    PluginFolder.removeQuarantine(from: new)

    let manager = FileManager.default
    let parent = running.deletingLastPathComponent()
    let path = running.path
    let canSwap =
      manager.isWritableFile(atPath: parent.path) && !path.hasPrefix("/Volumes/") && !path.contains("/AppTranslocation/")
    do {
      guard canSwap else {
        let destination = downloads.appendingPathComponent(running.lastPathComponent)
        try? manager.removeItem(at: destination)
        try manager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try move(new, destination)
        return .revealed(destination)
      }
      // The old app waits next to its place, on the same volume and outside the work folder (which is emptied at the
      // end): if everything goes wrong it is still there to be found.
      let aside = parent.appendingPathComponent(".\(running.deletingPathExtension().lastPathComponent)-old-\(UUID().uuidString).app")
      try move(running, aside)
      do {
        try move(new, running)
      } catch {
        // Back to how it was.
        try? move(aside, running)
        throw error
      }
      trash(aside)
      return .replaced
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  static func readInfo(_ app: URL) -> (identifier: String, version: String)? {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let identifier = info["CFBundleIdentifier"] as? String,
      let version = info["CFBundleShortVersionString"] as? String
    else { return nil }
    return (identifier, version)
  }

  public static let live = AppReplacer(
    verifySignature: { app in
      await Task.detached(priority: .utility) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
      }.value
    },
    trash: { url in
      if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
        try? FileManager.default.removeItem(at: url)
      }
    })
}
