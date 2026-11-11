import AppKit
import Foundation
import HubCore

/// Quits DT Hub and opens it again (a plug-in turned on, off, replaced or removed, or an installed update, takes effect
/// at the next launch).
enum AppRelaunch {
  @MainActor
  static func relaunch() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // The script waits until this instance is gone (and stops it if it does not quit), then opens the app once.
    process.arguments = RelaunchScript.arguments(
      pid: ProcessInfo.processInfo.processIdentifier, appPath: Bundle.main.bundleURL.path)
    try? process.run()
    // A sheet that is open (the details of an update) makes the quit fail: AppKit beeps and the app stays, until the
    // script above stops it after its grace time. A SwiftUI sheet is not closed by `endSheet` alone (its `isPresented`
    // flag stays true), so the caller dismisses its own sheet first; this closes whatever is left, and the quit waits
    // until no sheet is attached (two seconds at most).
    for window in NSApp.windows {
      if let sheet = window.attachedSheet { window.endSheet(sheet) }
    }
    quit(whenSheetsAreGone: Date().addingTimeInterval(2))
  }

  @MainActor
  private static func quit(whenSheetsAreGone deadline: Date) {
    let open = NSApp.windows.contains { $0.attachedSheet != nil }
    if !open || Date() >= deadline {
      NSApp.terminate(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { quit(whenSheetsAreGone: deadline) }
  }
}
