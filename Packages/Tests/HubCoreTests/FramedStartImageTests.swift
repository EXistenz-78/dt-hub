import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

/// The framed start image the plug-ins are offered: made away from the main actor, offered when it is ready.
@MainActor
struct FramedStartImageTests {
  private let root = FileManager.default.temporaryDirectory.appendingPathComponent("FramedStartImageTests-\(UUID())", isDirectory: true)

  private func control() -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  /// Asks for the picture and waits until `onChange` says one is ready.
  private func ready(_ framed: FramedStartImage, _ control: ControlStore, width: Int, height: Int) async -> String? {
    await withCheckedContinuation { continuation in
      framed.onChange = { [weak framed] in
        framed?.onChange = nil
        continuation.resume()
      }
      _ = framed.path(for: control, canvasWidth: width, canvasHeight: height, fill: .gray)
    }
    return framed.path(for: control, canvasWidth: width, canvasHeight: height, fill: .gray)
  }

  @Test func thePictureIsOfferedOnceItIsWrittenAtTheSizeOfTheCanvas() async throws {
    let control = control()
    try control.setImage(data: pictureData(width: 300, height: 200), name: "a.png", source: .pasteboard)
    let framed = FramedStartImage(folder: root.appendingPathComponent("out", isDirectory: true))
    // Nothing is ready at the first request: the answer does not wait for the picture.
    #expect(framed.path(for: control, canvasWidth: 128, canvasHeight: 64, fill: .gray) == nil)
    let path = try #require(await ready(framed, control, width: 128, height: 64))
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 128 && image.height == 64)
  }

  private func size(at path: String?) throws -> [Int] {
    let path = try #require(path)
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return [image.width, image.height]
  }

  @Test func aPictureIsOfferedEvenWhenAnotherFramingWasAskedMeanwhileAndTheNewOneFollows() async throws {
    let control = control()
    try control.setImage(data: pictureData(width: 300, height: 200), name: "a.png", source: .pasteboard)
    let framed = FramedStartImage(folder: root.appendingPathComponent("out", isDirectory: true))
    var sizes: [[Int]] = []
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      framed.onChange = { [weak framed] in
        // As the app does: it asks again for the canvas as it is now.
        if let size = try? size(at: framed?.path(for: control, canvasWidth: 96, canvasHeight: 96, fill: .gray)) {
          sizes.append(size)
        }
        if sizes.last == [96, 96] {
          framed?.onChange = nil
          continuation.resume()
        }
      }
      _ = framed.path(for: control, canvasWidth: 128, canvasHeight: 64, fill: .gray)
      Task {
        // The first picture is being made (or is ready) when the canvas changes.
        try? await Task.sleep(for: .milliseconds(20))
        _ = framed.path(for: control, canvasWidth: 96, canvasHeight: 96, fill: .gray)
      }
    }
    #expect(sizes == [[128, 64], [96, 96]])
  }

  @Test func aPictureMadeForAStartImageThatWentAwayIsNotOffered() async throws {
    let control = control()
    try control.setImage(data: pictureData(width: 300, height: 200), name: "a.png", source: .pasteboard)
    let out = root.appendingPathComponent("out", isDirectory: true)
    let framed = FramedStartImage(folder: out)
    _ = framed.path(for: control, canvasWidth: 128, canvasHeight: 64, fill: .gray)
    control.removeImage()
    #expect(framed.path(for: control, canvasWidth: 128, canvasHeight: 64, fill: .gray) == nil)
    try await Task.sleep(for: .milliseconds(300))
    #expect(framed.path == nil)
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).isEmpty)
  }
}
