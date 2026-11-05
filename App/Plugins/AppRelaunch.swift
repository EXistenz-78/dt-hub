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
    NSApp.terminate(nil)
  }
}
