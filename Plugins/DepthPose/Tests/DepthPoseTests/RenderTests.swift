import AppKit
import Foundation
import SwiftUI
import Testing

@testable import DepthPose

/// Draws the tab offscreen, to look at it. With `DP_RENDER_DIR` set the pictures are written there as PNG files;
/// without it the tests only check that something was drawn.
@MainActor
@Suite("The tab on screen")
struct RenderTests {
  private func state(italian: Bool, modelReady: Bool, withImage: Bool, downloading: Bool = false) async throws -> DPState {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dp-render-\(UUID().uuidString)")
    let downloader = FakeDownloader()
    downloader.contents = ["Manifest.json": Data("{}".utf8)]
    let models = DPModelStore(
      folder: root, files: [DPModelFile(path: "M.mlpackage/Manifest.json", size: 2, sha256: nil)],
      packageName: "M.mlpackage", downloader: downloader,
      compile: { package in
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).mlmodelc")
        try FileManager.default.copyItem(at: package, to: out)
        return out
      }, validate: { _ in true })
    if modelReady { try await models.install { _ in } }
    let state = DPState(
      store: DPStore(defaults: UserDefaults(suiteName: "dp-render-\(UUID().uuidString)")!), models: models,
      detector: FakeDetector(people: [standingPerson]), makeDepth: { _ in DepthEstimator(model: FakeDepthModel()) },
      italian: italian)
    state.active = true
    state.tempFolder = root.path
    await state.refreshModelState()
    if withImage {
      let photo = Pictures.image(width: 480, height: 640, red: 90)
      state.setImage(data: Pictures.data(photo), name: "ritratto.png")
      state.mode = modelReady ? .both : .pose
      await state.create()
    }
    if downloading {
      let gate = AsyncGate()
      downloader.gate = gate
      Task { await state.downloadModel() }
      while downloader.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    }
    return state
  }

  private func render(_ state: DPState, dark: Bool, name: String) throws -> NSBitmapImageRep {
    // ImageRenderer draws the SwiftUI tree itself (an NSHostingView snapshot drops parts of it), over the
    // background the app puts under the tab.
    let content = DPView(state: state, actions: .none)
      .frame(width: 820, height: 520)
      .background(dark ? Color(white: 0.11) : Color(white: 0.96))
      .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let rep = NSBitmapImageRep(cgImage: image)
    if let folder = ProcessInfo.processInfo.environment["DP_RENDER_DIR"],
      let png = rep.representation(using: .png, properties: [:])
    {
      try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
      try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
    return rep
  }

  private func distinctColors(_ rep: NSBitmapImageRep) -> Int {
    var seen = Set<UInt32>()
    for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
      for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        seen.insert(
          UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8
            | UInt32(color.blueComponent * 255))
      }
    }
    return seen.count
  }

  @Test func theEmptyTabIsDrawnInBothLanguagesAndThemes() async throws {
    for italian in [false, true] {
      for dark in [false, true] {
        let rep = try render(
          try await state(italian: italian, modelReady: false, withImage: false), dark: dark,
          name: "empty-\(italian ? "it" : "en")-\(dark ? "dark" : "light").png")
        #expect(rep.pixelsWide >= 820 && distinctColors(rep) > 3)
      }
    }
  }

  @Test func theTabWithAPictureAndBothMapsIsDrawn() async throws {
    let rep = try render(
      try await state(italian: true, modelReady: true, withImage: true), dark: true, name: "maps-dark.png")
    #expect(distinctColors(rep) > 20)
  }

  @Test func theTabWithoutTheModelShowsThePoseOnly() async throws {
    let rep = try render(
      try await state(italian: false, modelReady: false, withImage: true), dark: false, name: "no-model-light.png")
    #expect(distinctColors(rep) > 10)
  }

  @Test func theTabWhileDownloadingIsDrawn() async throws {
    let state = try await state(italian: false, modelReady: false, withImage: false, downloading: true)
    let rep = try render(state, dark: true, name: "downloading-dark.png")
    #expect(distinctColors(rep) > 3)
  }
}
