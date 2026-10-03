import AppKit
import Foundation

/// Quits DT Hub and opens it again (a plug-in turned on, off, replaced or removed takes effect at the next launch).
enum AppRelaunch {
  @MainActor
  static func relaunch() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // A moment for this instance to quit, then a new one of the same app.
    process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", Bundle.main.bundleURL.path]
    try? process.run()
    NSApp.terminate(nil)
  }
}
