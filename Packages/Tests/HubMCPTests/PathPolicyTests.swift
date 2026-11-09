import Foundation
import Testing

@testable import HubMCP

struct PathPolicyTests {
  let root: URL
  let outside: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("pathpolicy-\(UUID().uuidString)")
    root = base.appendingPathComponent("root")
    outside = base.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    for url in [root.appendingPathComponent("a.png"), outside.appendingPathComponent("x.png"),
      root.appendingPathComponent("notes.txt")]
    {
      try Data([0]).write(to: url)
    }
  }

  @Test func insideRootIsResolved() {
    let policy = PathPolicy(roots: [root])
    #expect(policy.resolve(root.appendingPathComponent("a.png").path) != nil)
  }

  @Test func dotDotEscapeIsRefused() {
    let policy = PathPolicy(roots: [root])
    #expect(policy.resolve(root.path + "/../outside/x.png") == nil)
  }

  @Test func symlinkToOutsideIsRefused() throws {
    let link = root.appendingPathComponent("link.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("x.png"))
    #expect(PathPolicy(roots: [root]).resolve(link.path) == nil)
  }

  @Test func nonImageExtensionIsRefused() {
    #expect(PathPolicy(roots: [root]).resolve(root.appendingPathComponent("notes.txt").path) == nil)
  }

  @Test func relativePathIsRefused() {
    #expect(PathPolicy(roots: [root]).resolve("a.png") == nil)
  }

  @Test func rootPrefixTrickIsRefused() throws {
    let evil = root.deletingLastPathComponent().appendingPathComponent("root-evil")
    try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
    try Data([0]).write(to: evil.appendingPathComponent("x.png"))
    #expect(PathPolicy(roots: [root]).resolve(evil.appendingPathComponent("x.png").path) == nil)
  }

  @Test func missingFileIsRefused() {
    #expect(PathPolicy(roots: [root]).resolve(root.appendingPathComponent("nope.png").path) == nil)
  }
}
