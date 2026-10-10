import Foundation

/// What the plug-in remembers for a project: the mode, the increments (as typed, so nothing the user wrote is lost),
/// the number of passes, the fixed-seed box and the prompts.
struct BatchPlusSession: Equatable, Codable {
  enum Mode: String, Codable { case parameters, prompts }

  static let passRange = 2...50
  static let warnFrom = 20

  var mode: Mode = .parameters
  /// By key (`steps`, `guidanceScale`…) or `lora:<file>`.
  var increments: [String: String] = [:]
  var count = 3
  var fixedSeed = true
  var promptText = ""
  /// Prompt mode: each list of terms is used in a random order.
  var shuffle = false
  /// The samplers chosen to vary, in the order chosen: pass *k* uses the *k*-th one; the passes after the last one keep
  /// the tab's sampler. At most one per pass.
  var samplers: [Int] = []

  init() {}

  /// Lenient: a state saved before a field existed still loads.
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .parameters
    increments = (try? c.decodeIfPresent([String: String].self, forKey: .increments)) ?? [:]
    count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 3
    fixedSeed = (try? c.decodeIfPresent(Bool.self, forKey: .fixedSeed)) ?? true
    promptText = (try? c.decodeIfPresent(String.self, forKey: .promptText)) ?? ""
    shuffle = (try? c.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? false
    samplers = (try? c.decodeIfPresent([Int].self, forKey: .samplers)) ?? []
  }

  private enum CodingKeys: String, CodingKey { case mode, increments, count, fixedSeed, promptText, samplers, shuffle }

  /// How many samplers there can be: one per pass.
  var samplerLimit: Int { min(max(count, Self.passRange.lowerBound), Self.passRange.upperBound) }

  /// Never more samplers than passes.
  mutating func trimSamplers() {
    if samplers.count > samplerLimit { samplers = Array(samplers.prefix(samplerLimit)) }
  }

  /// A first run, or a project without a state.
  static func initial() -> BatchPlusSession { BatchPlusSession() }

  /// The increments as the builder wants them. `invalid` holds the ids of the boxes that are not valid. With "auto"
  /// shift Draw Things ignores the shift, so its increment does not count.
  func batch(shiftIsAuto: Bool) -> (batch: ParameterBatch, invalid: Set<String>) {
    var result = ParameterBatch(count: min(max(count, Self.passRange.lowerBound), Self.passRange.upperBound), fixedSeed: fixedSeed)
    var invalid: Set<String> = []
    result.samplers = Array(samplers.prefix(result.count))
    for (id, text) in increments {
      let key = BatchPlusKey(rawValue: id)
      if id.hasPrefix("lora:") || key != nil {
        switch IncrementParse.parse(text, integer: key?.isInteger ?? false) {
        case .failure: invalid.insert(id)
        case .success(let value):
          guard let value else { continue }
          if let key {
            if key == .shift, shiftIsAuto { continue }
            result.increments[key] = value
          } else {
            result.loraIncrements[String(id.dropFirst(5))] = value
          }
        }
      }
    }
    return (result, invalid)
  }
}

/// The session in `state.json` in the folder the app gives the plug-in for the open project; `UserDefaults` before the
/// app sends the first `project` message (and as the state to adopt for the first project ever).
struct BatchPlusStore {
  static let key = "com.exiztenz.dthub.batchplus.state.v1"
  static let fileName = "state.json"

  var defaults: UserDefaults = .standard
  var key: String = BatchPlusStore.key
  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  private func write(_ data: Data) {
    if let fileURL {
      try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: fileURL, options: .atomic)
    } else {
      defaults.set(data, forKey: key)
    }
  }

  private func read() -> Data? {
    if let fileURL { return try? Data(contentsOf: fileURL) }
    return defaults.data(forKey: key)
  }

  /// The first project ever takes the state the tab had before projects: written to the file, only if there is none.
  func adoptLegacy() {
    guard let fileURL, !FileManager.default.fileExists(atPath: fileURL.path), let data = defaults.data(forKey: key) else {
      return
    }
    write(data)
  }

  func save(_ session: BatchPlusSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    write(data)
  }

  /// Nil when there is none or it cannot be read; the number of passes is brought into its range.
  func load() -> BatchPlusSession? {
    guard let data = read(), var session = try? JSONDecoder().decode(BatchPlusSession.self, from: data) else { return nil }
    session.count = min(max(session.count, BatchPlusSession.passRange.lowerBound), BatchPlusSession.passRange.upperBound)
    return session
  }
}
