import Foundation

/// One earlier turn of a conversation with the language model (a plug-in's chat): what was said and by whom.
public struct LanguageModelTurn: Equatable, Sendable {
  public enum Role: String, Sendable { case user, assistant }

  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    self.role = role
    self.text = text
  }
}
