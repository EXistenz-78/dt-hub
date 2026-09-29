import HubKit

/// Why RUN is disabled (spec §7: grey when Draw Things is not connected or no model is chosen).
public enum RunBlocker: Equatable, Sendable {
  case notConnected
  case noModelSelected
}

public enum RunAvailability {
  /// The reason RUN cannot start, or nil when it can. The connection is checked first,
  /// because without it the model list is empty anyway.
  public static func blocker(connection: ConnectionStatus, selectedModel: String?) -> RunBlocker? {
    guard connection == .connected else { return .notConnected }
    guard let selectedModel, !selectedModel.isEmpty else { return .noModelSelected }
    return nil
  }
}
