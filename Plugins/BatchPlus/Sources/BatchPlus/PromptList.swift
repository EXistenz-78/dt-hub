import Foundation

/// The prompts of Prompt mode: a bulleted list.
enum PromptList {
  /// A line starting (after spaces) with `-`, `•` or `*` opens an item; the following non-empty lines without a
  /// bullet are joined to it with a space. Empty items are dropped, and text before the first bullet is ignored.
  static func items(_ text: String) -> [String] {
    var items: [String] = []
    var current: String?
    func close() {
      if let value = current?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { items.append(value) }
      current = nil
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if let first = line.first, "-•*".contains(first) {
        close()
        current = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
      } else if !line.isEmpty, current != nil {
        current = (current ?? "") + (current?.isEmpty == true ? "" : " ") + line
      }
    }
    close()
    return items
  }
}
