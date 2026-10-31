import Foundation
import Testing

@testable import HubCore

struct GalleryFilterTests {
  private func entry(_ name: String, text: String) -> GalleryEntry {
    GalleryEntry(path: "/p/\(name).png", date: .distantPast, project: "P", searchText: GalleryEntry.searchKey(text))
  }

  private var all: [GalleryEntry] {
    [
      entry("a", text: "luna piena flux2"), entry("b", text: "luna kimono qwen"),
      entry("c", text: "Città di notte flux2"),
    ]
  }

  @Test func allTermsMustMatch() {
    let found = GalleryFilter.apply(all, query: "flux luna", onlyFavorites: false, favorites: [])
    #expect(found.map(\.path) == ["/p/a.png"])
  }

  @Test func ignoresCaseAndAccents() {
    let found = GalleryFilter.apply(all, query: "CITTA", onlyFavorites: false, favorites: [])
    #expect(found.map(\.path) == ["/p/c.png"])
  }

  @Test func blankQueryKeepsEverything() {
    #expect(GalleryFilter.apply(all, query: "   ", onlyFavorites: false, favorites: []).count == 3)
  }

  @Test func favoritesOnlyCombinesWithText() {
    let favorites: Set<String> = ["/p/a.png", "/p/b.png"]
    #expect(GalleryFilter.apply(all, query: "", onlyFavorites: true, favorites: favorites).count == 2)
    #expect(GalleryFilter.apply(all, query: "kimono", onlyFavorites: true, favorites: favorites).map(\.path) == ["/p/b.png"])
    #expect(GalleryFilter.apply(all, query: "notte", onlyFavorites: true, favorites: favorites).isEmpty)
  }

  @Test func keepsTheOrder() {
    #expect(GalleryFilter.apply(all, query: "luna", onlyFavorites: false, favorites: []).map(\.path) == ["/p/a.png", "/p/b.png"])
  }
}
