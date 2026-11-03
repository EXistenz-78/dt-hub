import Foundation
import Testing

@testable import HubCore

struct AppReplacerTests {
  static let identifier = "com.exiztenz.DTHub"

  final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
  }

  /// A running app and a new one in a temporary folder, each a folder with an Info.plist.
  struct Scene {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppReplacerTests-\(UUID().uuidString)")
    var apps: URL { root.appendingPathComponent("Applications") }
    var running: URL { apps.appendingPathComponent("DT Hub.app") }
    var work: URL { root.appendingPathComponent("work") }
    var new: URL { work.appendingPathComponent("new").appendingPathComponent("DT Hub.app") }
    var downloads: URL { root.appendingPathComponent("Downloads") }

    init(running runningVersion: String = "0.9.0", new newVersion: String = "1.0.0", newIdentifier: String = identifier)
      throws
    {
      try Self.makeApp(running, identifier: AppReplacerTests.identifier, version: runningVersion)
      try Self.makeApp(new, identifier: newIdentifier, version: newVersion)
      try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    }

    static func makeApp(_ url: URL, identifier: String, version: String) throws {
      let contents = url.appendingPathComponent("Contents")
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    }

    func version(of app: URL) -> String? {
      guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
        let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
      else { return nil }
      return info["CFBundleShortVersionString"] as? String
    }
  }

  func replacer(
    signed: Bool = true, trashed: Box<[URL]> = Box([]),
    move: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
  ) -> AppReplacer {
    AppReplacer(verifySignature: { _ in signed }, move: move, trash: { url in trashed.value.append(url) })
  }

  func replace(_ replacer: AppReplacer, _ scene: Scene) async throws(UpdateError) -> AppReplaceOutcome {
    try await replacer.replace(
      running: scene.running, runningIdentifier: Self.identifier, runningVersion: "0.9.0", with: scene.new,
      work: scene.work, downloads: scene.downloads)
  }

  @Test func aNewerAppTakesThePlaceOfTheOldOne() async throws {
    let scene = try Scene()
    let trashed = Box<[URL]>([])
    let outcome = try await replace(replacer(trashed: trashed), scene)
    #expect(outcome == .replaced)
    #expect(scene.version(of: scene.running) == "1.0.0")
    #expect(trashed.value.count == 1)
    #expect(scene.version(of: trashed.value[0]) == "0.9.0")
  }

  @Test func aFailureWhilePlacingTheNewAppPutsTheOldBack() async throws {
    let scene = try Scene()
    let calls = Box(0)
    let failing = replacer { from, to in
      calls.value += 1
      // The second move is the new app into place.
      if calls.value == 2 { throw CocoaError(.fileWriteOutOfSpace) }
      try FileManager.default.moveItem(at: from, to: to)
    }
    await #expect {
      _ = try await replace(failing, scene)
    } throws: { error in
      if case UpdateError.cannotWrite = error { return true }
      return false
    }
    #expect(scene.version(of: scene.running) == "0.9.0")
  }

  @Test func anotherIdentifierIsRefused() async throws {
    let scene = try Scene(newIdentifier: "com.other.app")
    await #expect(throws: UpdateError.identityMismatch) { _ = try await replace(replacer(), scene) }
    #expect(scene.version(of: scene.running) == "0.9.0")
  }

  @Test func anOlderOrSameVersionIsRefused() async throws {
    for version in ["0.9.0", "0.8.0"] {
      let scene = try Scene(new: version)
      await #expect(throws: UpdateError.notNewer) { _ = try await replace(replacer(), scene) }
    }
  }

  @Test func aBrokenSignatureIsRefusedAndNothingMoves() async throws {
    let scene = try Scene()
    await #expect(throws: UpdateError.signature) { _ = try await replace(replacer(signed: false), scene) }
    #expect(scene.version(of: scene.running) == "0.9.0")
    #expect(scene.version(of: scene.new) == "1.0.0")
  }

  @Test func anUnwritableFolderRevealsTheNewAppInDownloads() async throws {
    let scene = try Scene()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: scene.apps.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scene.apps.path) }
    let outcome = try await replace(replacer(), scene)
    guard case .revealed(let url) = outcome else {
      Issue.record("expected .revealed, got \(outcome)")
      return
    }
    #expect(url.deletingLastPathComponent().standardizedFileURL == scene.downloads.standardizedFileURL)
    #expect(scene.version(of: url) == "1.0.0")
    #expect(scene.version(of: scene.running) == "0.9.0")
  }

  @Test func relaunchArgumentsWaitForTheProcessThenOpen() {
    let arguments = AppReplacer.relaunchArguments(appAt: URL(fileURLWithPath: "/Applications/DT Hub.app"), pid: 123)
    #expect(arguments.first == "-c")
    #expect(arguments[1].contains("kill -0 123"))
    #expect(arguments[1].contains("open \"/Applications/DT Hub.app\""))
  }
}
