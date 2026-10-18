import AppKit
import SwiftUI

/// "Open Privacy & Security": opens System Settings on Files & Folders, or on Privacy & Security
/// if macOS no longer knows that address.
struct PrivacySettingsLink: View {
  private static let filesAndFolders = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
  private static let fallback = "x-apple.systempreferences:com.apple.preference.security"

  var body: some View {
    Button("prefs.privacy.open") {
      if let url = URL(string: Self.filesAndFolders), NSWorkspace.shared.open(url) { return }
      if let url = URL(string: Self.fallback) { NSWorkspace.shared.open(url) }
    }
  }
}
