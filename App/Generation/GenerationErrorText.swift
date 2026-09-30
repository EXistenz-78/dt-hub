import HubKit

/// Words for a failed generation (spec §10).
enum GenerationErrorText {
  static func headline(_ error: BackendError) -> String {
    switch error {
    case .noImages: String(localized: "generation.error.noImages")
    case .unauthorized: String(localized: "status.unauthorized")
    case .unreachable: String(localized: "status.disconnected")
    case .generationFailed: String(localized: "generation.error.failed")
    }
  }

  /// The technical detail, when there is one.
  static func detail(_ error: BackendError) -> String? {
    switch error {
    case .unreachable(let detail), .generationFailed(let detail): detail
    case .noImages, .unauthorized: nil
    }
  }
}
