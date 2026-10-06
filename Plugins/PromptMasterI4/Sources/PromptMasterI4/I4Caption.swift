import Foundation

/// A JSON value with its keys in the order they were given: the caption is trained with a fixed order, and
/// `JSONEncoder` does not keep one.
indirect enum OrderedJSON: Equatable {
  case string(String)
  case int(Int)
  case array([OrderedJSON])
  case object([(key: String, value: OrderedJSON)])

  static func == (left: OrderedJSON, right: OrderedJSON) -> Bool { left.rendered() == right.rendered() }

  /// The text of the value, as `JSON.stringify(value, null, indent)` writes it: one item to a line, `[]` and `{}`
  /// when empty, no escaping of `/` or of characters beyond ASCII.
  func rendered(indent: Int = 2, level: Int = 0) -> String {
    let inner = String(repeating: " ", count: indent * (level + 1))
    let outer = String(repeating: " ", count: indent * level)
    switch self {
    case .string(let text):
      return Self.quoted(text)
    case .int(let number):
      return String(number)
    case .array(let items):
      if items.isEmpty { return "[]" }
      return "[\n" + items.map { inner + $0.rendered(indent: indent, level: level + 1) }.joined(separator: ",\n") + "\n" + outer + "]"
    case .object(let members):
      if members.isEmpty { return "{}" }
      return "{\n"
        + members.map { inner + Self.quoted($0.key) + ": " + $0.value.rendered(indent: indent, level: level + 1) }
        .joined(separator: ",\n") + "\n" + outer + "}"
    }
  }

  static func quoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }
}

/// The values of the caption, each as it will be written (spec §4). The document makes one from the raw texts.
struct I4Caption: Equatable {
  struct Element: Equatable {
    var type: ElementType
    var bbox: BBox?
    var text: String
    var desc: String
    var colors: [String]
  }

  var description: String
  var aesthetics: String
  var lighting: String
  /// `photo` in Photo mode, `art_style` in Art mode.
  var style: String
  var medium: String
  var mode: StyleMode
  var colors: [String]
  var background: String
  var elements: [Element]

  /// The tree, with the keys in the order of the spec §4: `photo` goes BEFORE `medium`, `art_style` AFTER it.
  var tree: OrderedJSON {
    var styleMembers: [(key: String, value: OrderedJSON)] = [
      ("aesthetics", .string(aesthetics)), ("lighting", .string(lighting)),
    ]
    if mode == .photo { styleMembers.append(("photo", .string(style))) }
    styleMembers.append(("medium", .string(medium)))
    if mode == .art { styleMembers.append(("art_style", .string(style))) }
    styleMembers.append(("color_palette", .array(colors.map { .string($0) })))
    let items: [OrderedJSON] = elements.map { element in
      var members: [(key: String, value: OrderedJSON)] = [("type", .string(element.type.rawValue))]
      if let box = element.bbox { members.append(("bbox", .array(box.array.map { .int($0) }))) }
      if element.type == .text { members.append(("text", .string(element.text))) }
      members.append(("desc", .string(element.desc)))
      if !element.colors.isEmpty { members.append(("color_palette", .array(element.colors.map { .string($0) }))) }
      return .object(members)
    }
    return .object([
      ("high_level_description", .string(description)),
      ("style_description", .object(styleMembers)),
      ("compositional_deconstruction", .object([("background", .string(background)), ("elements", .array(items))])),
    ])
  }

  /// The JSON text that goes in the Prompt field.
  var json: String { tree.rendered(indent: 2) }
}
