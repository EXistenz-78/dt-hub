import Foundation

/// Un albero JSON con le chiavi in ordine fisso e la serializzazione compatta di `compile_prompt.py` di OpenMOSS:
/// una sola riga, separatori `,` e `:` senza spazi, niente escape di `/` né dei caratteri non ASCII.
enum MossJSON {
  indirect enum Value {
    case string(String)
    case int(Int)
    case array([Value])
    case object([(key: String, value: Value)])
  }

  static func compact(_ value: Value) -> String {
    switch value {
    case .string(let s): return quoted(s)
    case .int(let n): return String(n)
    case .array(let items): return "[" + items.map(compact).joined(separator: ",") + "]"
    case .object(let pairs): return "{" + pairs.map { quoted($0.key) + ":" + compact($0.value) }.joined(separator: ",") + "}"
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
