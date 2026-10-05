import DTHubPluginKit
import Foundation

/// The "Write prompt" button and the scene Shuffle, apart from the screen: choose the language model, build the request,
/// read the answer and contribute it to the Generation tab. It talks to the app through closures, so a test can stand in
/// for it.
@MainActor
struct PMWriter {
  /// `host.askLanguageModelAnswer(_:system:model:options:)`.
  var ask: @MainActor (_ prompt: String, _ system: String?, _ model: String?, _ options: DTHubLLMOptions) async -> DTHubLLMAnswer
  /// `host.contribute`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var italian = L.systemIsItalian
  var folderSize: (String) -> Int64 = PEPlanner.folderSize
  var readFile: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }

  /// What the tab knows when the button is pressed.
  struct Request {
    var family: String
    var masters: MasterPrompts
    var description: String
    var terms: [SelectedTerm]
    var booru: Bool
    var languageModels: [DTHubLanguageModel]
  }

  struct Outcome: Equatable {
    /// The lines to show under the button.
    var status: String
    /// The format a prompt enhancer suggested, when it did.
    var ratio: String?
    var sent: Bool
  }

  /// The generic model has to say a prompt, maybe with its negative: room for that.
  /// A model that thinks by default would spend its tokens on the reasoning and never close it: no thinking.
  static let genericOptions = DTHubLLMOptions(maxTokens: 2048, thinking: false)

  func write(_ request: Request) async -> Outcome {
    let master = request.masters.families[request.family]
    let plan = PEPlanner.plan(
      family: request.family, languageModels: request.languageModels, folderSize: folderSize, readFile: readFile)
    var notes: [String] = []
    let answer: DTHubLLMAnswer
    switch plan {
    case .enhancer(let enhancer):
      answer = await ask(
        BriefBuilder.enhancerRequest(description: request.description, terms: request.terms), enhancer.system, enhancer.model,
        enhancer.options)
    case .generic(let reason):
      guard let brief = BriefBuilder.make(
        family: request.family, masters: request.masters, description: request.description, terms: request.terms,
        booru: request.booru)
      else { return Outcome(status: L.text(.noMasterPrompt, italian: italian), ratio: nil, sent: false) }
      switch reason {
      case .modelMissing?:
        notes.append(L.text(.enhancerModelMissing, italian: italian))
      case .systemPromptMissing(let model)?:
        notes.append(L.format(.enhancerSystemMissing, model, italian: italian))
      case nil:
        break
      }
      answer = await ask(brief.prompt, brief.system, nil, Self.genericOptions)
    }

    let text: String
    switch answer {
    case .failure(let reason):
      return Outcome(status: ([L.format(.llmFailed, reason, italian: italian)] + notes).joined(separator: " "), ratio: nil, sent: false)
    case .text(let value):
      text = value
    }
    guard let parsed = AnswerParser.parse(text) else {
      return Outcome(status: ([L.text(.emptyAnswer, italian: italian)] + notes).joined(separator: " "), ratio: nil, sent: false)
    }
    // The negative prompt is written only where the family reads one.
    var fields: [String: Any] = ["prompt": parsed.prompt]
    if master?.negative == true, let negative = parsed.negative { fields["negativePrompt"] = negative }
    let result = await contribute(["fields": fields])
    var lines = [Self.describe(result, italian: italian)] + notes
    if let ratio = parsed.ratio { lines.append(L.format(.ratio, ratio, italian: italian)) }
    if master?.provisional == true, case .generic = plan { lines.append(L.text(.provisional, italian: italian)) }
    return Outcome(status: lines.joined(separator: " "), ratio: parsed.ratio, sent: Self.wasAccepted(result))
  }

  static func wasAccepted(_ answer: [String: Any]?) -> Bool {
    guard let answer else { return false }
    return answer["type"] as? String != "error"
  }

  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }

  // MARK: The suggested format

  /// Sets the Generation tab to `ratio` with the area it has now (spec §7). Only when the user presses «Apply».
  func applyRatio(_ ratio: String, currentWidth: Int?, currentHeight: Int?) async -> Outcome {
    guard let currentWidth, let currentHeight, currentWidth > 0, currentHeight > 0 else {
      return Outcome(status: L.text(.noSize, italian: italian), ratio: nil, sent: false)
    }
    guard let size = RatioSize.size(ratio: ratio, area: currentWidth * currentHeight) else {
      return Outcome(status: L.format(.badRatio, ratio, italian: italian), ratio: nil, sent: false)
    }
    let result = await contribute(["fields": ["width": size.width, "height": size.height]])
    guard Self.wasAccepted(result) else {
      return Outcome(status: Self.describe(result, italian: italian), ratio: ratio, sent: false)
    }
    return Outcome(status: L.format(.formatApplied, size.width, size.height, italian: italian), ratio: nil, sent: true)
  }

  // MARK: The scene Shuffle

  static let sceneSystem = """
    You invent ideas for images. Reply with exactly two short sentences: the first names a subject and what it is doing, \
    the second describes the setting. Be concrete and visual; no title, no quotation marks, no lists.
    """

  func scene() async -> Result<String, SceneFailure> {
    let language = italian ? "Italian" : "English"
    let answer = await ask(
      "Invent a subject with an action, and a setting, for an image. Write the two sentences in \(language).",
      Self.sceneSystem, nil, DTHubLLMOptions(temperature: 1.0, maxTokens: 300, thinking: false))
    switch answer {
    case .failure(let reason):
      return .failure(SceneFailure(text: L.format(.sceneFailed, reason, italian: italian)))
    case .text(let value):
      guard let scene = AnswerParser.parse(value)?.prompt else {
        return .failure(SceneFailure(text: L.format(.sceneFailed, L.text(.emptyAnswer, italian: italian), italian: italian)))
      }
      return .success(scene)
    }
  }

  struct SceneFailure: Error, Equatable { var text: String }
}
