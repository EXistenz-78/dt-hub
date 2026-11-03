import Foundation
import HubCore

/// The sentences of the update window and preferences.
enum UpdateText {
  static func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  /// «DT Hub 1.0.0 e 3 aggiornamenti di plug-in»: what the banner says of these offers.
  static func summary(_ offers: [UpdateOffer]) -> String {
    let plugins = offers.filter { !$0.isApp }.count
    if let app = offers.first(where: \.isApp) {
      if plugins == 0 { return String(format: String(localized: "updates.banner.app"), app.item.version) }
      return String(format: String(localized: "updates.banner.appAndPlugins"), app.item.version, plugins)
    }
    return String(format: String(localized: "updates.banner.plugins"), plugins)
  }

  static func error(_ error: UpdateError) -> String {
    switch error {
    case .checksum: return String(localized: "updates.error.checksum")
    case .signature: return String(localized: "updates.error.signature")
    case .identityMismatch: return String(localized: "updates.error.identity")
    case .notNewer: return String(localized: "updates.error.notNewer")
    case .noBundle: return String(localized: "updates.error.noBundle")
    case .download(let reason): return String(format: String(localized: "updates.error.download"), reason)
    case .unzip(let reason): return String(format: String(localized: "updates.error.unzip"), reason)
    case .cannotWrite(let reason): return String(format: String(localized: "updates.error.write"), reason)
    case .plugin(let error): return PluginText.error(error)
    }
  }

  static func message(_ message: UpdateMessage) -> String? {
    switch message {
    case .upToDate: return String(localized: "updates.message.upToDate")
    case .unreachable: return String(localized: "updates.message.unreachable")
    case .noInformation: return String(localized: "updates.message.noInformation")
    case .results: return nil
    }
  }
}
