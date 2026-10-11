import Foundation

/// A prompt file (a copy of the app's reader: a plug-in is a package of its own): a Markdown text with an optional header (`---`, lines `key: value`, `---`) and a body (spec
/// «Prompt modulari», §4). Reading never throws: a bad header makes the file invalid and the whole text the body.
public struct DTHubPromptFile: Equatable, Sendable {
  public var header: [String: String]
  public var body: String
  /// False when the header is opened and not closed, or has a line without a colon.
  public var isValid: Bool

  public init(header: [String: String] = [:], body: String, isValid: Bool = true) {
    self.header = header
    self.body = body
    self.isValid = isValid
  }

  public var version: Int { Int(header["version"] ?? "") ?? 0 }

  public static func parse(_ text: String) -> DTHubPromptFile {
    var text = text
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    text = text.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = text.components(separatedBy: "\n")
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
      return DTHubPromptFile(body: text)
    }
    guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
      return DTHubPromptFile(body: text, isValid: false)
    }
    var header: [String: String] = [:]
    for line in lines[1..<close] where !line.trimmingCharacters(in: .whitespaces).isEmpty {
      guard let colon = line.firstIndex(of: ":") else { return DTHubPromptFile(body: text, isValid: false) }
      let key = line[..<colon].trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else { return DTHubPromptFile(body: text, isValid: false) }
      header[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return DTHubPromptFile(header: header, body: lines[(close + 1)...].joined(separator: "\n"))
  }

  /// The body with `{name}` replaced for each name in `values`; any other braces stay as they are.
  public func resolved(_ values: [String: String]) -> String {
    values.reduce(body) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
  }

  public func serialized() -> String {
    let lines = header.keys.sorted().map { "\($0): \(header[$0] ?? "")" }
    return "---\n" + lines.map { $0 + "\n" }.joined() + "---\n" + body
  }
}
