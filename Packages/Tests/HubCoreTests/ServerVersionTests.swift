import Foundation
import Testing

@testable import HubCore

struct ServerVersionTests {
  static let old = ServerRelease(tag: "v1", publishedAt: Date(timeIntervalSince1970: 100), sha256: "aa")
  static let new = ServerRelease(tag: "v2", publishedAt: Date(timeIntervalSince1970: 200), sha256: "bb")

  func checker(releases: [ServerRelease]?, hash: String?) -> ServerVersionChecker {
    ServerVersionChecker(releases: { releases }, hash: { _ in hash })
  }

  @Test func theNewestReleaseIsUpToDate() async {
    let result = await checker(releases: [Self.old, Self.new], hash: "bb").check(programAt: "/x")
    #expect(result.info == ServerVersionInfo(state: .upToDate, installed: "v2", latest: "v2"))
    #expect(result.hash == "bb")
  }

  @Test func anOlderReleaseHasAnUpdate() async {
    let result = await checker(releases: [Self.new, Self.old], hash: "aa").check(programAt: "/x")
    #expect(result.info == ServerVersionInfo(state: .updateAvailable, installed: "v1", latest: "v2"))
  }

  @Test func aProgramOfNoReleaseIsUnidentifiedAndTheLatestIsShown() async {
    let result = await checker(releases: [Self.old, Self.new], hash: "zz").check(programAt: "/x")
    #expect(result.info == ServerVersionInfo(state: .unidentified, installed: nil, latest: "v2"))
  }

  @Test func withoutGitHubTheRememberedVersionIsShown() async {
    let offline = checker(releases: nil, hash: "aa")
    let remembered = await offline.check(programAt: "/x", remembered: (hash: "aa", tag: "v1"))
    #expect(remembered.info == ServerVersionInfo(state: .couldNotCheck, installed: "v1", latest: nil))
    let other = await offline.check(programAt: "/x", remembered: (hash: "other", tag: "v1"))
    #expect(other.info.installed == nil && other.info.state == .couldNotCheck)
  }

  @Test func noProgramNoLookup() async {
    let result = await checker(releases: [Self.new], hash: nil).check(programAt: "/x")
    #expect(result.info.state == .noProgram)
    let empty = await checker(releases: [Self.new], hash: "bb").check(programAt: "")
    #expect(empty.info.state == .noProgram)
  }

  @Test func theHashOfAFileIsItsSha256() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString)")
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(
      ServerVersionChecker.sha256(ofFileAt: url.path)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(ServerVersionChecker.sha256(ofFileAt: "/no/such/file") == nil)
  }

  @Test func theGitHubListKeepsReleasesWithTheProgramAndItsDigest() {
    let json = """
      [{"tag_name":"v26.0928.0","published_at":"2026-09-28T17:41:07Z","draft":false,"prerelease":false,
        "assets":[{"name":"draw-things-cli","digest":"sha256:11"},{"name":"gRPCServerCLI-macOS","digest":"sha256:d15c"}]},
       {"tag_name":"v0","published_at":"2026-01-01T00:00:00Z","assets":[{"name":"gRPCServerCLI-macOS","digest":null}]},
       {"tag_name":"beta","published_at":"2026-10-01T00:00:00Z","prerelease":true,
        "assets":[{"name":"gRPCServerCLI-macOS","digest":"sha256:ee"}]}]
      """
    let releases = GitHubReleases.parse(Data(json.utf8))
    #expect(releases?.map(\.tag) == ["v26.0928.0"])
    #expect(releases?.first?.sha256 == "d15c")
    #expect(GitHubReleases.parse(Data("{}".utf8)) == nil)
  }
}
