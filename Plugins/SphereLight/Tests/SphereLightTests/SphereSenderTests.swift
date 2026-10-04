import Foundation
import Testing

@testable import SphereLight

/// What the sender asked of the app.
@MainActor
final class Spy {
  var contributions: [[String: Any]] = []
  var presets: [[[String: Any]]] = []
  var answer: [String: Any]? = ["type": "ok", "conflicts": 0]
}

@MainActor
@Suite("SphereSender")
struct SphereSenderTests {
  private func makeSender(_ spy: Spy, saveFolder: URL) -> SphereSender {
    SphereSender(
      contribute: { spy.contributions.append($0); return spy.answer },
      registerPresets: { spy.presets.append($0); return ["type": "ok"] },
      saveFolder: saveFolder, size: 32, shadowSamples: 2, italian: false)
  }

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private let lights = [LightParams.makeDefault(index: 0)]

  @Test func withoutAPictureFolderNothingIsSent() async throws {
    let spy = Spy()
    let desk = try makeFolder()
    defer { try? FileManager.default.removeItem(at: desk) }
    let line = await makeSender(spy, saveFolder: desk).send(
      .pipeline, lights: lights, overcast: false, saveToDesktop: true, tempFolder: nil)
    #expect(line == "No picture folder yet: switch the plug-in on first.")
    #expect(spy.contributions.isEmpty && spy.presets.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: desk.path).isEmpty)
  }

  @Test func thePipelineGoesWithTheSphereAndThePresetsAreOfferedFirst() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let line = await makeSender(spy, saveFolder: desk).send(
      .pipeline, lights: lights, overcast: true, saveToDesktop: false, tempFolder: temp.path)
    #expect(line == "Sent.")
    #expect(spy.presets.count == 1 && spy.presets[0].count == 2)
    let sphere = temp.appendingPathComponent(SphereSender.fileName).path
    #expect(FileManager.default.fileExists(atPath: sphere))
    let pipeline = try #require(spy.contributions.first?["pipeline"] as? [String: Any])
    let steps = try #require(pipeline["steps"] as? [[String: Any]])
    #expect(steps.count == 2)
    #expect((steps[1]["moodboard"] as? [[String: Any]])?.first?["path"] as? String == sphere)
    #expect(try FileManager.default.contentsOfDirectory(atPath: desk.path).isEmpty)
  }

  @Test func onlyTheMoodboardOffersNoPresetsAndSendsOnlyTheSphere() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    _ = await makeSender(spy, saveFolder: desk).send(
      .moodboard, lights: lights, overcast: true, saveToDesktop: false, tempFolder: temp.path)
    #expect(spy.presets.isEmpty)
    #expect(spy.contributions.count == 1 && Set(spy.contributions[0].keys) == ["moodboard"])
  }

  @Test func theBoxSavesACopyOnTheDesktopAndSaysSo() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let sender = makeSender(spy, saveFolder: desk)
    let line = await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(line == "Sent. Saved to Desktop as Sphere Light 001.png.")
    _ = await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: desk.path)) == ["Sphere Light 001.png", "Sphere Light 002.png"])
  }

  @Test func aFailedDesktopSaveIsReportedAndTheSendGoesOn() async throws {
    let spy = Spy()
    let temp = try makeFolder()
    defer { try? FileManager.default.removeItem(at: temp) }
    let missing = temp.appendingPathComponent("no-such-folder")
    let line = await makeSender(spy, saveFolder: missing).send(
      .moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(line == "Sent. Could not save to Desktop.")
    #expect(spy.contributions.count == 1)
  }

  @Test func conflictsAnErrorAndNoAnswerAreSaid() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let sender = makeSender(spy, saveFolder: desk)
    spy.answer = ["type": "ok", "conflicts": 2]
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "Sent. 2 conflict(s) waiting in the app.")
    spy.answer = ["type": "error", "text": "Plug-in is off"]
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "Plug-in is off")
    spy.answer = nil
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "No answer from the app.")
  }
}
