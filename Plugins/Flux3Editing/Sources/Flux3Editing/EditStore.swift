import Foundation
import ImageIO

/// Quello che il tab ricorda tra un avvio e l'altro. Il layout ha un numero: una sessione di un altro layout si ignora.
struct EditSession: Codable, Equatable {
  static let currentSchema = 1

  var schema = EditSession.currentSchema
  var document = EditDocument()
}

/// Dove sta una sessione: una chiave e dei byte. `UserDefaults` nell'app; i test usano un dizionario.
protocol EditStorage {
  func data(forKey key: String) -> Data?
  func set(_ data: Data, forKey key: String)
}

struct DefaultsStorage: EditStorage {
  var defaults: UserDefaults = .standard
  func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
  func set(_ data: Data, forKey key: String) { defaults.set(data, forKey: key) }
}

/// `state.json` nella cartella che l'app dà al plug-in per il progetto aperto (la chiave non conta: un file, una sessione).
struct FileStorage: EditStorage {
  static let fileName = "state.json"
  let folder: URL

  private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

  func data(forKey key: String) -> Data? { try? Data(contentsOf: fileURL) }

  func set(_ data: Data, forKey key: String) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}

struct EditStore {
  static let key = "com.exiztenz.dthub.flux3editing.state.v1"

  var storage: any EditStorage = DefaultsStorage()
  var key: String = EditStore.key

  func save(_ session: EditSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    storage.set(data, forKey: key)
  }

  func load() -> EditSession {
    guard let data = storage.data(forKey: key), let session = try? JSONDecoder().decode(EditSession.self, from: data),
      session.schema == EditSession.currentSchema
    else { return EditSession() }
    return session
  }

  /// Il primo progetto di sempre prende la sessione che il tab aveva prima dei progetti (`legacy`): copiata qui, solo se
  /// qui non ce n'è già una.
  func adoptLegacy(from legacy: any EditStorage) {
    guard storage.data(forKey: key) == nil, let data = legacy.data(forKey: key) else { return }
    storage.set(data, forKey: key)
  }
}

/// La cartella di lavoro dell'LLM: `llm/` accanto a `state.json`. Ogni scrittura sostituisce i tre file.
struct EditWorkFolder {
  let folder: URL

  var directory: URL { folder.appendingPathComponent("llm", isDirectory: true) }

  func write(request: String, answer: String, before: EditSnapshot?) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? request.write(to: directory.appendingPathComponent("request.md"), atomically: true, encoding: .utf8)
    try? answer.write(to: directory.appendingPathComponent("answer.md"), atomically: true, encoding: .utf8)
    if let before {
      try? before.markdown.write(to: directory.appendingPathComponent("before.md"), atomically: true, encoding: .utf8)
    }
  }
}

/// Le dimensioni in pixel di un file immagine, lette senza caricarlo.
enum ImageSizes {
  static func read(path: String) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }
    return CGSize(width: width, height: height)
  }
}
