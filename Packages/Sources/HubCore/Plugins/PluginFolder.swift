import Foundation
import HubKit

/// One `.dthubplugin` found in the folder: what it says, or why it cannot be used.
public struct PluginSlot: Equatable, Sendable {
  public let url: URL
  public let info: PluginBundleInfo?
  public let error: PluginError?

  public init(url: URL, info: PluginBundleInfo?, error: PluginError?) {
    self.url = url
    self.info = info
    self.error = error
  }

  /// The plug-in's identifier, or the folder's name when the bundle cannot be read.
  public var identifier: String { info?.identifier ?? url.deletingPathExtension().lastPathComponent }
}

/// The folder the plug-ins live in (`~/Library/Application Support/DT Hub/Plug-ins`): finds them,
/// copies a new one in, removes one.
public struct PluginFolder: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public static var defaultRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Plug-ins", isDirectory: true)
  }

  /// Every `.dthubplugin` in the folder, read but not loaded; one identifier appears once (the
  /// first folder in name order wins, the others are reported as unreadable duplicates).
  public func scan() -> [PluginSlot] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    var seen: Set<String> = []
    var slots: [PluginSlot] = []
    for url in urls.filter({ $0.pathExtension == PluginContract.bundleExtension }).sorted(by: {
      $0.lastPathComponent < $1.lastPathComponent
    }) {
      do {
        let info = try PluginBundleReader.read(url)
        guard seen.insert(info.identifier).inserted else {
          slots.append(PluginSlot(url: url, info: nil, error: .unreadable))
          continue
        }
        slots.append(PluginSlot(url: url, info: info, error: nil))
      } catch {
        slots.append(PluginSlot(url: url, info: nil, error: error))
      }
    }
    return slots
  }

  /// The installed bundle with this identifier, if any.
  public func installed(_ identifier: String) -> PluginBundleInfo? {
    scan().compactMap(\.info).first { $0.identifier == identifier }
  }

  /// Where a plug-in with this identifier is kept.
  public func location(of identifier: String) -> URL {
    root.appendingPathComponent("\(identifier).\(PluginContract.bundleExtension)", isDirectory: true)
  }

  /// Copies the bundle in (replacing an older version of the same plug-in) and takes the download
  /// quarantine mark off the copy. The same or a lower version is refused.
  public func install(_ source: URL, info: PluginBundleInfo) throws(PluginError) {
    if let current = installed(info.identifier),
      !(PluginVersion(info.version) > PluginVersion(current.version))
    {
      throw .notNewer(installed: current.version)
    }
    let destination = location(of: info.identifier)
    let manager = FileManager.default
    // Copy to a hidden folder first, swap after; whatever happens the hidden folder goes away.
    let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    defer { try? manager.removeItem(at: staging) }
    do {
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try manager.copyItem(at: source, to: staging)
      Self.removeQuarantine(from: staging)
      // Every folder that holds this plug-in, under whatever name it was put there.
      let previous = scan().filter { $0.info?.identifier == info.identifier }.map(\.url)
      if manager.fileExists(atPath: destination.path) {
        _ = try manager.replaceItemAt(destination, withItemAt: staging)
      } else {
        try manager.moveItem(at: staging, to: destination)
      }
      for url in previous where url.standardizedFileURL != destination.standardizedFileURL {
        try? manager.removeItem(at: url)
      }
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  /// Removes one folder of the list (a broken bundle has no identifier to go by).
  public func remove(folderAt url: URL) throws(PluginError) {
    do { try FileManager.default.removeItem(at: url) } catch { throw .cannotWrite(error.localizedDescription) }
  }

  /// Removes the plug-in's folder (a loaded plug-in goes away at the next launch).
  public func remove(_ identifier: String) throws(PluginError) {
    for slot in scan() where slot.identifier == identifier {
      do { try FileManager.default.removeItem(at: slot.url) } catch { throw .cannotWrite(error.localizedDescription) }
    }
  }

  /// Takes `com.apple.quarantine` off a bundle and everything in it.
  static func removeQuarantine(from url: URL) {
    removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    while let item = enumerator?.nextObject() as? URL {
      removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
    }
  }
}
