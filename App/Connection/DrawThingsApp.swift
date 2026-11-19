import AppKit

/// The Draw Things app, whose own server DT Hub connects to in "DT" mode.
enum DrawThingsApp {
  static let bundleIdentifier = "com.liuliu.draw-things"

  /// Opens the app (and brings it forward) unless it is already running; does nothing when it is not installed. The
  /// server inside it is not started: that is done there, by hand.
  static func open(workspace: NSWorkspace = .shared) {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty,
      let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    workspace.openApplication(at: url, configuration: configuration)
  }
}
