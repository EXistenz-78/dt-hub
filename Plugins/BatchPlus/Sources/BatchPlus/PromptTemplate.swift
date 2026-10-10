import Foundation

/// The prompt of Prompt mode: text with lists of terms in it, and one prompt for each term.
///
/// A **term** sits between an opening delimiter (`<` or `|`) and a closing one (`>` or `|`): `<a>`, `<a|`, `|a>`, `|a|`.
/// `<cane|gatto|scoiattolo>` is a list of three terms (the `|` between two terms closes one and opens the next); a `>`
/// outside a list and a `<` inside a term are plain text (no `><`). Lists written one after the other with only blank
/// space between them are one list: `<a>` newline `<b>` newline `<c>` is a list of three terms. The text outside the
/// lists is the same in every prompt. Pass *k* takes the *k*-th term of each list (not every combination). The number of
/// passes is the length of the longest list; a shorter list keeps its last term for the extra passes, or, with shuffle,
/// goes on with a new random order.
enum PromptTemplate {
  enum Piece: Equatable {
    case text(String)
    case list([String])
  }

  // MARK: Reading

  /// The text split into plain text and lists.
  static func pieces(_ text: String) -> [Piece] {
    let chars = Array(text)
    var pieces: [Piece] = []
    var plain = ""
    var index = 0

    func flush() {
      if !plain.isEmpty { pieces.append(.text(plain)) }
      plain = ""
    }

    /// A list starting at `start` (a `<`): its terms and the index after its closing `>`; nil when it is not closed.
    func list(at start: Int) -> (terms: [String], end: Int)? {
      guard chars[start] == "<" else { return nil }
      var terms: [String] = []
      var term = ""
      var i = start + 1
      while i < chars.count {
        let c = chars[i]
        if c == "|" {
          terms.append(term.trimmingCharacters(in: .whitespacesAndNewlines))
          term = ""
        } else if c == ">" {
          terms.append(term.trimmingCharacters(in: .whitespacesAndNewlines))
          return (terms, i + 1)
        } else {
          term.append(c)
        }
        i += 1
      }
      return nil
    }

    while index < chars.count {
      if let first = list(at: index) {
        var terms = first.terms
        var end = first.end
        // Another list after only blank space joins this one.
        while true {
          var next = end
          while next < chars.count, chars[next].isWhitespace { next += 1 }
          guard next < chars.count, let more = list(at: next) else { break }
          terms += more.terms
          end = more.end
        }
        flush()
        pieces.append(.list(terms))
        index = end
      } else {
        plain.append(chars[index])
        index += 1
      }
    }
    flush()
    return pieces
  }

  /// The lists in the text, in order.
  static func lists(_ text: String) -> [[String]] {
    pieces(text).compactMap { if case .list(let terms) = $0 { terms } else { nil } }
  }

  /// How many passes the text makes: the longest list; 1 without lists.
  static func passCount(_ text: String) -> Int {
    max(1, lists(text).map(\.count).max() ?? 1)
  }

  // MARK: Writing

  /// One prompt per pass. `seed` makes the shuffle repeatable (the preview shows what will be sent).
  static func prompts(from text: String, shuffle: Bool, seed: UInt64) -> [String] {
    let pieces = pieces(text)
    let passes = passCount(text)
    // The term of each list at each pass.
    var sequences: [[String]] = []
    var number = 0
    for case .list(let terms) in pieces {
      sequences.append(sequence(terms, length: passes, shuffle: shuffle, seed: seed &+ UInt64(number) &* 0x9E37_79B9))
      number += 1
    }
    return (0..<passes).map { pass in
      var result = ""
      var which = 0
      for piece in pieces {
        switch piece {
        case .text(let plain): result += plain
        case .list: result += sequences[which][pass]; which += 1
        }
      }
      return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func sequence(_ terms: [String], length: Int, shuffle: Bool, seed: UInt64) -> [String] {
    guard !terms.isEmpty else { return Array(repeating: "", count: length) }
    if !shuffle {
      return (0..<length).map { terms[min($0, terms.count - 1)] }
    }
    var generator = SeededGenerator(seed: seed)
    var result: [String] = []
    while result.count < length { result += terms.shuffled(using: &generator) }
    return Array(result.prefix(length))
  }
}

/// A small repeatable generator (SplitMix64), for the shuffle.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
