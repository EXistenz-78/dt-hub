import Foundation
import Testing

@testable import HubCore

struct UpdatePlanTests {
  static let sha = String(repeating: "ab", count: 32)

  static func item(_ id: String, _ version: String, contract: Int? = 1, name: String? = nil) -> ReleaseItem {
    ReleaseItem(
      id: id, name: name ?? id, version: version, asset: "\(id).zip", sha256: sha, size: 1000, contract: contract)
  }

  static func manifest(app: String = "1.0.0", plugins: [ReleaseItem] = []) -> ReleaseManifest {
    ReleaseManifest(tag: "v\(app)", app: item("app", app, contract: nil, name: "DT Hub"), plugins: plugins)
  }

  static func ids(_ offers: [UpdateOffer]) -> [String] { offers.map(\.id) }

  func make(_ manifest: ReleaseManifest, app: String = "0.9.0", installed: [String: String] = [:], contracts: Set<Int> = [1])
    -> [UpdateOffer]
  {
    UpdatePlan.make(manifest: manifest, appVersion: app, installedPlugins: installed, supportedContracts: contracts)
  }

  @Test func anAppNewerThanTheRunningOneIsOffered() {
    let offers = make(Self.manifest(app: "1.0.0"), app: "0.9.0")
    #expect(Self.ids(offers) == ["app"])
    #expect(offers[0].installed == "0.9.0" && offers[0].isApp)
  }

  @Test func anAppOfTheSameOrAnOlderVersionIsNotOffered() {
    #expect(make(Self.manifest(app: "1.0.0"), app: "1.0.0").isEmpty)
    #expect(make(Self.manifest(app: "1.0.0"), app: "1.1.0").isEmpty)
  }

  @Test func versionsAreComparedByNumber() {
    let manifest = Self.manifest(app: "0.9.0", plugins: [Self.item("p", "1.10")])
    #expect(Self.ids(make(manifest, installed: ["p": "1.9"])) == ["p"])
    #expect(make(manifest, installed: ["p": "1.10"]).isEmpty)
  }

  @Test func onlyInstalledPluginsAreOffered() {
    let manifest = Self.manifest(app: "0.9.0", plugins: [Self.item("a", "2"), Self.item("b", "2")])
    #expect(Self.ids(make(manifest, installed: ["b": "1"])) == ["b"])
  }

  @Test func theAppComesFirstThenThePluginsByName() {
    let manifest = Self.manifest(
      app: "1.0.0", plugins: [Self.item("z", "2", name: "Zeta"), Self.item("a", "2", name: "Alfa")])
    #expect(Self.ids(make(manifest, installed: ["a": "1", "z": "1"])) == ["app", "a", "z"])
  }

  @Test func aPluginOfAnUnsupportedContractWaits() {
    let manifest = Self.manifest(app: "0.9.0", plugins: [Self.item("p", "2", contract: 2)])
    #expect(make(manifest, installed: ["p": "1"], contracts: [1]).isEmpty)
    #expect(Self.ids(make(manifest, installed: ["p": "1"], contracts: [1, 2])) == ["p"])
  }

  @Test func visibleHidesWhatWasPutOffAtTheSameVersion() {
    let offers = make(Self.manifest(app: "1.0.0"))
    #expect(UpdatePlan.visible(offers, dismissed: ["app": "1.0.0"]).isEmpty)
    #expect(UpdatePlan.visible(offers, dismissed: ["app": "0.9.5"]).count == 1)
    #expect(UpdatePlan.visible(offers, dismissed: ["app": "1.1.0"]).isEmpty)
    #expect(UpdatePlan.visible(offers, dismissed: [:]).count == 1)
  }
}
