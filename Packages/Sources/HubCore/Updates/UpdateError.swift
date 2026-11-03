import Foundation

/// Why an item of an update could not be installed.
public enum UpdateError: Error, Equatable, Sendable {
  case download(String)
  /// The sha256 of the file is not the one in the manifest.
  case checksum
  case unzip(String)
  /// The zip holds no bundle, or more than one.
  case noBundle
  /// The bundle is not the plug-in (identifier, version) the manifest named.
  case identityMismatch
  /// `codesign` does not accept the new app.
  case signature
  /// The new app is not newer than the running one.
  case notNewer
  case cannotWrite(String)
  case plugin(PluginError)
}
