import DTHubPluginKit
import Foundation

/// Un testo riscritto: l'originale serve a non sovrascrivere ciò che l'utente ha cambiato nel frattempo.
struct F3Rewrite: Equatable, Sendable {
  var kind: F3Part.Kind
  var original: String
  var text: String
}

struct F3WriteResult: Sendable {
  var rewrites: [F3Rewrite]
  var status: String
  var request: String
  var answer: String
}

/// Il controllo nel codice dell'ordine tassativo (spec §9): gli `<id>` e le parole tra virgolette non si toccano.
enum F3IDCheck {
  static func preserves(original: String, rewritten: String) -> Bool {
    sortedIDs(original) == sortedIDs(rewritten) && quoted(original).allSatisfy { rewritten.contains($0) }
  }

  static func idsPreserved(original: String, rewritten: String) -> Bool { sortedIDs(original) == sortedIDs(rewritten) }

  private static func sortedIDs(_ text: String) -> [String] { F3IDParser.ids(in: text).map(\.id).sorted() }

  /// Le parole tra virgolette dritte o ricurve.
  static func quoted(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|“([^”]+)”") else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      for group in 1...2 {
        if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
      }
      return nil
    }
  }
}

/// «Scrivi con LLM» (spec §9): una richiesta con tutte le parti, il ripiego per le mancanti, il controllo degli id.
@MainActor
struct F3Writer {
  var ask: (String, String, DTHubLLMOptions) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  static let idReminder = "IMPORTANT: copy every <placeholder> exactly as written, the same number of times, and every quoted phrase unchanged."

  func write(document: F3Document, catalog: F3Catalog, system: String, options: DTHubLLMOptions) async -> F3WriteResult {
    let parts = F3Brief.parts(from: document, catalog: catalog)
    guard !parts.isEmpty else { return F3WriteResult(rewrites: [], status: L.text(.nothingToWrite, italian: italian), request: "", answer: "") }
    let request = F3Brief.message(parts)
    var failureText: String?
    let first = await ask(request, system, options)
    var answer = ""
    var parsed: [F3Part.Kind: String] = [:]
    switch first {
    case .text(let text):
      answer = text
      parsed = F3AnswerParser.parse(text, requested: parts.map(\.kind))
    case .failure(let reason):
      failureText = reason
    }
    var rewrites: [F3Rewrite] = []
    var problems: [String] = []
    for part in parts {
      var candidate = parsed[part.kind]
      if candidate == nil || !acceptable(candidate!, for: part) {
        // Ripiego: la sola parte, con l'ordine ripetuto.
        let single = await ask(F3Brief.message([part], reminder: Self.idReminder), system, options)
        if case .text(let text) = single {
          answer += "\n\n" + text
          candidate = F3AnswerParser.parse(text, requested: [part.kind])[part.kind]
        } else {
          candidate = nil
        }
      }
      if let candidate, acceptable(candidate, for: part) {
        rewrites.append(F3Rewrite(kind: part.kind, original: part.text, text: candidate))
      } else if let candidate, part.kind == .composition, !F3IDCheck.idsPreserved(original: part.text, rewritten: candidate) {
        problems.append(L.text(.idsChanged, italian: italian))
      } else {
        problems.append(part.kind.title)
      }
    }
    var lines: [String] = []
    if let failureText, rewrites.isEmpty { lines.append(failureText) }
    if !rewrites.isEmpty { lines.append(L.format(.writtenCount, rewrites.count, italian: italian)) }
    if !problems.isEmpty && !(failureText != nil && rewrites.isEmpty) {
      lines.append(L.format(.failedParts, problems.joined(separator: ", "), italian: italian))
    }
    return F3WriteResult(rewrites: rewrites, status: lines.joined(separator: " "), request: request, answer: answer)
  }

  /// Le parti con `<id>` (composizione) e ogni parte con virgolette devono restare intatte.
  private func acceptable(_ text: String, for part: F3Part) -> Bool {
    switch part.kind {
    case .composition: return F3IDCheck.preserves(original: part.text, rewritten: text)
    default: return F3IDCheck.quoted(part.text).allSatisfy { text.contains($0) } && !containsPlaceholder(text, part: part)
    }
  }

  /// Un elemento o la descrizione non deve ricevere `<id>` che non aveva.
  private func containsPlaceholder(_ text: String, part: F3Part) -> Bool {
    Set(F3IDParser.ids(in: text).map(\.id)) != Set(F3IDParser.ids(in: part.text).map(\.id))
  }
}
