import Foundation
import Testing

@testable import HubCore

/// The relaunch must open the new app only once the old one is gone, and make sure the old one goes.
struct RelaunchScriptTests {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch-\(UUID().uuidString)", isDirectory: true)

  private func shell(_ script: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    try process.run()
    return process
  }

  /// Runs the script for `old`; `touch` stands for `open` and leaves a marker file instead of opening an app.
  private func runScript(waitingFor old: Process, grace: Int) throws -> (process: Process, marker: URL) {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let marker = folder.appendingPathComponent("opened")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = RelaunchScript.arguments(
      pid: old.processIdentifier, appPath: marker.path, openCommand: "/usr/bin/touch", grace: grace)
    try process.run()
    return (process, marker)
  }

  @Test func theNewAppOpensOnlyAfterTheOldOneHasQuit() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = try shell("sleep 1.5")
    let (script, marker) = try runScript(waitingFor: old, grace: 10)
    Thread.sleep(forTimeInterval: 0.7)
    // The old one is still running: nothing has been opened (the old fixed one-second wait would have).
    #expect(old.isRunning)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    script.waitUntilExit()
    #expect(!old.isRunning)
    #expect(FileManager.default.fileExists(atPath: marker.path))
  }

  @Test func anOldOneThatDoesNotQuitIsStoppedAndThenTheNewOneOpens() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    // Ignores the polite request to quit, like an app whose quit is stuck.
    let old = try shell("trap '' TERM; while true; do sleep 0.1; done")
    Thread.sleep(forTimeInterval: 0.3)
    let (script, marker) = try runScript(waitingFor: old, grace: 1)
    script.waitUntilExit()
    #expect(!old.isRunning)
    #expect(FileManager.default.fileExists(atPath: marker.path))
  }
}
