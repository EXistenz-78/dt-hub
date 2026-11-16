import Foundation
import HubKit

/// The retouches of a local edit: the results the confirm can choose from.
public enum LocalEditAttempts {
  /// The pictures made since the session opened at exactly the crop's size, newest first. Videos are left out, and so is
  /// a picture whose size `pixelSize` cannot read (it reads the file: `image` is a reduced copy).
  public static func select(
    _ results: [GeneratedImage], session: LocalEditSession,
    pixelSize: (GeneratedImage) -> (width: Int, height: Int)?
  ) -> [GeneratedImage] {
    results
      .filter { result in
        guard !result.job.isVideo, result.date >= session.openedAt, let size = pixelSize(result) else { return false }
        return size.width == session.rect.width && size.height == session.rect.height
      }
      .sorted { $0.date > $1.date }
  }
}
