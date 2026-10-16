import Foundation

/// What the Results button of the header says (design of 16 Oct 2026): `working` while a RUN is under way, `unseen`
/// when it is over and the Results window, which was not on screen, has images the user has not seen, `idle` otherwise.
public enum ResultsAttentionState: Equatable, Sendable {
  case idle
  case working
  case unseen
}

/// The date of the newest image the user has seen: one seen while the Results window was on screen. An image that
/// arrives with the window visible is seen at once, so the button does not light for it. A newer image is one made
/// after that date, so deleting the newest image does not make an older one look new. Session state, never saved.
public struct ResultsAttention: Equatable, Sendable {
  public private(set) var lastSeen: Date?

  public init(lastSeen: Date? = nil) {
    self.lastSeen = lastSeen
  }

  /// The date of the newest image this session made: the images read back from disk (at launch, at a project
  /// switch) are not new, and they arrive after the button exists. nil when there is none.
  public static func newestDate(in results: [GeneratedImage]) -> Date? {
    results.first { !$0.isRestored }?.date
  }

  /// With the window on screen, the newest image counts as seen.
  public mutating func update(newestDate: Date?, windowVisible: Bool) {
    if windowVisible, let newestDate { lastSeen = max(lastSeen ?? newestDate, newestDate) }
  }

  public func state(isBusy: Bool, newestDate: Date?, windowVisible: Bool) -> ResultsAttentionState {
    if isBusy { return .working }
    guard let newestDate, !windowVisible else { return .idle }
    if let lastSeen, newestDate <= lastSeen { return .idle }
    return .unseen
  }
}
