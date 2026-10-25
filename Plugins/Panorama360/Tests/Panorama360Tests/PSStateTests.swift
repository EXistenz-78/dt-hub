import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("State")
struct PSStateTests {
  @Test func nothingIsWrittenBeforeAProjectIsOpen() {
    let state = PSState()
    state.mutate { $0.description = "x" }
    #expect(state.doc.description == "x")
    #expect(state.projectFolder == nil)
  }

  @Test func everyChangeIsSavedInTheProjectFolder() {
    let folder = PSModelsTests.folder()
    let state = PSState()
    state.switchProject(folder: folder)
    state.mutate { $0.description = "a valley" }
    #expect(PanoState.load(from: folder).description == "a valley")
    state.doc.mode = .fast
    #expect(PanoState.load(from: folder).mode == .fast)
  }

  @Test func switchingProjectSwapsTheDocumentWithoutWritingIntoTheNewOne() throws {
    let first = PSModelsTests.folder()
    let second = PSModelsTests.folder()
    var other = PanoState()
    other.description = "second"
    try other.save(to: second)
    let state = PSState()
    state.switchProject(folder: first)
    state.mutate { $0.description = "first" }
    state.switchProject(folder: second)
    #expect(state.doc.description == "second")
    #expect(PanoState.load(from: first).description == "first")
    state.switchProject(folder: PSModelsTests.folder())
    #expect(state.doc == PanoState())
  }

  @Test func modelIsBaseReadsTheFileName() {
    let state = PSState()
    #expect(state.modelIsBase == nil)
    state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp"}"#.utf8))
    #expect(state.modelIsBase == nil)
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_base_9b_i8x.ckpt","tempFolder":"/tmp/t"}"#.utf8))
    #expect(state.modelIsBase == true)
    #expect(state.tempFolder == "/tmp/t")
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_9b_q8p.ckpt","tempFolder":"/tmp/t"}"#.utf8))
    #expect(state.modelIsBase == false)
  }
}
