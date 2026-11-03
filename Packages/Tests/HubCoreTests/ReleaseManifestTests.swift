import Foundation
import Testing

@testable import HubCore

struct ReleaseManifestTests {
  static let sha = String(repeating: "ab", count: 32)

  /// A manifest as the release script writes it; the pieces can be replaced to break it.
  static func json(
    schema: Int = 1, tag: String = "v1.0.0", appAsset: String = "DT-Hub-1.0.0-macOS-arm64.zip",
    appVersion: String = "1.0.0", pluginAsset: String = "PromptMasterI4.dthubplugin.zip", sha256: String = sha,
    includeTag: Bool = true, includeApp: Bool = true
  ) -> Data {
    // A backslash in a name must reach the file as a backslash, not as a JSON escape.
    let appAsset = appAsset.replacingOccurrences(of: "\\", with: "\\\\")
    let pluginAsset = pluginAsset.replacingOccurrences(of: "\\", with: "\\\\")
    let tagLine = includeTag ? "\"tag\": \"\(tag)\"," : ""
    let appLine =
      includeApp
      ? "\"app\": {\"version\": \"\(appVersion)\", \"asset\": \"\(appAsset)\", \"sha256\": \"\(sha)\", \"size\": 26296563},"
      : ""
    return Data(
      """
      {"schema": \(schema), \(tagLine) \(appLine)
       "plugins": [{"id": "com.exiztenz.dthub.promptmasteri4", "name": "Prompt Master I4", "version": "1.2",
         "contract": 1, "asset": "\(pluginAsset)", "sha256": "\(sha256)", "size": 608492}]}
      """.utf8)
  }

  static let base = URL(string: "https://github.com/EXistenz-78/dt-hub/releases")!

  @Test func aValidManifestIsRead() throws {
    let manifest = try #require(ReleaseManifest.parse(Self.json()))
    #expect(manifest.tag == "v1.0.0")
    #expect(manifest.app.id == "app" && manifest.app.name == "DT Hub" && manifest.app.contract == nil)
    #expect(manifest.app.version == "1.0.0")
    #expect(manifest.plugins.count == 1)
    #expect(manifest.plugins[0].id == "com.exiztenz.dthub.promptmasteri4")
    #expect(manifest.plugins[0].size == 608492)
    #expect(manifest.plugins[0].contract == 1)
  }

  @Test func aHigherSchemaIsRefused() {
    #expect(ReleaseManifest.parse(Self.json(schema: 2)) == nil)
  }

  @Test func hostileAssetNamesAreRefused() {
    for name in ["../x.zip", "a/b.zip", "a\\b.zip", ".."] {
      #expect(ReleaseManifest.parse(Self.json(appAsset: name)) == nil, "app: \(name)")
      #expect(ReleaseManifest.parse(Self.json(pluginAsset: name)) == nil, "plug-in: \(name)")
    }
    #expect(ReleaseManifest.parse(Self.json(appAsset: "")) == nil)
    #expect(ReleaseManifest.parse(Self.json(pluginAsset: "")) == nil)
  }

  @Test func badChecksumsAreRefused() {
    #expect(ReleaseManifest.parse(Self.json(sha256: String(repeating: "a", count: 63))) == nil)
    #expect(ReleaseManifest.parse(Self.json(sha256: String(repeating: "g", count: 64))) == nil)
  }

  @Test func missingFieldsAreRefused() {
    #expect(ReleaseManifest.parse(Self.json(includeTag: false)) == nil)
    #expect(ReleaseManifest.parse(Self.json(includeApp: false)) == nil)
    #expect(ReleaseManifest.parse(Self.json(appVersion: "")) == nil)
    #expect(ReleaseManifest.parse(Data("not json".utf8)) == nil)
  }

  @Test func downloadURLsFollowTheTag() throws {
    let manifest = try #require(ReleaseManifest.parse(Self.json()))
    #expect(
      manifest.downloadURL(for: manifest.app, base: Self.base).absoluteString
        == "https://github.com/EXistenz-78/dt-hub/releases/download/v1.0.0/DT-Hub-1.0.0-macOS-arm64.zip")
    #expect(
      UpdateEndpoint.manifestURL(base: Self.base).absoluteString
        == "https://github.com/EXistenz-78/dt-hub/releases/latest/download/dthub-release.json")
  }
}
