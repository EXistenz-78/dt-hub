import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFStateTests {
  private func ready() -> (state: PFState, project: URL) {
    let state = PFState(italian: false)
    let project = TestImages.tempFolder()
    state.switchProject(folder: project)
    return (state, project)
  }

  private func pictures(_ names: [String]) -> [URL] {
    let folder = TestImages.tempFolder()
    return names.map { TestImages.png(width: 40, height: 30, in: folder, name: $0) }
  }

  @Test func addImagesCopiesThemIntoTheProjectAndKeepsOrder() {
    let (state, project) = ready()
    state.addImages(pictures(["a.png", "b.png", "c.png"]))
    #expect(state.doc.images.map(\.name) == ["a.png", "b.png", "c.png"])
    for image in state.doc.images {
      #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(image.file).path))
    }
    #expect(state.error == nil)
  }

  @Test func anUnreadableFileGivesAnErrorAndAddsNothing() throws {
    let (state, _) = ready()
    let text = TestImages.tempFolder().appendingPathComponent("notes.txt")
    try Data("no".utf8).write(to: text)
    state.addImages([text])
    #expect(state.doc.images.isEmpty)
    #expect(state.error?.contains("notes.txt") == true)
  }

  @Test func addingWithoutAProjectAsksToOpenOne() {
    let state = PFState(italian: false)
    state.addImages(pictures(["a.png"]))
    #expect(state.doc.images.isEmpty && state.error != nil)
  }

  @Test func moveChangesTheNumbering() {
    let (state, _) = ready()
    state.addImages(pictures(["a.png", "b.png", "c.png"]))
    state.move(from: IndexSet(integer: 2), to: 0)
    #expect(state.visibleImages.map(\.name) == ["c.png", "a.png", "b.png"])
    state.move(from: IndexSet(integer: 0), to: 3)
    #expect(state.visibleImages.map(\.name) == ["a.png", "b.png", "c.png"])
  }

  @Test func hiddenImagesAreNotVisibleImages() {
    let (state, _) = ready()
    state.addImages(pictures(["a.png", "b.png", "c.png"]))
    state.toggleVisible(state.doc.images[1].id)
    #expect(state.visibleImages.map(\.name) == ["a.png", "c.png"])
  }

  @Test func removeDeletesTheFileAndTheEntry() {
    let (state, project) = ready()
    state.addImages(pictures(["a.png", "b.png"]))
    let gone = state.doc.images[0]
    state.remove(gone.id)
    #expect(state.doc.images.map(\.name) == ["b.png"])
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(gone.file).path))
  }

  @Test func sizeUpAndDownFollowTheLadderAndStopAtTheEnds() {
    let (state, _) = ready()
    state.sizeUp()
    #expect(state.doc.size == PFSize(width: 2176, height: 1088))
    state.sizeDown()
    state.sizeDown()
    #expect(state.doc.size == PFSize(width: 1920, height: 960))
    state.mutate { $0.size = PFSizes.minimum }
    state.sizeDown()
    #expect(state.doc.size == PFSizes.minimum)
    state.mutate { $0.size = PFSizes.maximum }
    state.sizeUp()
    #expect(state.doc.size == PFSizes.maximum)
  }

  @Test func theDocumentIsSavedAndReloadedPerProject() {
    let (state, first) = ready()
    state.addImages(pictures(["a.png"]))
    state.mutate { $0.description = "misty lake" }
    let second = TestImages.tempFolder()
    state.switchProject(folder: second)
    #expect(state.doc.images.isEmpty && state.doc.description.isEmpty)
    state.switchProject(folder: first)
    #expect(state.doc.images.map(\.name) == ["a.png"] && state.doc.description == "misty lake")
  }

  @Test func canSendIsFalseWithNoVisibleImage() {
    let (state, _) = ready()
    #expect(!state.canSend)
    state.addImages(pictures(["a.png"]))
    #expect(state.canSend)
    state.toggleVisible(state.doc.images[0].id)
    #expect(!state.canSend)
  }

  @Test func theContextGivesTheModelTheExchangeFolderAndTheLastResult() {
    let state = PFState(italian: false)
    state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp/x","model":"flux_3_klein_q8p.ckpt"}"#.utf8))
    #expect(state.modelFile == "flux_3_klein_q8p.ckpt")
    #expect(state.exchangeFolder.path.hasPrefix("/tmp/x"))
  }
}
