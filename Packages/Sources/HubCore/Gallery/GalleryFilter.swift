import Foundation

/// The search box and the star filter of the Explore gallery.
public enum GalleryFilter {
  /// The entries that hold every word of `query` (not caring about case or accents), and, with `onlyFavorites`, are
  /// starred. The order is kept; a blank query filters nothing.
  public static func apply(
    _ entries: [GalleryEntry], query: String, onlyFavorites: Bool, favorites: Set<String>
  ) -> [GalleryEntry] {
    let terms = GalleryEntry.searchKey(query).split(whereSeparator: \.isWhitespace).map(String.init)
    return entries.filter { entry in
      (!onlyFavorites || favorites.contains(entry.path)) && terms.allSatisfy { entry.searchText.contains($0) }
    }
  }
}
