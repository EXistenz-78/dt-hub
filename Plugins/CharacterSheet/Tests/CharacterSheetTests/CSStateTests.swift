import DTHubPluginKit
import Foundation
import Testing

@testable import CharacterSheet

@MainActor
@Suite("CSState")
struct CSStateTests {
  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func context(models: String?) throws -> DTHubContext {
    let list = models.map { ",\"languageModels\":\($0)" } ?? ""
    let json = "{\"family\":\"qwen_image_2.1\",\"tempFolder\":\"/t\"\(list)}"
    return try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8))
  }

  private let threeModels =
    "[{\"name\":\"A-text\",\"path\":\"/m/a\",\"supportsImages\":false},{\"name\":\"B-vision\",\"path\":\"/m/b\",\"supportsImages\":true},{\"name\":\"C-vision\",\"path\":\"/m/c\",\"supportsImages\":true}]"

  @Test func visionModelsKeepsOnlyThoseWithImages() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: threeModels))
    #expect(state.visionModels.map(\.name) == ["B-vision", "C-vision"])
  }

  @Test func theSavedChoiceIsUsedWhenItExists() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: threeModels))
    state.selectedModel = "C-vision"
    #expect(state.resolvedModel?.name == "C-vision")
  }

  @Test func aMissingSavedModelFallsBackToTheFirstWithVision() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: threeModels))
    state.selectedModel = "Gone"
    #expect(state.resolvedModel?.name == "B-vision")
    state.selectedModel = "A-text"  // a model without vision is not offered either
    #expect(state.resolvedModel?.name == "B-vision")
  }

  @Test func noVisionModelGivesNil() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: "[{\"name\":\"A\",\"path\":\"/m/a\",\"supportsImages\":false}]"))
    #expect(state.resolvedModel == nil)
    state.update(from: try context(models: nil))
    #expect(state.resolvedModel == nil)
    #expect(state.visionModels.isEmpty)
  }

  @Test func choicesSurviveARestart() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = CSState(store: CSSettingsStore(folder: folder))
    first.useStatic = true
    first.selectedModel = "C-vision"
    first.imagePath = "/pics/a.png"
    first.name = "Ayaka"
    let second = CSState(store: CSSettingsStore(folder: folder))
    #expect(second.useStatic)
    #expect(second.selectedModel == "C-vision")
    #expect(second.imagePath == nil)
    #expect(second.name == "")
  }

  @Test func firstRunDefaults() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    #expect(!state.useStatic)
    #expect(state.selectedModel == nil)
  }

  @Test func aCorruptSettingsFileFallsBackToDefaults() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try "not json".write(to: folder.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let state = CSState(store: CSSettingsStore(folder: folder))
    #expect(!state.useStatic)
    #expect(state.selectedModel == nil)
  }

  @Test func savingCreatesTheFolder() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("not/yet")
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.useStatic = true
    #expect(CSSettingsStore(folder: folder).load().useStatic)
  }

  @Test func contextFillsTheFolderAndTheFamily() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: threeModels))
    #expect(state.tempFolder == "/t")
    #expect(state.family == "qwen_image_2.1")
    #expect(state.languageModels.count == 3)
    state.update(from: try context(models: nil))
    #expect(state.languageModels.isEmpty)
  }

  @Test func onlyOnePrepareAtATime() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    #expect(state.beginPrepare())
    #expect(state.busy)
    #expect(!state.beginPrepare())
    state.endPrepare(status: "Done.")
    #expect(!state.busy)
    #expect(state.status == "Done.")
    #expect(state.beginPrepare())
  }

  @Test func jobCarriesWhatTheTabHolds() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = CSState(store: CSSettingsStore(folder: folder))
    state.update(from: try context(models: threeModels))
    state.imagePath = "/pics/a.png"
    state.name = "Ayaka"
    state.useStatic = true
    state.selectedModel = "C-vision"
    let job = state.job
    #expect(job.imagePath == "/pics/a.png")
    #expect(job.name == "Ayaka")
    #expect(job.useStatic)
    #expect(job.model?.name == "C-vision")
    #expect(job.tempFolder == "/t")
  }
}
