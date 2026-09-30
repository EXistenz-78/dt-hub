import HubKit

/// Why RUN is disabled (spec §7, §10).
public enum RunBlocker: Equatable, Sendable {
  case notConnected
  case noModelSelected
  /// The selected model is not installed on the connected server.
  case modelNotOnServer
}

public enum RunAvailability {
  /// The reason RUN cannot start, or nil when it can. The connection is checked first,
  /// because without it the catalog is empty anyway.
  public static func blocker(
    connection: ConnectionStatus, selectedModel: String?, catalog: ModelCatalog
  ) -> RunBlocker? {
    guard connection == .connected else { return .notConnected }
    guard let selectedModel, !selectedModel.isEmpty else { return .noModelSelected }
    guard catalog.model(forFile: selectedModel) != nil else { return .modelNotOnServer }
    return nil
  }
}
