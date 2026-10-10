import Foundation

/// The chats of a project: `state.json` and `chats/<uuid>.json` in the folder the app gives the plug-in. Written
/// atomically at every change and read with tolerance (a file that cannot be read is skipped). Without a folder (before
/// the app sends the first `project` message) everything is kept in memory.
final class ChatStore {
  static let stateName = "state.json"
  static let chatsName = "chats"

  let folder: URL?
  private var memorySettings = ChatSettings()
  private var memoryChats: [UUID: Chat] = [:]

  init(folder: URL?) { self.folder = folder }

  private var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private var chatsFolder: URL? { folder?.appendingPathComponent(Self.chatsName, isDirectory: true) }

  private func write(_ data: Data, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  func loadSettings() -> ChatSettings {
    guard let folder else { return memorySettings }
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.stateName)),
      let settings = try? decoder.decode(ChatSettings.self, from: data)
    else { return ChatSettings() }
    return settings
  }

  func save(_ settings: ChatSettings) {
    guard let folder else {
      memorySettings = settings
      return
    }
    if let data = try? encoder.encode(settings) { write(data, to: folder.appendingPathComponent(Self.stateName)) }
  }

  func load(_ id: UUID) -> Chat? {
    guard let chatsFolder else { return memoryChats[id] }
    guard let data = try? Data(contentsOf: chatsFolder.appendingPathComponent("\(id.uuidString).json")) else { return nil }
    return try? decoder.decode(Chat.self, from: data)
  }

  func save(_ chat: Chat) {
    guard let chatsFolder else {
      memoryChats[chat.id] = chat
      return
    }
    if let data = try? encoder.encode(chat) { write(data, to: chatsFolder.appendingPathComponent("\(chat.id.uuidString).json")) }
  }

  func delete(_ id: UUID) {
    guard let chatsFolder else {
      memoryChats[id] = nil
      return
    }
    try? FileManager.default.removeItem(at: chatsFolder.appendingPathComponent("\(id.uuidString).json"))
  }

  /// The chats of the project, the most recently updated first. A file that cannot be read is not in the list.
  func list() -> [ChatSummary] {
    var chats: [Chat] = []
    if let chatsFolder {
      let files = (try? FileManager.default.contentsOfDirectory(at: chatsFolder, includingPropertiesForKeys: nil)) ?? []
      for file in files where file.pathExtension == "json" {
        if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), let chat = load(id) { chats.append(chat) }
      }
    } else {
      chats = Array(memoryChats.values)
    }
    return chats.sorted { $0.updated > $1.updated }.map { ChatSummary(id: $0.id, title: $0.title, updated: $0.updated) }
  }
}
