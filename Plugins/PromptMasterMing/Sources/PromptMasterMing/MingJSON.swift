import Foundation

/// Un albero JSON con le chiavi in ordine fisso e la serializzazione di `json.dumps(indent=2, ensure_ascii=False)` del nodo
/// ComfyUI (l'uscita `pretty`, quella predefinita): due spazi per livello, `", "` mai, `": "` tra chiave e valore.
enum MingJSON {
  indirect enum Value {
    case string(String)
    case array([Value])
    case object([(key: String, value: Value)])
  }

  static func pretty(_ value: Value, indent: Int = 0) -> String {
    let pad = String(repeating: " ", count: indent), inner = String(repeating: " ", count: indent + 2)
    switch value {
    case .string(let s): return quoted(s)
    case .array(let items):
      guard !items.isEmpty else { return "[]" }
      return "[\n" + items.map { inner + pretty($0, indent: indent + 2) }.joined(separator: ",\n") + "\n" + pad + "]"
    case .object(let pairs):
      guard !pairs.isEmpty else { return "{}" }
      return "{\n" + pairs.map { inner + quoted($0.key) + ": " + pretty($0.value, indent: indent + 2) }.joined(separator: ",\n")
        + "\n" + pad + "}"
    }
  }

  /// Escape come `json.dumps(ensure_ascii=False)`: `"` `\` e i caratteri sotto 0x20 (`\n \r \t \b \f`, gli altri `\u00xx`).
  static func quoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{8}": out += "\\b"
      case "\u{c}": out += "\\f"
      default:
        if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
      }
    }
    return out + "\""
  }
}
