import Foundation
import HubKit
import Testing

@testable import HubCore

struct GalleryIndexTests {
  private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
  }

  private struct Setup {
    let root: URL
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }
    var cache: URL { root.appendingPathComponent("cache/gallery-index.json") }
    var index: GalleryIndex { GalleryIndex(cacheURL: cache) }
  }

  private func makeSetup() -> Setup {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gidx-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return Setup(root: root)
  }

  private func job(_ prompt: String, model: String = "m.ckpt", seed: UInt32 = 1) -> GenerationJob {
    GenerationJob(prompt: prompt, model: model, parameters: GenerationParameters(seed: seed, randomSeed: false))
  }

  private let day = Date(timeIntervalSince1970: 1_790_000_000)

  @discardableResult
  private func save(_ prompt: String, in folder: URL, model: String = "m.ckpt", seed: UInt32 = 1, offset: TimeInterval = 0) throws -> URL {
    try PNGImageStore(folder: folder).save(
      testImage(), job: job(prompt, model: model, seed: seed), index: 0, date: day.addingTimeInterval(offset))
  }

  private func project(_ name: String, in setup: Setup) throws -> Project {
    try ProjectCatalog(outputFolder: setup.output).create(named: name)
  }

  @Test func indexesEveryProjectAndNamesTheProject() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup), b = try project("B", in: setup)
    try save("uno", in: a.folder, seed: 1)
    try save("due", in: a.folder, seed: 2, offset: 60)
    try save("tre", in: b.folder, seed: 3, offset: 120)
    let entries = setup.index.refresh(outputFolder: setup.output, extraFolders: [])
    #expect(entries.count == 3)
    #expect(Set(entries.map(\.project)) == ["A", "B"])
    #expect(entries.map(\.date) == entries.map(\.date).sorted(by: >))
  }

  @Test func searchTextHoldsPromptModelAndIsFolded() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup)
    try save("Città di luna", in: a.folder, model: "flux2_klein.ckpt")
    let text = try #require(setup.index.refresh(outputFolder: setup.output, extraFolders: []).first).searchText
    #expect(text.contains("citta di luna"))
    #expect(text.contains("flux2_klein"))
  }

  @Test func secondRefreshRereadsOnlyChangedFiles() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup)
    try save("uno", in: a.folder, seed: 1)
    try save("due", in: a.folder, seed: 2, offset: 60)
    let counter = Counter()
    let reader: @Sendable (URL) -> String = { _ in counter.bump(); return "" }
    _ = setup.index.refresh(outputFolder: setup.output, extraFolders: [], reader: reader)
    #expect(counter.count == 2)
    _ = setup.index.refresh(outputFolder: setup.output, extraFolders: [], reader: reader)
    #expect(counter.count == 2, "nothing changed: nothing is read again")
    try save("tre", in: a.folder, seed: 3, offset: 120)
    let entries = setup.index.refresh(outputFolder: setup.output, extraFolders: [], reader: reader)
    #expect(counter.count == 3 && entries.count == 3)
  }

  @Test func removedFileLeavesTheIndex() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup)
    let gone = try save("uno", in: a.folder, seed: 1)
    try save("due", in: a.folder, seed: 2, offset: 60)
    #expect(setup.index.refresh(outputFolder: setup.output, extraFolders: []).count == 2)
    try FileManager.default.removeItem(at: gone)
    #expect(setup.index.refresh(outputFolder: setup.output, extraFolders: []).count == 1)
  }

  @Test func hiddenFoldersAreSkippedInExtraFolders() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let extra = setup.root.appendingPathComponent("extra", isDirectory: true)
    try save("visibile", in: extra)
    try save("nascosta", in: extra.appendingPathComponent(".dthub/Control", isDirectory: true), seed: 2)
    let entries = setup.index.refresh(outputFolder: setup.output, extraFolders: [extra])
    #expect(entries.count == 1)
    #expect(entries.first?.project == "extra")
  }

  @Test func extraFolderInsideTheOutputIsNotCountedTwice() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup)
    try save("uno", in: a.folder)
    let entries = setup.index.refresh(outputFolder: setup.output, extraFolders: [a.folder])
    #expect(entries.count == 1)
  }

  @Test func unreadablePNGStillEnters() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let extra = setup.root.appendingPathComponent("extra", isDirectory: true)
    try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
    try Data([1, 2, 3, 4]).write(to: extra.appendingPathComponent("Rotta.png"))
    let entries = setup.index.refresh(outputFolder: setup.output, extraFolders: [extra])
    #expect(entries.count == 1)
    #expect(entries.first?.searchText.contains("rotta.png") == true)
  }

  @Test func cacheSurvivesBetweenInstances() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let a = try project("A", in: setup)
    try save("uno", in: a.folder)
    let fresh = setup.index.refresh(outputFolder: setup.output, extraFolders: [])
    #expect(GalleryIndex(cacheURL: setup.cache).cached() == fresh)
  }

  @Test func descriptionIsReadBack() throws {
    let setup = makeSetup()
    defer { try? FileManager.default.removeItem(at: setup.root) }
    let url = try save("una candela", in: setup.root.appendingPathComponent("p", isDirectory: true))
    #expect(PNGImageStore.description(in: url) == "una candela")
  }
}
