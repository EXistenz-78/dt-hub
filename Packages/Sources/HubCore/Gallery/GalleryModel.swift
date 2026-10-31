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
  /// How the folders are scanned (the index's `refresh`; a test puts its own).
  @ObservationIgnored private let scan: @Sendable (URL, [URL]) -> [GalleryEntry]
  /// Which scan is the latest one: an older scan that ends later is dropped.
  @ObservationIgnored private var latestScan = UUID()
  /// The pictures taken out while a scan was running: that scan may still have seen them.
  @ObservationIgnored private var removedDuringScan: Set<String> = []

  public init(
    outputFolder: URL, folders: GalleryFoldersStore, favorites: FavoritesStore, index: GalleryIndex,
    scan: (@Sendable (URL, [URL]) -> [GalleryEntry])? = nil
  ) {
    self.scan = scan ?? { index.refresh(outputFolder: $0, extraFolders: $1) }
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
    let mine = UUID()
    latestScan = mine
    removedDuringScan = []
    isIndexing = true
    let (output, extras, scan) = (outputFolder, extraFolders, scan)
    let found = await Task.detached { scan(output, extras) }.value
    // A newer scan has started since: its result is the one that counts.
    guard latestScan == mine else { return }
    entries = found.filter { !removedDuringScan.contains($0.path) }
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
    // With the star filter on, a picture that loses its star leaves the grid, and the selection with it.
    if onlyFavorites { clampSelection() }
  }

  /// Takes pictures that were moved to the Trash out of the gallery, the stars and the selection.
  public func removeEntries(_ paths: Set<String>) {
    entries.removeAll { paths.contains($0.path) }
    removedDuringScan.formUnion(paths)
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
