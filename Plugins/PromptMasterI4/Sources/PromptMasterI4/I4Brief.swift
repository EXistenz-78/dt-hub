import Foundation

/// The request to the language model (spec §7.1): one block for each field to write, wrapped in its tag, the sentences
/// already written as plain context, and the shape of the reply. Positions, colors and the words a lettering prints are
/// never in it.
enum I4Brief {
  /// `targets` are the fields to write; `written` the fields that are final and only give context (tag and sentence).
  static func make(targets: [I4FieldInfo], written: [(tag: String, text: String)] = []) -> String {
    var parts: [String] = targets.map { field in
      let open = field.kind.map { "<\(field.tag) kind=\"\($0)\">" } ?? "<\(field.tag)>"
      return "\(open)\n\(field.block)\n</\(field.tag)>"
    }
    if !written.isEmpty {
      parts.append("<already_written>\n" + written.map { "\($0.tag): \($0.text)" }.joined(separator: "\n") + "\n</already_written>")
    }
    // A small model that is only told to answer with tags answers for some of them, or invents others; shown the shape,
    // it fills every one (tried on the real model, 6 October).
    parts.append(
      "Reply in exactly this shape, replacing the dots with the sentence:\n"
        + targets.map { "<\($0.tag)>...</\($0.tag)>" }.joined(separator: "\n"))
    return parts.joined(separator: "\n")
  }

  /// The fields that are final (an up-to-date sentence) and are not in `targets`, as context for the request.
  static func context(of fields: [I4FieldInfo], excluding targets: [I4FieldInfo]) -> [(tag: String, text: String)] {
    let asked = Set(targets.map(\.id))
    return fields.filter { $0.state == .written && !asked.contains($0.id) }.compactMap { field in
      field.phrase.map { (field.tag, $0.text) }
    }
  }
}
