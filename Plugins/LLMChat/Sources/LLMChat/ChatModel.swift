import Foundation

/// One line of a chat: what the user wrote, what the LLM answered, or a note of the plug-in (an action sent, an error,
/// something ignored). Read with tolerance: a missing field takes its default.
struct ChatMessage: Codable, Equatable, Identifiable {
  enum Role: String, Codable { case user, assistant, note }
  enum NoteKind: String, Codable { case action, error, ignored, info }

  var id = UUID()
  var role: Role
  var text: String
  var date = Date()
  /// The names of the pictures that went with a user message (the pictures themselves are not kept).
  var images: [String] = []
  var note: NoteKind?

  init(role: Role, text: String, date: Date = Date(), images: [String] = [], note: NoteKind? = nil) {
    self.role = role
    self.text = text
    self.date = date
    self.images = images
    self.note = note
  }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    role = (try? c.decodeIfPresent(Role.self, forKey: .role)) ?? .note
    text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
    images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
    note = (try? c.decodeIfPresent(NoteKind.self, forKey: .note)) ?? nil
  }

  private enum CodingKeys: String, CodingKey { case id, role, text, date, images, note }
}

struct Chat: Codable, Equatable, Identifiable {
  var id = UUID()
  var title = ""
  var created = Date()
  var updated = Date()
  var messages: [ChatMessage] = []

  init(id: UUID = UUID(), title: String = "", created: Date = Date(), updated: Date = Date(), messages: [ChatMessage] = []) {
    self.id = id
    self.title = title
    self.created = created
    self.updated = updated
    self.messages = messages
  }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
    created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
    updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? created
    messages = (try? c.decodeIfPresent([ChatMessage].self, forKey: .messages)) ?? []
  }

  private enum CodingKeys: String, CodingKey { case id, title, created, updated, messages }
}

/// What the plug-in remembers for a project besides the chats.
struct ChatSettings: Codable, Equatable {
  var currentChat: UUID?
  var model: String?
  var includeImages = true

  init(currentChat: UUID? = nil, model: String? = nil, includeImages: Bool = true) {
    self.currentChat = currentChat
    self.model = model
    self.includeImages = includeImages
  }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    currentChat = (try? c.decodeIfPresent(UUID.self, forKey: .currentChat)) ?? nil
    model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
    includeImages = (try? c.decodeIfPresent(Bool.self, forKey: .includeImages)) ?? true
  }

  private enum CodingKeys: String, CodingKey { case currentChat, model, includeImages }
}

struct ChatSummary: Equatable, Identifiable {
  var id: UUID
  var title: String
  var updated: Date
}
