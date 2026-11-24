import Foundation

/// Larghezza e altezza della Generazione, in pixel.
struct PixelSize: Codable, Equatable, Sendable {
  var width: Int
  var height: Int

  /// Positive: Ming legge solo frazioni e il rapporto, ma serve una forma.
  var isUsable: Bool { width > 0 && height > 0 }
}

/// Un riquadro in frazioni della tela (0–1, origine in alto a sinistra): non dipende dalla risoluzione.
struct FracBox: Codable, Equatable, Sendable {
  var x0: Double
  var y0: Double
  var x1: Double
  var y1: Double

  /// Il lato minimo di un box disegnato: il 2 % del lato corto della tela, espresso in frazioni per ciascun asse.
  static let minSide = 0.02

  static func minimum(for size: PixelSize) -> (x: Double, y: Double) {
    let short = Double(min(size.width, size.height))
    return (minSide * short / Double(max(size.width, 1)), minSide * short / Double(max(size.height, 1)))
  }

  /// Estremi in ordine, dentro 0–1; nil se un lato è più corto del minimo.
  static func normalized(x0: Double, y0: Double, x1: Double, y1: Double, size: PixelSize) -> FracBox? {
    func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    let box = FracBox(x0: clamp(min(x0, x1)), y0: clamp(min(y0, y1)), x1: clamp(max(x0, x1)), y1: clamp(max(y0, y1)))
    let least = minimum(for: size)
    guard box.x1 - box.x0 >= least.x - 1e-9, box.y1 - box.y0 >= least.y - 1e-9 else { return nil }
    return box
  }

  var width: Double { x1 - x0 }
  var height: Double { y1 - y0 }
  var centerX: Double { (x0 + x1) / 2 }
  var centerY: Double { (y0 + y1) / 2 }
}

/// Le coordinate di Ming: `"cx: 0.500, cy: 0.500, w: 1.000, h: 1.000"`, il centro e i lati in frazioni della tela, tre
/// decimali (come `serialize_coordinates` del nodo ComfyUI).
enum MingGeometry {
  static func coordinates(_ box: FracBox) -> String {
    String(format: "cx: %.3f, cy: %.3f, w: %.3f, h: %.3f", box.centerX, box.centerY, box.width, box.height)
  }

  /// Legge `cx, cy, w, h` (con o senza i nomi, separati da virgole o spazi); nil se non sono quattro numeri finiti con il
  /// centro in 0–1 e i lati in (0–1]. Il riquadro che ne esce si taglia ai bordi della tela; un lato sotto 0,001 sale a 0,001.
  static func parse(_ text: String) -> FracBox? {
    let pattern = #"^\s*(?:cx\s*[:=]\s*)?([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*[,;\s]\s*(?:cy\s*[:=]\s*)?([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*[,;\s]\s*(?:w\s*[:=]\s*)?([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*[,;\s]\s*(?:h\s*[:=]\s*)?([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    let numbers = (1...4).compactMap { Range(match.range(at: $0), in: text).flatMap { Double(text[$0]) } }
    guard numbers.count == 4, numbers.allSatisfy(\.isFinite) else { return nil }
    let (cx, cy, w, h) = (numbers[0], numbers[1], numbers[2], numbers[3])
    guard (0...1).contains(cx), (0...1).contains(cy), w > 0, w <= 1, h > 0, h <= 1 else { return nil }
    return clipped(x0: cx - w / 2, y0: cy - h / 2, x1: cx + w / 2, y1: cy + h / 2)
  }

  /// Il riquadro dentro la tela; nil se ne resta fuori del tutto.
  static func clipped(x0: Double, y0: Double, x1: Double, y1: Double) -> FracBox? {
    var left = max(0, x0), top = max(0, y0), right = min(1, x1), bottom = min(1, y1)
    guard right > left, bottom > top else { return nil }
    if right - left < 0.001 { right = min(1, left + 0.001); left = right - 0.001 }
    if bottom - top < 0.001 { bottom = min(1, top + 0.001); top = bottom - 0.001 }
    return FracBox(x0: left, y0: top, x1: right, y1: bottom)
  }

  /// La forma della tela come la scrive il nodo ComfyUI: il rapporto ridotto con il MCD, `"832:1248"` → `"2:3"`.
  static func aspectRatio(_ size: PixelSize) -> String {
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    let divisor = max(1, gcd(size.width, size.height))
    return "\(size.width / divisor):\(size.height / divisor)"
  }

  /// Quello che un `aspect_ratio` dice della tela: un rapporto (`"16:9"`, `"16/9"`) o una misura in pixel
  /// (`"portrait, 832 x 1248 px"`, `"1024×1024"`), che vale anche come rapporto.
  enum Shape: Equatable, Sendable {
    case ratio(Int, Int)
    case pixels(PixelSize)

    var ratio: Double {
      switch self {
      case .ratio(let a, let b): return Double(a) / Double(b)
      case .pixels(let size): return Double(size.width) / Double(size.height)
      }
    }
  }

  static func shape(of text: String) -> Shape? {
    func numbers(_ pattern: String) -> (Int, Int)? {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let a = Range(match.range(at: 1), in: text).flatMap({ Int(text[$0]) }),
        let b = Range(match.range(at: 2), in: text).flatMap({ Int(text[$0]) }), a > 0, b > 0, a <= 16384, b <= 16384
      else { return nil }
      return (a, b)
    }
    if let (w, h) = numbers(#"(\d+)\s*[x×*]\s*(\d+)"#) { return .pixels(PixelSize(width: w, height: h)) }
    if let (a, b) = numbers(#"(\d+)\s*[:/]\s*(\d+)"#) { return .ratio(a, b) }
    let lower = text.lowercased()
    if lower.contains("square") { return .ratio(1, 1) }
    if lower.contains("portrait") { return .ratio(2, 3) }
    if lower.contains("landscape") { return .ratio(3, 2) }
    return nil
  }

  /// La dimensione della Generazione per una forma: i pixel scritti, se ci sono; per un rapporto, lo stesso lato lungo di
  /// `current` (1024 se non c'è), con i lati in multipli di 32 (quello che Ming vuole).
  static func size(for shape: Shape, keepingLongSideOf current: PixelSize?) -> PixelSize {
    func step(_ value: Double) -> Int { max(32, Int((value / 32).rounded()) * 32) }
    switch shape {
    case .pixels(let size): return PixelSize(width: step(Double(size.width)), height: step(Double(size.height)))
    case .ratio(let a, let b):
      let long = Double(max(current?.width ?? 1024, current?.height ?? 1024, 256))
      if a >= b { return PixelSize(width: step(long), height: step(long * Double(b) / Double(a))) }
      return PixelSize(width: step(long * Double(a) / Double(b)), height: step(long))
    }
  }
}
