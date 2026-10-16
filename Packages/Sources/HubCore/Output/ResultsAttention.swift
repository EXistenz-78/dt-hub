import Foundation

/// What the Results button of the header says (design of 16 Oct 2026): `working` while a RUN is under way, `unseen`
/// when it is over and the Results window, which was not on screen, has images the user has not seen, `idle` otherwise.
public enum ResultsAttentionState: Equatable, Sendable {
  case idle
  case working
  case unseen
}

/// The newest image the user has seen: one seen while the Results window was on screen. An image that arrives with
/// the window visible is seen at once, so the button does not light for it. Session state, never saved.
public struct ResultsAttention: Equatable, Sendable {
  public private(set) var lastSeen: UUID?

  /// `lastSeen` is the newest result there is when the app starts (the results come back from the last launch):
  /// nothing is to be seen then.
  public init(lastSeen: UUID? = nil) {
    self.lastSeen = lastSeen
  }

  /// With the window on screen, the newest image counts as seen.
  public mutating func update(newestResultID: UUID?, windowVisible: Bool) {
    if windowVisible { lastSeen = newestResultID }
  }

  public func state(isBusy: Bool, newestResultID: UUID?, windowVisible: Bool) -> ResultsAttentionState {
    if isBusy { return .working }
    guard let newestResultID, newestResultID != lastSeen, !windowVisible else { return .idle }
    return .unseen
  }
}
