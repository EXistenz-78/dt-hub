import Foundation
import Testing

@testable import HubCore

struct GalleryStoresTests {
  private func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("gstore-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent(name)
  }

  @Test func foldersRoundTripInOrder() {
    let store = GalleryFoldersStore(fileURL: tempFile("gallery-folders.json"))
    let folders = [URL(fileURLWithPath: "/tmp/b", isDirectory: true), URL(fileURLWithPath: "/tmp/a", isDirectory: true)]
    store.save(folders)
    #expect(store.load() == folders)
  }

  @Test func missingOrBrokenFileIsEmpty() throws {
    let missing = tempFile("x.json")
    #expect(GalleryFoldersStore(fileURL: missing).load().isEmpty)
    #expect(FavoritesStore(fileURL: missing).load().isEmpty)
    let broken = tempFile("broken.json")
    try FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{".utf8).write(to: broken)
    #expect(GalleryFoldersStore(fileURL: broken).load().isEmpty)
    #expect(FavoritesStore(fileURL: broken).load().isEmpty)
  }

  @Test func favoritesRoundTrip() {
    let store = FavoritesStore(fileURL: tempFile("favorites.json"))
    let paths: Set<String> = ["/a/1.png", "/a/2.png", "/b/3.png"]
    store.save(paths)
    #expect(store.load() == paths)
  }

  @Test func saveCreatesTheFolder() {
    let url = tempFile("deep.json")
    GalleryFoldersStore(fileURL: url).save([URL(fileURLWithPath: "/x")])
    #expect(FileManager.default.fileExists(atPath: url.path))
  }
}
