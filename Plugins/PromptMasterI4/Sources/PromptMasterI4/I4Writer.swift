import DTHubPluginKit
import Foundation

/// «Write with LLM» apart from the screen (spec §7): one request for all the fields that need a sentence; for each field the
/// answer lacks, a request of its own, one after another. It talks to the app through a closure, so a test can stand in
/// for it.
@MainActor
struct I4Writer {
  /// `host.askLanguageModelAnswer(_:system:model:options:)`, with the model the user chose in the app.
  var ask: @MainActor (_ prompt: String, _ system: String, _ options: DTHubLLMOptions) async -> DTHubLLMAnswer
  var italian = L.systemIsItalian
  /// Told before each request on its own, so the screen can say «field 3 of 5».
  var progress: @MainActor (String) -> Void = { _ in }

  struct Outcome: Equatable {
    /// The sentences, by field key, each with the input it was written for.
    var phrases: [String: WrittenPhrase] = [:]
    /// The titles of the fields that got no sentence.
    var failed: [String] = []
    /// What to tell the user.
    var status = ""
  }

  /// Writes a sentence for each of `targets`; `fields` are all the fields (the final ones give context to the request).
  func write(targets: [I4FieldInfo], fields: [I4FieldInfo], system: String, options: DTHubLLMOptions) async -> Outcome {
    var outcome = Outcome()
    guard !targets.isEmpty else { return outcome }

    var firstFailure: String?
    switch await ask(I4Brief.make(targets: targets, written: I4Brief.context(of: fields, excluding: targets)), system, options) {
    case .text(let answer):
      let found = I4AnswerParser.parse(answer, tags: targets.map(\.tag))
      for field in targets {
        if let text = found[I4AnswerParser.normalized(field.tag)] {
          outcome.phrases[field.id] = WrittenPhrase(text: text, input: field.input)
        }
      }
    case .failure(let reason):
      firstFailure = reason
    }

    // The fields the answer did not cover: one request each.
    let missing = targets.filter { outcome.phrases[$0.id] == nil }
    var fallbackFailed = 0
    for (index, field) in missing.enumerated() {
      progress(L.format(.writingField, index + 1, missing.count, italian: italian))
      var context = I4Brief.context(of: fields, excluding: [field])
      for (id, phrase) in outcome.phrases {
        if let done = fields.first(where: { $0.id == id }), !context.contains(where: { $0.tag == done.tag }) {
          context.append((done.tag, phrase.text))
        }
      }
      switch await ask(I4Brief.make(targets: [field], written: context), system, options) {
      case .text(let answer):
        if let text = I4AnswerParser.parse(answer, tags: [field.tag])[I4AnswerParser.normalized(field.tag)] {
          outcome.phrases[field.id] = WrittenPhrase(text: text, input: field.input)
        } else {
          outcome.failed.append(field.title)
          fallbackFailed += 1
        }
      case .failure(let reason):
        outcome.failed.append(field.title)
        fallbackFailed += 1
        // The app said no twice, in a row: asking again for every field would only repeat it.
        if firstFailure != nil, outcome.phrases.isEmpty, fallbackFailed == 1 {
          outcome.failed += missing.dropFirst(index + 1).map(\.title)
          outcome.status = L.format(.llmFailed, reason, italian: italian)
          return outcome
        }
      }
    }

    var lines: [String] = []
    if !outcome.phrases.isEmpty { lines.append(L.format(.writtenCount, outcome.phrases.count, italian: italian)) }
    if !outcome.failed.isEmpty {
      lines.append(L.format(.failedFields, outcome.failed.joined(separator: ", "), italian: italian))
      if outcome.phrases.isEmpty, let firstFailure { lines.append(L.format(.llmFailed, firstFailure, italian: italian)) }
    }
    outcome.status = lines.joined(separator: " ")
    return outcome
  }
}
