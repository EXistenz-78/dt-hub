import Foundation
import Testing

@testable import HubCore

/// The whole update against a test release served from a local folder: real URLSession, ditto, codesign and the swap.
/// Not run by default. Setup, in a scratch folder `F`:
/// - `F/running/DT Hub.app`: a copy of the app (0.9.0) the test replaces;
/// - `F/plugins/`: a plug-in folder holding an older `com.exiztenz.dthub.promptmasteri4.dthubplugin` (or any older copy of it);
/// - `F/rel/`: `latest/download/dthub-release.json` (from `Scripts/make_release_manifest.py`) and `download/v1.0.0-prova/*.zip`
///   with an app 1.0.0 and plug-ins `PromptMasterI4` and `SphereLight` at 9.9, all re-signed with `codesign --force --deep -s -`;
/// - `F/rel-bad/`: the same with the app's sha256 in the manifest set to zeros (`download` is a symlink to `../rel/download`);
/// - `python3 -m http.server 8765 --bind 127.0.0.1` in `F`.
/// Then, outside the sandbox (the network of `swift test` times out inside it):
/// `DTHUB_LIVE_UPDATE=F swift test --filter LiveUpdateTests`.
@MainActor
struct LiveUpdateTests {
  nonisolated static let folder = ProcessInfo.processInfo.environment["DTHUB_LIVE_UPDATE"]

  func controller(base: String, live: URL, work: URL) -> (UpdateController, PluginFolder) {
    let plugins = PluginFolder(root: live.appendingPathComponent("plugins"))
    let controller = UpdateController(
      checker: .live, installer: .live, replacer: .live,
      settings: UpdateSettings(defaults: UpdateSettingsTests.defaults()), appVersion: "0.9.0",
      appURL: live.appendingPathComponent("running/DT Hub.app"), appIdentifier: "com.exiztenz.DTHub",
      installedPlugins: { Dictionary(uniqueKeysWithValues: plugins.scan().compactMap(\.info).map { ($0.identifier, $0.version) }) },
      installPlugin: { try plugins.install($0, info: try PluginBundleReader.read($0)) }, workFolder: work,
      downloads: live.appendingPathComponent("downloads"), base: URL(string: base)!)
    return (controller, plugins)
  }

  @Test(.enabled(if: LiveUpdateTests.folder != nil))
  func aWrongChecksumInstallsNothingThenTheGoodReleaseUpdatesEverything() async throws {
    let live = URL(fileURLWithPath: Self.folder!)
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("LiveUpdateTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: work) }
    func appVersion() -> String? { AppReplacer.readInfo(live.appendingPathComponent("running/DT Hub.app"))?.version }

    // 1. A manifest whose app sha256 is wrong: the app is refused, the plug-in still installs.
    let (bad, plugins) = controller(base: "http://127.0.0.1:8765/rel-bad", live: live, work: work)
    await bad.checkNow()
    #expect(bad.offers.map(\.id) == ["app", "com.exiztenz.dthub.promptmasteri4"])
    await bad.install(Set(bad.offers.map(\.id)))
    guard case .results(let results) = bad.message else {
      Issue.record("no results")
      return
    }
    #expect(results.first { $0.id == "app" }?.error == .checksum)
    #expect(results.first { $0.id == "com.exiztenz.dthub.promptmasteri4" }?.error == nil)
    #expect(appVersion() == "0.9.0")
    #expect(plugins.installed("com.exiztenz.dthub.promptmasteri4")?.version == "9.9")
    #expect(plugins.installed("com.exiztenz.dthub.spherelight") == nil)

    // 2. The good release: the app is the only thing left to update (the plug-in is already at 9.9).
    let (good, _) = controller(base: "http://127.0.0.1:8765/rel", live: live, work: work)
    await good.checkNow()
    #expect(good.offers.map(\.id) == ["app"])
    await good.install(["app"])
    guard case .results(let second) = good.message else {
      Issue.record("no results")
      return
    }
    #expect(second.allSatisfy { $0.error == nil })
    #expect(appVersion() == "1.0.0")
    #expect(good.needsRelaunch)
    #expect(AppReplacer.readInfo(live.appendingPathComponent("running/DT Hub.app"))?.identifier == "com.exiztenz.DTHub")
  }
}
