import DTHubPluginKit
import Foundation

/// What «Prepare» works on.
struct CSJob: Equatable {
  var imagePath: String?
  var name: String
  var useStatic: Bool
  /// The language model to ask; unused in static mode.
  var model: DTHubLanguageModel?
  /// The app's folder to exchange picture files through.
  var tempFolder: String?
  var kind: CSSheetKind = .base
}

struct CSOutcome: Equatable {
  /// The status line to show.
  var line: String
  var succeeded: Bool
}

/// The whole job of the «Prepare» button (spec §3.5). It talks to the app and to the disk through closures, so the
/// tests stand in for both.
@MainActor
struct CSRunner {
  /// `host.contribute`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  /// `host.askLanguageModelAnswer`.
  var ask: @MainActor (CSRequest) async -> DTHubLLMAnswer
  var copyImage: (_ source: String, _ tempFolder: String) throws -> String
  var readTemplate: (CSTemplateFile) -> Result<String, CSTemplateError>
  /// The system prompt that comes with a Qwen PE I2I model; nil when it is not there.
  var readPESystem: (DTHubLanguageModel) -> String?
  var now: () -> Date
  /// Shown in the error about a missing file.
  var templatesFolder: String
  var italian: Bool

  /// Checks first (nothing that touches the app), then: picture to the Moodboard, size, prompt. The fields are only
  /// written when the prompt is ready.
  func prepare(_ job: CSJob, progress: (String) -> Void) async -> CSOutcome {
    guard let image = job.imagePath else { return failure(.needImage) }
    guard let tempFolder = job.tempFolder else { return failure(.noFolder) }
    var model: DTHubLanguageModel?
    if !job.useStatic {
      guard let chosen = job.model else { return failure(.noVisionModel) }
      model = chosen
    }

    let file = CSTemplateFile.of(useStatic: job.useStatic, kind: job.kind)
    let template: String
    switch readTemplate(file) {
    case .success(let text): template = text
    case .failure(.missing(let missing)):
      return outcome(L.format(.templateMissing, missing.rawValue, templatesFolder, italian: italian))
    case .failure(.empty(let empty)):
      return outcome(L.format(.templateEmpty, empty.rawValue, italian: italian))
    }

    var peSystem: String?
    if let model, CSBrief.isPEI2I(model.name) {
      guard let system = readPESystem(model) else {
        return outcome(L.format(.peSystemMissing, model.name, italian: italian))
      }
      peSystem = system
    }

    progress(L.text(.sendingImage, italian: italian))
    let copy: String
    do { copy = try copyImage(image, tempFolder) } catch { return failure(.copyFailed) }
    if let problem = problem(in: await contribute(CSMessages.moodboard(imagePath: copy))) { return outcome(problem) }
    if let problem = problem(in: await contribute(CSMessages.size())) { return outcome(problem) }

    if job.useStatic {
      let prompt = CSTemplates.fill(template, name: job.name)
      if let problem = problem(in: await contribute(CSMessages.prompt(prompt))) { return outcome(problem) }
      return CSOutcome(line: L.text(.doneStatic, italian: italian), succeeded: true)
    }

    guard let model else { return failure(.noVisionModel) }
    progress(L.text(.writingBrief, italian: italian))
    let request =
      peSystem.map { CSBrief.peI2I(model: model.name, image: copy, name: job.name, master: template, peSystem: $0) }
      ?? CSBrief.generic(model: model.name, image: copy, name: job.name, master: template)
    let started = now()
    let answer = await ask(request)
    let seconds = Int(now().timeIntervalSince(started).rounded())
    switch answer {
    case .failure(let reason):
      return outcome(L.format(.llmFailed, reason, italian: italian))
    case .text(let raw):
      guard let prompt = CSAnswer.parse(raw) else { return failure(.emptyAnswer) }
      if let problem = problem(in: await contribute(CSMessages.prompt(prompt))) { return outcome(problem) }
      let words = prompt.split(whereSeparator: \.isWhitespace).count
      return CSOutcome(line: L.format(.doneLLM, words, seconds, italian: italian), succeeded: true)
    }
  }

  /// Copies the picture into the app's folder under a fixed name (a second run replaces the first copy) and returns
  /// the path of the copy.
  static func copyIntoFolder(_ source: String, _ tempFolder: String) throws -> String {
    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: tempFolder, withIntermediateDirectories: true)
    let ext = (source as NSString).pathExtension
    let name = ext.isEmpty ? CSMessages.referenceFileStem : CSMessages.referenceFileStem + "." + ext
    let destination = (tempFolder as NSString).appendingPathComponent(name)
    if fileManager.fileExists(atPath: destination) { try fileManager.removeItem(atPath: destination) }
    try fileManager.copyItem(atPath: source, toPath: destination)
    return destination
  }

  private func failure(_ key: L.Key) -> CSOutcome { outcome(L.text(key, italian: italian)) }

  private func outcome(_ line: String) -> CSOutcome { CSOutcome(line: line, succeeded: false) }

  /// The app's complaint about a `contribute`, if any.
  private func problem(in answer: [String: Any]?) -> String? {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" {
      return answer["text"] as? String ?? L.text(.notAnswered, italian: italian)
    }
    return nil
  }
}
