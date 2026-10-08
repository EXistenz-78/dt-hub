import Foundation
import HubKit
import Testing

@testable import HubCore

struct SessionStoreTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SessionStoreTests-\(UUID())", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  @Test func noFileMeansNoSession() {
    #expect(SessionStore(fileURL: tempFile()).load() == nil)
  }

  @Test func restoresWhatWasSaved() throws {
    let store = SessionStore(fileURL: tempFile())
    let snapshot = SessionSnapshot(
      prompt: "a fox", negativePrompt: "blurry",
      parameters: GenerationParameters(width: 832, steps: 20, loras: [LoRASelection(file: "a", weight: 0.7)]),
      lockRatio: true)
    try store.save(snapshot)
    #expect(store.load() == snapshot)
  }

  @Test func anUnreadableFileMeansNoSession() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file)
    #expect(SessionStore(fileURL: file).load() == nil)
  }

  @Test func aPartialFileKeepsWhatItHas() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"prompt": "a fox", "parameters": {"steps": 20}}"#.utf8).write(to: file)
    let snapshot = try #require(SessionStore(fileURL: file).load())
    #expect(snapshot.prompt == "a fox")
    #expect(snapshot.negativePrompt == "")
    #expect(snapshot.parameters.steps == 20)
    #expect(snapshot.parameters.width == GenerationParameters.default.width)
  }

  @Test func theProjectNameSurvivesASaveAndLoad() throws {
    let store = SessionStore(fileURL: tempFile())
    try store.save(SessionSnapshot(prompt: "a fox", project: "Campagna"))
    #expect(store.load()?.project == "Campagna")
  }

  @Test func aFileWrittenBeforeProjectsHasNoProject() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"prompt": "a fox"}"#.utf8).write(to: file)
    #expect(try #require(SessionStore(fileURL: file).load()).project == nil)
  }

  @Test func aProjectOfTheWrongTypeIsIgnored() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"prompt": "a fox", "project": 3}"#.utf8).write(to: file)
    let snapshot = try #require(SessionStore(fileURL: file).load())
    #expect(snapshot.project == nil)
    #expect(snapshot.prompt == "a fox")
  }
}
