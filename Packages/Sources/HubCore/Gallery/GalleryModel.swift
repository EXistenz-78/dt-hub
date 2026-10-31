import Foundation
import Observation

/// The state of the Explore gallery: the pictures found, the extra folders, the stars, the search and the selection.
/// The scan runs off the main actor; the file of the last scan shows at once.
@MainActor @Observable
public final class GalleryModel {
  public private(set) var entries: [GalleryEntry]
  public private(set) var isIndexing = false
  public private(set) var extraFolders: [URL]
  public private(set) var favorites: Set<String>
  public var query = ""
  public var onlyFavorites = false
  /// The selection, by file path.
  public var selection = ResultSelection<String>()

  @ObservationIgnored private var outputFolder: URL
  @ObservationIgnored private let foldersStore: GalleryFoldersStore
  @ObservationIgnored private let favoritesStore: FavoritesStore
  @ObservationIgnored private let index: GalleryIndex

  public init(outputFolder: URL, folders: GalleryFoldersStore, favorites: FavoritesStore, index: GalleryIndex) {
    self.outputFolder = outputFolder
    foldersStore = folders
    favoritesStore = favorites
    self.index = index
    entries = index.cached()
    extraFolders = folders.load()
    self.favorites = favorites.load()
  }

  /// The pictures that match the search and the star filter, newest first.
  public var visible: [GalleryEntry] {
    GalleryFilter.apply(entries, query: query, onlyFavorites: onlyFavorites, favorites: favorites)
  }

  public func setOutputFolder(_ url: URL) { outputFolder = url }

  /// Scans again; the pictures found replace `entries` at the end.
  public func refresh() async {
    isIndexing = true
    let (output, extras, index) = (outputFolder, extraFolders, index)
    let found = await Task.detached { index.refresh(outputFolder: output, extraFolders: extras) }.value
    entries = found
    isIndexing = false
    clampSelection()
  }

  public func addFolder(_ url: URL) async {
    guard !extraFolders.contains(url) else { return }
    extraFolders.append(url)
    foldersStore.save(extraFolders)
    await refresh()
  }

  public func removeFolder(_ url: URL) async {
    extraFolders.removeAll { $0 == url }
    foldersStore.save(extraFolders)
    await refresh()
  }

  public func toggleFavorite(_ path: String) {
    if favorites.contains(path) { favorites.remove(path) } else { favorites.insert(path) }
    favoritesStore.save(favorites)
  }

  /// Takes pictures that were moved to the Trash out of the gallery, the stars and the selection.
  public func removeEntries(_ paths: Set<String>) {
    entries.removeAll { paths.contains($0.path) }
    if !favorites.isDisjoint(with: paths) {
      favorites.subtract(paths)
      favoritesStore.save(favorites)
    }
    clampSelection()
  }

  /// Keeps in the selection only what is shown; with nothing shown that is selected, nothing is selected.
  public func clampSelection() {
    let order = visible.map(\.path)
    if selection.ids.contains(where: order.contains) {
      selection.keepOnly(order: order)
    } else {
      selection = ResultSelection<String>()
    }
  }
}
