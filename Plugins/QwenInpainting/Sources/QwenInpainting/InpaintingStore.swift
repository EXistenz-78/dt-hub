import Foundation

/// What the plug-in remembers for a project. Read with tolerance: a field that is missing takes its default and a mark
/// that cannot be read is skipped.
struct InpaintingSession: Codable, Equatable {
  /// The start image the marks were drawn on (the path the app gave).
  var startImage: String?
  var marks: [Mark] = []
  /// The text of each card, by `CardKey.rawValue`, kept even when the card is hidden.
  var texts: [String: String] = [:]
  var tool: MarkTool = .box
  var color: MarkColor = .red
  var width = Mark.defaultWidth
  var usePE = true

  init() {}

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    startImage = (try? c.decodeIfPresent(String.self, forKey: .startImage)) ?? nil
    texts = (try? c.decodeIfPresent([String: String].self, forKey: .texts)) ?? [:]
    tool = (try? c.decodeIfPresent(MarkTool.self, forKey: .tool)) ?? .box
    color = (try? c.decodeIfPresent(MarkColor.self, forKey: .color)) ?? .red
    width = (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? Mark.defaultWidth
    usePE = (try? c.decodeIfPresent(Bool.self, forKey: .usePE)) ?? true
    var list = (try? c.nestedUnkeyedContainer(forKey: .marks))
    var read: [Mark] = []
    while let l = list, !l.isAtEnd {
      var item = l
      if let mark = try? item.decode(Mark.self) {
        read.append(mark.clamped())
      } else {
        _ = try? item.decode(Skipped.self)  // a mark that cannot be read is skipped
      }
      list = item
    }
    marks = read
  }

  private struct Skipped: Decodable {}
  private enum CodingKeys: String, CodingKey { case startImage, marks, texts, tool, color, width, usePE }
}

/// `state.json` in the folder the app gives the plug-in for the open project; in memory before the first `project` message.
final class InpaintingStore {
  static let fileName = "state.json"
  let folder: URL?
  private var memory: InpaintingSession?

  init(folder: URL?) { self.folder = folder }

  func save(_ session: InpaintingSession) {
    guard let folder else {
      memory = session
      return
    }
    guard let data = try? JSONEncoder().encode(session) else { return }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? data.write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }

  func load() -> InpaintingSession? {
    guard let folder else { return memory }
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.fileName)) else { return nil }
    return try? JSONDecoder().decode(InpaintingSession.self, from: data)
  }
}
