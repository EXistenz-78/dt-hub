import Foundation
import Testing

@testable import HubCore

@MainActor
struct CardExpansionStoreTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("CardExpansionStoreTests-\(UUID())", isDirectory: true)
      .appendingPathComponent("cards.json")
  }

  @Test func untouchedCardsUseTheirDefault() {
    let store = CardExpansionStore(fileURL: tempFile())
    #expect(store.isExpanded("sampling"))
    #expect(!store.isExpanded("seed", default: false))
  }

  @Test func remembersTheStateAcrossLaunches() {
    let file = tempFile()
    CardExpansionStore(fileURL: file).setExpanded(false, for: "sampling")
    #expect(!CardExpansionStore(fileURL: file).isExpanded("sampling"))
  }

  @Test func anUnreadableFileMeansDefaults() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file)
    #expect(CardExpansionStore(fileURL: file).isExpanded("sampling"))
  }
}
