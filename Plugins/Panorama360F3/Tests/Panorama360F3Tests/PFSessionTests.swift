import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360F3

struct PFSessionTests {
  typealias Previous = (path: String, width: Int, height: Int)

  private let size = PFSize(width: 256, height: 128)

  private func sources() -> [URL] {
    [
      TestImages.png(width: 40, height: 30, in: TestImages.tempFolder(), name: "a.png"),
      TestImages.png(width: 50, height: 20, in: TestImages.tempFolder(), name: "b.png"),
    ]
  }

  private func generate(folder: URL, description: String = "foggy", size: PFSize? = nil) -> PFSession {
    PFSession(kind: .generate(images: sources(), description: description, size: size ?? self.size), folder: folder)
  }

  /// A picture file of this size, as the app hands it over in `previous`.
  private func picture(_ width: Int, _ height: Int) -> Previous {
    let url = TestImages.writePNG(TestImages.coordinates(width: width, height: height), to: TestImages.tempFolder().appendingPathComponent("p.png"))
    return (url.path, width, height)
  }

  private func panorama(_ outcome: PFOutcome) -> (image: CGImage, corrected: Bool)? {
    if case .panorama(let image, let corrected) = outcome { return (image, corrected) }
    return nil
  }

  private func problem(_ outcome: PFOutcome) -> PFProblem? {
    if case .nothing(let problem) = outcome { return problem }
    return nil
  }

  private func dictionary(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }

  // MARK: the passes

  @Test func firstPassHasMoodboardAndNoStartImage() throws {
    let folder = TestImages.tempFolder()
    let session = generate(folder: folder, size: PFSize(width: 2048, height: 1024))
    let pass = session.next(index: 1, previous: nil)
    let moodboard = try #require(pass["moodboard"] as? [[String: Any]])
    #expect(moodboard.count == 2)
    #expect(moodboard.map { $0["name"] as? String } == ["a.png", "b.png"])
    for entry in moodboard {
      let path = try #require(entry["path"] as? String)
      #expect(path.hasPrefix(folder.path) && FileManager.default.fileExists(atPath: path))
    }
    #expect(pass["startImage"] == nil && pass["strength"] == nil)
    #expect(dictionary(pass["size"])["width"] as? Int == 2048 && dictionary(pass["size"])["height"] as? Int == 1024)
    #expect(pass["preset"] as? String == "PANO F3")
    let fields = dictionary(pass["fields"])
    #expect(fields["prompt"] as? String == "starting from <image 1>, <image 2>. foggy")
    #expect(fields["highRes"] as? Bool == true && fields["randomSeed"] as? Bool == true)
    let lora = try #require((pass["loras"] as? [[String: Any]])?.first)
    #expect(lora["file"] as? String == "f3_360_lora_f16.ckpt" && lora["weight"] as? Double == 1.0)
    #expect(lora["mode"] as? Int == 0 && lora["trigger"] as? String == "create a 360 hdr")
  }

  @Test func secondPassHasOnlyTheSquare() throws {
    let folder = TestImages.tempFolder()
    let session = generate(folder: folder)
    _ = session.next(index: 1, previous: nil)
    let pass = session.next(index: 2, previous: picture(256, 128))
    let start = dictionary(pass["startImage"])
    let path = try #require(start["path"] as? String)
    #expect(path.hasPrefix(folder.path))
    let square = try #require(TestImages.size(of: URL(fileURLWithPath: path)))
    #expect(square.width == 128 && square.height == 128)
    #expect(pass["moodboard"] == nil, "the Moodboard of the second pass is empty: only the square is a reference")
    #expect(dictionary(pass["size"])["width"] as? Int == 128 && dictionary(pass["size"])["height"] as? Int == 128)
    #expect(pass["preset"] as? String == "PANO F3 Seamfix" && pass["strength"] as? Double == 1.0)
    let fields = dictionary(pass["fields"])
    #expect(fields["prompt"] as? String == "" && fields["highRes"] as? Bool == true && fields["randomSeed"] as? Bool == true)
    let lora = try #require((pass["loras"] as? [[String: Any]])?.first)
    #expect(lora["file"] as? String == "f3_seamfix_lora_f16.ckpt" && lora["trigger"] as? String == "seamfix")
    // The white bar: 32 px from x 48 on a 128 px square made from a 256 px panorama.
    let image = try #require(PFSeamFixtures.read(URL(fileURLWithPath: path)))
    #expect(TestImages.pixel(image, 47, 5) != (255, 255, 255) && TestImages.pixel(image, 48, 5) == (255, 255, 255))
    #expect(TestImages.pixel(image, 79, 5) == (255, 255, 255) && TestImages.pixel(image, 80, 5) != (255, 255, 255))
  }

  @Test func estimateNamesPresetAndSize() {
    let all = generate(folder: TestImages.tempFolder(), size: PFSize(width: 2048, height: 1024)).estimate()
    #expect(all["preset"] as? String == "PANO F3" && dictionary(all["size"])["width"] as? Int == 2048)
    let only = PFSession(kind: .seamOnly(panorama: TestImages.coordinates(width: 256, height: 128)), folder: TestImages.tempFolder()).estimate()
    #expect(only["preset"] as? String == "PANO F3 Seamfix" && dictionary(only["size"])["height"] as? Int == 128)
  }

  // MARK: the end

  @Test func endFinishedMergesAndCleansUp() throws {
    let folder = TestImages.tempFolder()
    let session = generate(folder: folder)
    _ = session.next(index: 1, previous: nil)
    _ = session.next(index: 2, previous: picture(256, 128))
    let outcome = session.end(reason: "finished", previous: picture(128, 128))
    let result = try #require(panorama(outcome))
    #expect(result.corrected && result.image.width == 256 && result.image.height == 128)
    #expect((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true, "the files it wrote are gone")
  }

  @Test func aWrongSizedPictureKeepsTheRawPanorama() throws {
    let session = generate(folder: TestImages.tempFolder())
    _ = session.next(index: 1, previous: nil)
    _ = session.next(index: 2, previous: picture(256, 128))
    let result = try #require(panorama(session.end(reason: "finished", previous: picture(100, 100))))
    #expect(!result.corrected && result.image.width == 256)
  }

  @Test func anUnreadablePictureKeepsTheRawPanorama() throws {
    let session = generate(folder: TestImages.tempFolder())
    _ = session.next(index: 1, previous: nil)
    _ = session.next(index: 2, previous: picture(256, 128))
    let missing: Previous = (TestImages.tempFolder().appendingPathComponent("none.png").path, 128, 128)
    let result = try #require(panorama(session.end(reason: "finished", previous: missing)))
    #expect(!result.corrected)
  }

  @Test func failedAndStoppedAfterPassOneKeepTheRawPanorama() throws {
    for reason in ["failed", "stopped", "closed"] {
      let session = generate(folder: TestImages.tempFolder())
      _ = session.next(index: 1, previous: nil)
      _ = session.next(index: 2, previous: picture(256, 128))
      let result = try #require(panorama(session.end(reason: reason, previous: nil)), "\(reason)")
      #expect(!result.corrected && result.image.height == 128)
    }
  }

  @Test func stoppedBeforePassTwoGivesNothing() {
    let session = generate(folder: TestImages.tempFolder())
    _ = session.next(index: 1, previous: nil)
    #expect(problem(session.end(reason: "stopped", previous: nil)) == .stopped)
  }

  @Test func seamOnlyHasOnePassAndTheSquarePass() throws {
    let source = TestImages.coordinates(width: 256, height: 128)
    let session = PFSession(kind: .seamOnly(panorama: source), folder: TestImages.tempFolder())
    #expect(session.passCount == 1)
    let pass = session.next(index: 1, previous: nil)
    #expect(pass["preset"] as? String == "PANO F3 Seamfix" && pass["startImage"] != nil && pass["moodboard"] == nil)
    #expect(problem(session.end(reason: "failed", previous: nil)) == .failed)
    let again = PFSession(kind: .seamOnly(panorama: source), folder: TestImages.tempFolder())
    _ = again.next(index: 1, previous: nil)
    let result = try #require(panorama(again.end(reason: "finished", previous: picture(128, 128))))
    #expect(result.corrected && result.image.width == 256)
  }

  @Test func theGenerateSessionHasTwoPasses() {
    #expect(generate(folder: TestImages.tempFolder()).passCount == 2)
  }

  @Test func outOfOrderCallsAreDone() {
    let late = generate(folder: TestImages.tempFolder())
    #expect(late.next(index: 2, previous: picture(256, 128))["done"] as? Bool == true)
    let session = generate(folder: TestImages.tempFolder())
    #expect(session.next(index: 1, previous: nil)["done"] == nil)
    #expect(session.next(index: 1, previous: nil)["done"] as? Bool == true)
    #expect(session.next(index: 3, previous: nil)["done"] as? Bool == true)
    #expect(session.next(index: 2, previous: nil)["done"] as? Bool == true, "pass two needs the picture of pass one")
    _ = session.end(reason: "stopped", previous: nil)
    #expect(problem(session.end(reason: "stopped", previous: nil)) == .closed)
  }

  @Test func aSessionWithNoImagesHasNothingToGive() {
    let session = PFSession(kind: .generate(images: [], description: "", size: size), folder: TestImages.tempFolder())
    #expect(session.next(index: 1, previous: nil)["done"] as? Bool == true)
  }
}

enum PFSeamFixtures {
  static func read(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
