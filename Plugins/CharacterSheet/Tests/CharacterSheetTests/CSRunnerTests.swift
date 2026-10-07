import DTHubPluginKit
import Foundation
import Testing

@testable import CharacterSheet

/// What the runner asked of the app, and what the app answers.
@MainActor
final class Spy {
  var bodies: [[String: Any]] = []
  var requests: [CSRequest] = []
  var progress: [String] = []
  var copied: [(source: String, folder: String)] = []
  /// Answers of `contribute`, one per call; the last one repeats.
  var contributeAnswers: [[String: Any]?] = [["type": "ok", "conflicts": 0]]
  var llmAnswer: DTHubLLMAnswer = .text("")
  var templates: [CSTemplateFile: Result<String, CSTemplateError>] = [:]
  var peSystem: String? = "PE SYSTEM"
  var dates: [Date] = [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 1038)]
  var copyError: Error?

  func nextContributeAnswer() -> [String: Any]? {
    contributeAnswers.count > 1 ? contributeAnswers.removeFirst() : contributeAnswers[0]
  }

  func nextDate() -> Date { dates.count > 1 ? dates.removeFirst() : dates[0] }

  /// "moodboard", "size" or "prompt" for each body sent.
  var kinds: [String] {
    bodies.map { body in
      if body["moodboard"] != nil { return "moodboard" }
      let fields = body["fields"] as? [String: Any] ?? [:]
      return fields["prompt"] != nil ? "prompt" : "size"
    }
  }

  var writtenPrompt: String? {
    bodies.compactMap { ($0["fields"] as? [String: Any])?["prompt"] as? String }.first
  }
}

struct CopyFailure: Error {}

func visionModel(_ name: String, vision: Bool = true) -> DTHubLanguageModel {
  let json = "{\"name\":\"\(name)\",\"path\":\"/models/\(name)\",\"supportsImages\":\(vision)}"
  return try! JSONDecoder().decode(DTHubLanguageModel.self, from: Data(json.utf8))
}

@MainActor
@Suite("CSRunner")
struct CSRunnerTests {
  let spy = Spy()

  private func makeRunner() -> CSRunner {
    let spy = spy
    return CSRunner(
      contribute: { body in
        spy.bodies.append(body)
        return spy.nextContributeAnswer()
      },
      ask: { request in
        spy.requests.append(request)
        return spy.llmAnswer
      },
      copyImage: { source, folder in
        if let error = spy.copyError { throw error }
        spy.copied.append((source, folder))
        return folder + "/copied.png"
      },
      readTemplate: { spy.templates[$0] ?? .failure(.missing($0)) },
      readPESystem: { _ in spy.peSystem },
      now: { spy.nextDate() },
      templatesFolder: "/data/CharacterSheet", italian: false)
  }

  private func job(
    image: String? = "/pics/my ref.PNG", name: String = "Ayaka", useStatic: Bool = false,
    model: DTHubLanguageModel? = visionModel("Qwen3-VL-8B-Instruct-4bit"), folder: String? = "/tmp/dthub"
  ) -> CSJob {
    CSJob(imagePath: image, name: name, useStatic: useStatic, model: model, tempFolder: folder)
  }

  private func run(_ job: CSJob) async -> CSOutcome {
    await makeRunner().prepare(job, progress: { spy.progress.append($0) })
  }

  private func words(_ count: Int) -> String { Array(repeating: "w", count: count).joined(separator: " ") }

  @Test func everyWordIsInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func staticModeWritesTheStaticPromptWithoutAskingTheModel() async {
    spy.templates[.staticPrompt] = .success("Sheet for {{name}}")
    let outcome = await run(job(useStatic: true))
    #expect(spy.kinds == ["moodboard", "size", "prompt"])
    #expect(spy.writtenPrompt == "Sheet for Ayaka")
    #expect(spy.requests.isEmpty)
    #expect(outcome.succeeded)
    #expect(outcome.line == L.text(.doneStatic, italian: false))
  }

  @Test func theMoodboardGetsTheCopiedPicture() async {
    spy.templates[.staticPrompt] = .success("x")
    _ = await run(job(useStatic: true))
    #expect(spy.copied.map(\.source) == ["/pics/my ref.PNG"])
    #expect(spy.copied.map(\.folder) == ["/tmp/dthub"])
    let pictures = spy.bodies[0]["moodboard"] as? [[String: Any]]
    #expect(pictures?.first?["path"] as? String == "/tmp/dthub/copied.png")
  }

  @Test func genericModelRequestUsesTheMasterAsSystem() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .text("Ten sections")
    let model = visionModel("Qwen3-VL-8B-Instruct-4bit")
    let outcome = await run(job(model: model))
    #expect(
      spy.requests
        == [
          CSBrief.generic(
            model: model.name, image: "/tmp/dthub/copied.png", name: "Ayaka", master: "MASTER")
        ])
    #expect(spy.writtenPrompt == "Ten sections")
    #expect(outcome.succeeded)
    #expect(outcome.line == L.format(.doneLLM, 2, 38, italian: false))
  }

  @Test func peModelUsesItsOwnSystemAndTheMasterAsInstruction() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .text("{\"rewritten_prompt\":\"Sheet\",\"wh_ratio\":\"3:2\"}")
    let model = visionModel("Qwen-Image-2.1-PE-I2I-MLX-4bit")
    _ = await run(job(model: model))
    #expect(
      spy.requests
        == [
          CSBrief.peI2I(
            model: model.name, image: "/tmp/dthub/copied.png", name: "Ayaka", master: "MASTER",
            peSystem: "PE SYSTEM")
        ])
    #expect(spy.writtenPrompt == "Sheet")
  }

  @Test func aPEWithoutItsSystemPromptStopsBeforeTheApp() async {
    spy.templates[.master] = .success("MASTER")
    spy.peSystem = nil
    let model = visionModel("Qwen-Image-2.1-PE-I2I-MLX-4bit")
    let outcome = await run(job(model: model))
    #expect(outcome.line == L.format(.peSystemMissing, model.name, italian: false))
    #expect(!outcome.succeeded)
    #expect(spy.bodies.isEmpty && spy.requests.isEmpty && spy.copied.isEmpty)
  }

  @Test(arguments: [CSTemplateError.missing(.master), .empty(.master)])
  func aBadMasterStopsBeforeTouchingTheApp(error: CSTemplateError) async {
    spy.templates[.master] = .failure(error)
    let outcome = await run(job())
    let expected =
      error == .missing(.master)
      ? L.format(.templateMissing, "master-prompt.txt", "/data/CharacterSheet", italian: false)
      : L.format(.templateEmpty, "master-prompt.txt", italian: false)
    #expect(outcome.line == expected)
    #expect(spy.bodies.isEmpty && spy.requests.isEmpty && spy.copied.isEmpty)
  }

  @Test func aMissingStaticFileStopsBeforeTouchingTheApp() async {
    let outcome = await run(job(useStatic: true))
    #expect(outcome.line == L.format(.templateMissing, "static-prompt.txt", "/data/CharacterSheet", italian: false))
    #expect(spy.bodies.isEmpty && spy.copied.isEmpty)
  }

  @Test func noImageStopsEverything() async {
    let outcome = await run(job(image: nil))
    #expect(outcome.line == L.text(.needImage, italian: false))
    #expect(spy.bodies.isEmpty && spy.requests.isEmpty && spy.copied.isEmpty)
  }

  @Test func noTempFolderStopsEverything() async {
    spy.templates[.master] = .success("MASTER")
    let outcome = await run(job(folder: nil))
    #expect(outcome.line == L.text(.noFolder, italian: false))
    #expect(spy.bodies.isEmpty && spy.requests.isEmpty && spy.copied.isEmpty)
  }

  @Test func llmModeWithoutAModelStopsEverything() async {
    spy.templates[.master] = .success("MASTER")
    let outcome = await run(job(model: nil))
    #expect(outcome.line == L.text(.noVisionModel, italian: false))
    #expect(spy.bodies.isEmpty && spy.requests.isEmpty && spy.copied.isEmpty)
  }

  @Test func staticModeNeedsNoModel() async {
    spy.templates[.staticPrompt] = .success("x")
    let outcome = await run(job(useStatic: true, model: nil))
    #expect(outcome.succeeded)
  }

  @Test func aFailedCopyStopsBeforeTheApp() async {
    spy.templates[.staticPrompt] = .success("x")
    spy.copyError = CopyFailure()
    let outcome = await run(job(useStatic: true))
    #expect(outcome.line == L.text(.copyFailed, italian: false))
    #expect(spy.bodies.isEmpty)
  }

  @Test func anEmptyAnswerLeavesThePromptAlone() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .text("<think>x")
    let outcome = await run(job())
    #expect(outcome.line == L.text(.emptyAnswer, italian: false))
    #expect(!outcome.succeeded)
    #expect(spy.kinds == ["moodboard", "size"])
  }

  @Test func aFailureOfTheAppIsReported() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .failure("no model chosen")
    let outcome = await run(job())
    #expect(outcome.line == L.format(.llmFailed, "no model chosen", italian: false))
    #expect(spy.writtenPrompt == nil)
  }

  @Test func aContributeErrorStopsTheSequence() async {
    spy.templates[.master] = .success("MASTER")
    spy.contributeAnswers = [["type": "error", "text": "boom"]]
    let outcome = await run(job())
    #expect(outcome.line.contains("boom"))
    #expect(!outcome.succeeded)
    #expect(spy.kinds == ["moodboard"])
    #expect(spy.requests.isEmpty)
  }

  @Test func anAppThatDoesNotAnswerIsReported() async {
    spy.templates[.master] = .success("MASTER")
    spy.contributeAnswers = [nil]
    let outcome = await run(job())
    #expect(outcome.line == L.text(.notAnswered, italian: false))
    #expect(spy.requests.isEmpty)
  }

  @Test func progressLinesFollowTheSteps() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .text("Sheet")
    _ = await run(job())
    #expect(spy.progress == [L.text(.sendingImage, italian: false), L.text(.writingBrief, italian: false)])
  }

  @Test func theLineShowsWordsAndSeconds() async {
    spy.templates[.master] = .success("MASTER")
    spy.llmAnswer = .text(words(1420))
    let outcome = await run(job())
    #expect(outcome.line == "Prompt written: 1420 words in 38 s.")
  }

  @Test func copyIntoFolderCopiesAndOverwrites() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appendingPathComponent("my ref.PNG")
    let second = root.appendingPathComponent("other.PNG")
    try Data("one".utf8).write(to: first)
    try Data("two".utf8).write(to: second)
    let folder = root.appendingPathComponent("temp").path
    let copy = try CSRunner.copyIntoFolder(first.path, folder)
    #expect(copy == folder + "/com.exiztenz.dthub.charactersheet-reference.PNG")
    #expect(try String(contentsOfFile: copy, encoding: .utf8) == "one")
    let again = try CSRunner.copyIntoFolder(second.path, folder)
    #expect(again == copy)
    #expect(try String(contentsOfFile: again, encoding: .utf8) == "two")
    #expect(throws: (any Error).self) { try CSRunner.copyIntoFolder(root.appendingPathComponent("nope.png").path, folder) }
  }
}
