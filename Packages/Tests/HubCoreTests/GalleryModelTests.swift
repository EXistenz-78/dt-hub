import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct GalleryModelTests {
  private struct Env {
    let root: URL
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }
    var folders: GalleryFoldersStore { GalleryFoldersStore(fileURL: root.appendingPathComponent("folders.json")) }
    var favorites: FavoritesStore { FavoritesStore(fileURL: root.appendingPathComponent("fav.json")) }
    var index: GalleryIndex { GalleryIndex(cacheURL: root.appendingPathComponent("index.json")) }
    @MainActor func model() -> GalleryModel {
      GalleryModel(outputFolder: output, folders: folders, favorites: favorites, index: index)
    }
  }

  private func makeEnv() -> Env {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gmodel-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return Env(root: root)
  }

  @discardableResult
  private func save(_ prompt: String, in folder: URL, seed: UInt32 = 1) throws -> URL {
    let job = GenerationJob(prompt: prompt, model: "m.ckpt", parameters: GenerationParameters(seed: seed, randomSeed: false))
    return try PNGImageStore(folder: folder).save(testImage(), job: job, index: 0, date: Date(timeIntervalSince1970: 1_790_000_000 + Double(seed)))
  }

  private func extra(_ env: Env, _ name: String, prompts: [String]) throws -> URL {
    let folder = env.root.appendingPathComponent(name, isDirectory: true)
    for (i, prompt) in prompts.enumerated() { try save(prompt, in: folder, seed: UInt32(i + 1)) }
    return folder
  }

  @Test func theNewModelShowsTheCacheAtOnce() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let folder = try extra(env, "x", prompts: ["uno"])
    let first = env.model()
    await first.addFolder(folder)
    #expect(first.entries.count == 1)
    #expect(env.model().entries.count == 1, "read from the cache file, before any scan")
  }

  @Test func addingAFolderPersistsAndRemovingDropsItsImages() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let folder = try extra(env, "x", prompts: ["uno", "due"])
    let model = env.model()
    await model.addFolder(folder)
    #expect(model.extraFolders == [folder] && model.entries.count == 2)
    #expect(env.model().extraFolders == [folder])
    await model.removeFolder(folder)
    #expect(model.extraFolders.isEmpty && model.entries.isEmpty)
    #expect(env.model().extraFolders.isEmpty)
  }

  @Test func toggleFavoritePersists() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let model = env.model()
    model.toggleFavorite("/a.png")
    #expect(model.favorites == ["/a.png"] && env.model().favorites == ["/a.png"])
    model.toggleFavorite("/a.png")
    #expect(model.favorites.isEmpty && env.model().favorites.isEmpty)
  }

  @Test func visibleFollowsQueryAndFavorites() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let folder = try extra(env, "x", prompts: ["luna piena", "luna rossa", "sole"])
    let model = env.model()
    await model.addFolder(folder)
    model.query = "luna"
    #expect(model.visible.count == 2)
    model.toggleFavorite(try #require(model.visible.first).path)
    model.onlyFavorites = true
    #expect(model.visible.count == 1)
  }

  @Test func removeEntriesDropsFavoritesAndSelection() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let folder = try extra(env, "x", prompts: ["uno", "due"])
    let model = env.model()
    await model.addFolder(folder)
    let gone = try #require(model.entries.first).path
    model.toggleFavorite(gone)
    model.selection = ResultSelection(only: gone)
    model.removeEntries([gone])
    #expect(model.entries.count == 1 && !model.favorites.contains(gone))
    #expect(model.selection.ids.isEmpty)
    #expect(env.model().favorites.isEmpty)
  }

  @Test func clampSelectionKeepsOnlyVisible() async throws {
    let env = makeEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let folder = try extra(env, "x", prompts: ["luna", "sole"])
    let model = env.model()
    await model.addFolder(folder)
    let paths = model.entries.map(\.path)
    model.selection = ResultSelection(only: paths[0])
    model.selection.click(paths[1], command: true, shift: false, order: paths)
    model.query = "luna"
    model.clampSelection()
    #expect(model.selection.ids.count == 1)
    model.query = "inesistente"
    model.clampSelection()
    #expect(model.selection.ids.isEmpty, "nothing visible: nothing selected")
  }
}
