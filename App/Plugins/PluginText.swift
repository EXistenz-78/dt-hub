import Foundation
import HubCore

/// The sentences for what the plug-in list shows.
enum PluginText {
  /// The page where plug-ins can be downloaded, once it exists (nil: the link is not shown).
  static let downloadPage: URL? = nil

  static func error(_ error: PluginError) -> String {
    switch error {
    case .unreadable: String(localized: "plugin.error.unreadable")
    case .missingKey(let key): String(format: String(localized: "plugin.error.missingKey"), key)
    case .contractNotSupported(let version): String(format: String(localized: "plugin.error.contract"), version)
    case .manifestMismatch(let found): String(format: String(localized: "plugin.error.mismatch"), found)
    case .noEntryPoint: String(localized: "plugin.error.entry")
    case .loadFailed(let reason): String(format: String(localized: "plugin.error.load"), reason)
    case .notNewer(let installed): String(format: String(localized: "plugin.error.notNewer"), installed)
    case .cannotWrite(let reason): String(format: String(localized: "plugin.error.write"), reason)
    case .invalidIdentifier(let id): String(format: String(localized: "plugin.error.identifier"), id)
    }
  }

  /// The line under a plug-in's name: its state, and when the folder holds a version newer than the one running.
  static func state(_ entry: PluginEntry) -> String {
    if entry.state == .loaded, let running = entry.runningVersion, running != entry.version {
      return String(format: String(localized: "plugin.state.pendingVersion"), running, entry.version)
    }
    return state(entry.state)
  }

  static func state(_ state: PluginEntry.State) -> String {
    switch state {
    case .off: String(localized: "plugin.state.off")
    case .loadsAtNextLaunch: String(localized: "plugin.state.next")
    case .skipped: String(localized: "plugin.state.skipped")
    case .loaded: String(localized: "plugin.state.loaded")
    case .failed(let reason): error(reason)
    }
  }
}
