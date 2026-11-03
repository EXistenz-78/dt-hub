import Foundation
import HubKit

/// One thing the release can update: the app or an installed plug-in.
public struct UpdateOffer: Identifiable, Equatable, Sendable {
  public let item: ReleaseItem
  /// The version that is there now.
  public let installed: String

  public var id: String { item.id }
  public var isApp: Bool { item.id == ReleaseItem.appID }

  public init(item: ReleaseItem, installed: String) {
    self.item = item
    self.installed = installed
  }
}

/// What a manifest offers to this Mac: only what is newer than what is installed.
public enum UpdatePlan {
  /// The app first (if newer), then the installed plug-ins that are newer, by name. A plug-in that is not installed is
  /// not offered; one made for a contract this app does not know waits until the app is updated.
  public static func make(
    manifest: ReleaseManifest, appVersion: String, installedPlugins: [String: String], supportedContracts: Set<Int>
  ) -> [UpdateOffer] {
    var offers: [UpdateOffer] = []
    if PluginVersion(manifest.app.version) > PluginVersion(appVersion) {
      offers.append(UpdateOffer(item: manifest.app, installed: appVersion))
    }
    let plugins = manifest.plugins.compactMap { item -> UpdateOffer? in
      guard let installed = installedPlugins[item.id], PluginVersion(item.version) > PluginVersion(installed),
        item.contract.map(supportedContracts.contains) ?? true
      else { return nil }
      return UpdateOffer(item: item, installed: installed)
    }
    return offers + plugins.sorted { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending }
  }

  /// What is left after «Più tardi»: an offer put off at this version, or at a higher one, stays hidden.
  public static func visible(_ offers: [UpdateOffer], dismissed: [String: String]) -> [UpdateOffer] {
    offers.filter { offer in
      guard let version = dismissed[offer.id] else { return true }
      return PluginVersion(offer.item.version) > PluginVersion(version)
    }
  }
}
