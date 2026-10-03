import Foundation

/// Why a plug-in could not be read, installed or loaded. The app turns each case into a sentence.
public enum PluginError: Error, Equatable, Sendable {
  /// The folder is not a readable bundle (no `Contents/Info.plist`).
  case unreadable
  /// A required `Info.plist` key is missing or empty.
  case missingKey(String)
  /// Made for a contract version this app does not understand.
  case contractNotSupported(Int)
  /// The manifest the code returned does not match the bundle (its identifier).
  case manifestMismatch(String)
  /// The principal class is missing or is not the kind the app expects.
  case noEntryPoint
  /// The code could not be loaded.
  case loadFailed(String)
  /// An installed plug-in has the same version or a higher one.
  case notNewer(installed: String)
  /// A file operation failed.
  case cannotWrite(String)
}
