import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct SnapshotTests {
  func makeState() -> F3State {
    F3State(
      promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] },
      sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
  }

  func prepared() -> F3State {
    let state = makeState()
    state.document.description = "una strada"
    state.compositionChanged("Una donna <w_1> e un cane <d_1>.")
    state.commitComposition()
    state.update(element: "w_1") { $0.desc = "donna" }
    state.update(element: "d_1") { $0.desc = "cane" }
    return state
  }

  func result(_ rewrites: [F3Rewrite]) -> F3WriteResult { F3WriteResult(rewrites: rewrites, status: "ok", request: "", answer: "") }

  func rewrites() -> [F3Rewrite] {
    [
      F3Rewrite(kind: .description, original: "una strada", text: "A street."),
      F3Rewrite(kind: .composition, original: "Una donna <w_1> e un cane <d_1>.", text: "A woman <w_1> and a dog <d_1>."),
      F3Rewrite(kind: .element(id: "w_1"), original: "donna", text: "A woman."),
    ]
  }

  @Test func applyReplacesTextsAndTakesASnapshot() {
    let state = prepared()
    state.apply(result(rewrites()))
    #expect(state.document.description == "A street.")
    #expect(state.document.composition == "A woman <w_1> and a dog <d_1>.")
    #expect(state.document.element("w_1")?.desc == "A woman.")
    #expect(state.document.element("d_1")?.desc == "cane")
    #expect(state.document.snapshot?.description == "una strada")
    #expect(state.canUndo)
  }

  @Test func undoRestoresEverythingAndTurnsOff() {
    let state = prepared()
    state.apply(result(rewrites()))
    state.undo()
    #expect(state.document.description == "una strada")
    #expect(state.document.composition == "Una donna <w_1> e un cane <d_1>.")
    #expect(state.document.element("w_1")?.desc == "donna")
    #expect(state.document.snapshot == nil)
    #expect(!state.canUndo)
  }

  @Test func descriptionTermsAreClearedAfterWritingAndComeBackWithUndo() throws {
    let state = prepared()
    let light = try #require(state.catalog.categories(mode: .photo).first { $0.id == "light_source" })
    state.choose(light.terms[0].id)
    state.apply(result([F3Rewrite(kind: .description, original: "una strada", text: "A lit street.")]))
    #expect(state.document.selection.isEmpty)
    state.undo()
    #expect(state.document.selection == [light.terms[0].id])
  }

  @Test func onlyTheLastSnapshotIsKept() {
    let state = prepared()
    state.apply(result(rewrites()))
    state.apply(result([F3Rewrite(kind: .description, original: "A street.", text: "A wet street.")]))
    #expect(state.document.snapshot?.description == "A street.")
    state.undo()
    #expect(state.document.description == "A street.")
    #expect(!state.canUndo)
  }

  @Test func textChangedWhileWritingIsKept() {
    let state = prepared()
    state.document.description = "una strada diversa"
    state.apply(result(rewrites()))
    #expect(state.document.description == "una strada diversa")
    #expect(state.document.composition == "A woman <w_1> and a dog <d_1>.")
    #expect(state.status.contains("description"))
  }

  @Test func undoAfterRenamingIDsRestoresTextsAndResyncs() {
    let state = prepared()
    state.apply(result(rewrites()))
    state.compositionChanged("A woman <w_2> and a dog <d_1>.")
    state.commitComposition()
    state.undo()
    #expect(state.document.composition == "Una donna <w_1> e un cane <d_1>.")
    #expect(state.document.elements.map(\.id).sorted() == ["d_1", "w_1"])
  }

  @Test func snapshotMarkdownListsTheTexts() {
    let snapshot = F3Snapshot(description: "d", selection: ["t1"], composition: "c <a>", descs: ["a": "x"])
    #expect(snapshot.markdown.contains("## description\nd"))
    #expect(snapshot.markdown.contains("## element: a\nx"))
  }

  @Test func workFolderKeepsThreeFilesAndReplacesThem() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let work = F3WorkFolder(folder: folder)
    work.write(request: "R1", answer: "A1", before: F3Snapshot(description: "d", selection: [], composition: "", descs: [:]))
    work.write(request: "R2", answer: "A2", before: nil)
    #expect(try String(contentsOf: work.directory.appendingPathComponent("request.md"), encoding: .utf8) == "R2")
    #expect(try String(contentsOf: work.directory.appendingPathComponent("answer.md"), encoding: .utf8) == "A2")
    #expect(FileManager.default.fileExists(atPath: work.directory.appendingPathComponent("before.md").path))
  }
}
