import AppKit
import SwiftUI

/// "Open Privacy & Security": opens System Settings on Files & Folders, or on Privacy & Security
/// if macOS no longer knows that address.
struct PrivacySettingsLink: View {
  private static let filesAndFolders = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
  private static let fallback = "x-apple.systempreferences:com.apple.preference.security"

  /// Opens System Settings on Files & Folders (or Privacy & Security).
  static func open() {
    if let url = URL(string: filesAndFolders), NSWorkspace.shared.open(url) { return }
    if let url = URL(string: fallback) { NSWorkspace.shared.open(url) }
  }

  var body: some View {
    Button("prefs.privacy.open") { Self.open() }
  }
}
