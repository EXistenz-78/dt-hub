import Foundation
import HubKit
import Testing

@testable import DTBridge

struct CloudCatalogLimitsTests {
  func cache() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("limits-\(UUID()).json") }

  func catalog(
    cache: URL, echo: @escaping @Sendable () async throws -> CloudEcho
  ) -> CloudCatalog {
    CloudCatalog(
      filesCache: cache, lorasCache: cache.appendingPathExtension("loras"), echo: echo,
      download: { _ in throw URLError(.notConnectedToInternet) })
  }

  @Test func noPolicyGivesTheStandardLimits() async {
    let cloud = catalog(cache: cache()) { CloudEcho(files: ["a.ckpt"]) }
    #expect(await cloud.limits() == .standard)
  }

  @Test func anActivePolicyOverridesTheDefault() async {
    let expiry = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let cloud = catalog(cache: cache()) {
      CloudEcho(files: ["a.ckpt"], plus: 20_000, community: 5_000, expireAt: expiry)
    }
    let limits = await cloud.limits()
    #expect(limits.limit == 20_000)
    #expect(limits.community == 5_000)
    #expect(limits.expiresAt != nil)
  }

  @Test func anExpiredPolicyIsIgnored() async {
    let past = Int64(Date().addingTimeInterval(-1).timeIntervalSince1970)
    let cloud = catalog(cache: cache()) {
      CloudEcho(files: ["a.ckpt"], plus: 20_000, community: 5_000, expireAt: past)
    }
    #expect(await cloud.limits() == .standard)
  }

  @Test func aPolicyWithoutAPlusValueIsIgnored() async {
    let expiry = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let cloud = catalog(cache: cache()) {
      CloudEcho(files: ["a.ckpt"], plus: 0, community: 5_000, expireAt: expiry)
    }
    #expect(await cloud.limits() == .standard)
  }

  @Test func anOldCacheOfFilesOnlyStillReads() async throws {
    let url = cache()
    try JSONEncoder().encode(["a.ckpt"]).write(to: url)
    let cloud = catalog(cache: url) { throw URLError(.notConnectedToInternet) }
    #expect(await cloud.files() == ["a.ckpt"])
    #expect(await cloud.limits() == .standard)
  }

  @Test func aSavedPolicyIsKeptWhileTheEchoFailsAndUntilItExpires() async {
    let url = cache()
    let expiry = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let first = catalog(cache: url) { CloudEcho(files: ["a.ckpt"], plus: 20_000, community: 0, expireAt: expiry) }
    #expect(await first.limits().limit == 20_000)
    let offline = catalog(cache: url) { throw URLError(.notConnectedToInternet) }
    #expect(await offline.limits().limit == 20_000)
    #expect(await offline.limits(now: Date().addingTimeInterval(7200)) == .standard)
  }
}
