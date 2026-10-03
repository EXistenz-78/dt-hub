import Foundation

/// Builds the sample plug-in of the repository the way an author does (`swift build` of its package, then
/// `make-bundle.sh`), once per test run.
enum SampleBundle {
  /// The repository root: Packages/Tests/PluginHostTests/<this file>.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("PluginHostTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

  static let dylib: URL? = {
    let scratch = work.appendingPathComponent("build", isDirectory: true)
    guard run("/usr/bin/env", ["swift", "build", "--package-path", root.appendingPathComponent("PluginKit/Examples/Sample").path, "--scratch-path", scratch.path]) else { return nil }
    let enumerator = FileManager.default.enumerator(at: scratch, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      if url.lastPathComponent == "libSamplePlugin.dylib" { return url }
    }
    return nil
  }()

  /// A bundle of the sample: its identifier, version, principal class and contract are the Info.plist's.
  static func make(
    id: String = "com.example.dthub.sample", version: String = "1.0", principal: String = "SampleEntry", contract: Int = 1
  ) -> URL? {
    guard let dylib else { return nil }
    let out = work.appendingPathComponent("\(UUID().uuidString)/Sample.dthubplugin", isDirectory: true)
    try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let script = root.appendingPathComponent("PluginKit/Scripts/make-bundle.sh").path
    guard run(script, [dylib.path, out.path, id, "Sample", version, principal, String(contract)]) else { return nil }
    return out
  }

  private static func run(_ tool: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }
}
