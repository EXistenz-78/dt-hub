import Foundation
import Testing

@testable import HubCore

struct UpdateCheckerTests {
  final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.withLock { urls.append(url) } }
    var all: [URL] { lock.withLock { urls } }
  }

  func checker(_ answer: UpdateFetch, calls: Calls = Calls()) -> UpdateChecker {
    UpdateChecker(fetch: { url in
      calls.add(url)
      return answer
    })
  }

  @Test func aValidManifestIsGiven() async {
    let result = await checker(.ok(ReleaseManifestTests.json())).check(base: ReleaseManifestTests.base)
    guard case .manifest(let manifest) = result else {
      Issue.record("expected a manifest, got \(result)")
      return
    }
    #expect(manifest.tag == "v1.0.0")
  }

  @Test func garbageIsNoInformation() async {
    #expect(await checker(.ok(Data("<html>".utf8))).check(base: ReleaseManifestTests.base) == .noInformation)
  }

  @Test func aReleaseWithoutAManifestIsNoInformation() async {
    #expect(await checker(.missing).check(base: ReleaseManifestTests.base) == .noInformation)
  }

  @Test func aFailedRequestIsUnreachable() async {
    #expect(await checker(.failed).check(base: ReleaseManifestTests.base) == .unreachable)
  }

  @Test func itAsksOnceAndForTheManifestURL() async {
    let calls = Calls()
    _ = await checker(.failed, calls: calls).check(base: ReleaseManifestTests.base)
    #expect(calls.all == [UpdateEndpoint.manifestURL(base: ReleaseManifestTests.base)])
  }
}
