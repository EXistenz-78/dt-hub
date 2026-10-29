import Foundation

extension GeneratedImage {
  /// The file dragged out of the strip and revealed in the Finder: the MP4 for a video, else the saved picture.
  public var exportURL: URL? { videoURL ?? fileURL }

  /// The whole seconds the strip badge shows ("5 s"); nil for a picture, and for a clip without a length.
  public var videoBadgeSeconds: Int? {
    guard videoURL != nil, let seconds = videoSeconds, seconds > 0 else { return nil }
    return max(1, Int(seconds.rounded()))
  }
}
