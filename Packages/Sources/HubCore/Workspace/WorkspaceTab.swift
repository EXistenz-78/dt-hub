/// One entry of the tab bar under the header.
public struct WorkspaceTab: Identifiable, Equatable, Sendable {
  /// Identifier of the built-in Generation tab, the only tab the app ships with.
  public static let generationID = "generation"

  public let id: String
  /// Already localized by whoever creates the tab (the app, or a plug-in).
  public let title: String
  /// SF Symbol name.
  public let systemImage: String

  public init(id: String, title: String, systemImage: String) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
  }
}
