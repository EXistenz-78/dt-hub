import Foundation
import HubKit

/// What `Info.plist` of a plug-in bundle says.
public struct PluginBundleInfo: Equatable, Sendable {
  public let identifier: String
  public let name: String
  public let version: String
  public let contract: Int
  public let principalClass: String

  public init(identifier: String, name: String, version: String, contract: Int, principalClass: String) {
    self.identifier = identifier
    self.name = name
    self.version = version
    self.contract = contract
    self.principalClass = principalClass
  }
}

/// Reads and checks the `Info.plist` of a `.dthubplugin` bundle without loading its code.
public enum PluginBundleReader {
  public static func read(_ url: URL) throws(PluginError) -> PluginBundleInfo {
    let plist = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
      let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let info = object as? [String: Any]
    else { throw .unreadable }
    func text(_ key: String) throws(PluginError) -> String {
      guard let value = info[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty
      else { throw .missingKey(key) }
      return value
    }
    let identifier = try text("CFBundleIdentifier")
    let name = try text("CFBundleName")
    let principal = try text("NSPrincipalClass")
    let version = (info["CFBundleShortVersionString"] as? String) ?? "0"
    guard let contract = (info[PluginContract.infoKey] as? Int) ?? (info[PluginContract.infoKey] as? String).flatMap(Int.init)
    else { throw .missingKey(PluginContract.infoKey) }
    guard PluginContract.supported.contains(contract) else { throw .contractNotSupported(contract) }
    return PluginBundleInfo(
      identifier: identifier, name: name, version: version, contract: contract, principalClass: principal)
  }
}
