import Foundation
import Testing

@testable import HubCore

struct UpdateInstallerTests {
  static let sha = String(repeating: "ab", count: 32)
  static let pluginID = "com.exiztenz.dthub.promptmasteri4"

  static func item(_ id: String = pluginID, version: String = "1.2", asset: String = "PromptMasterI4.dthubplugin.zip")
    -> ReleaseItem
  {
    ReleaseItem(
      id: id, name: "X", version: version, asset: asset, sha256: sha, size: 10,
      contract: id == "app" ? nil : 1)
  }

  static func manifest(_ item: ReleaseItem) -> ReleaseManifest {
    ReleaseManifest(tag: "v1.0.0", app: UpdatePlanTests.item("app", "1.0.0", contract: nil), plugins: [item])
  }

  /// A bundle folder with an Info.plist, as the unzip would leave it.
  static func makeBundle(in folder: URL, name: String, identifier: String, version: String) throws {
    let contents = folder.appendingPathComponent(name).appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": identifier, "CFBundleName": "X", "CFBundleShortVersionString": version,
      "NSPrincipalClass": "Main", "DTHubContract": 1,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
  }

  struct Failure: Error {}

  func installer(
    bundles: [(name: String, id: String, version: String)] = [
      (name: "PromptMasterI4.dthubplugin", id: pluginID, version: "1.2")
    ], checksum: String? = sha, downloadFails: Bool = false
  ) -> UpdateInstaller {
    UpdateInstaller(
      download: { _, destination, progress in
        if downloadFails { throw Failure() }
        try Data("zip".utf8).write(to: destination)
        progress(1)
      },
      unzip: { _, folder in
        for bundle in bundles {
          try Self.makeBundle(in: folder, name: bundle.name, identifier: bundle.id, version: bundle.version)
        }
      },
      sha256: { _ in checksum })
  }

  func fetch(_ installer: UpdateInstaller, item: ReleaseItem = item()) async throws(UpdateError) -> (URL, URL) {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)")
    let bundle = try await installer.fetchBundle(
      item, manifest: Self.manifest(item), base: ReleaseManifestTests.base, work: work, progress: { _ in })
    return (bundle, work)
  }

  @Test func aGoodPluginComesBackAsItsBundle() async throws {
    let (bundle, _) = try await fetch(installer())
    #expect(bundle.lastPathComponent == "PromptMasterI4.dthubplugin")
  }

  @Test func aWrongChecksumThrowsAndLeavesNoBundle() async {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)")
    let item = Self.item()
    await #expect(throws: UpdateError.checksum) {
      try await installer(checksum: String(repeating: "cd", count: 32)).fetchBundle(
        item, manifest: Self.manifest(item), base: ReleaseManifestTests.base, work: work, progress: { _ in })
    }
    let left = (try? FileManager.default.subpathsOfDirectory(atPath: work.path)) ?? []
    #expect(!left.contains { $0.hasSuffix(".dthubplugin") })
  }

  @Test func twoBundlesInOneZipFail() async {
    let two = installer(bundles: [
      (name: "A.dthubplugin", id: Self.pluginID, version: "1.2"),
      (name: "B.dthubplugin", id: Self.pluginID, version: "1.2"),
    ])
    await #expect(throws: UpdateError.noBundle) { _ = try await fetch(two) }
  }

  @Test func aZipWithNoBundleFails() async {
    await #expect(throws: UpdateError.noBundle) { _ = try await fetch(installer(bundles: [])) }
  }

  @Test func aBundleWithAnotherIdentifierOrVersionFails() async {
    await #expect(throws: UpdateError.identityMismatch) {
      _ = try await fetch(installer(bundles: [(name: "X.dthubplugin", id: "com.other.plugin", version: "1.2")]))
    }
    await #expect(throws: UpdateError.identityMismatch) {
      _ = try await fetch(installer(bundles: [(name: "X.dthubplugin", id: Self.pluginID, version: "9.9")]))
    }
  }

  @Test func theAppIsAnAppFolderNotAPlugin() async throws {
    let app = Self.item("app", version: "1.0.0", asset: "DT-Hub-1.0.0-macOS-arm64.zip")
    let good = installer(bundles: [(name: "DT Hub.app", id: "com.exiztenz.DTHub", version: "1.0.0")])
    let (bundle, _) = try await fetch(good, item: app)
    #expect(bundle.pathExtension == "app")
    let wrong = installer(bundles: [(name: "X.dthubplugin", id: Self.pluginID, version: "1.0.0")])
    await #expect(throws: UpdateError.noBundle) { _ = try await fetch(wrong, item: app) }
  }

  @Test func aFailingDownloadIsReported() async {
    await #expect {
      _ = try await fetch(installer(downloadFails: true))
    } throws: { error in
      if case UpdateError.download = error { return true }
      return false
    }
  }
}
