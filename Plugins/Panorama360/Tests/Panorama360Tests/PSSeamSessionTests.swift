import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@Suite("Seam session")
struct PSSeamSessionTests {
  func plan() throws -> PSSeamPlan {
    guard case .success(let plan) = PSSeam.plan(width: 512, height: 256) else { throw PSSeamReason.notTwoToOne }
    return plan
  }

  /// A panorama whose columns are told apart by colour.
  func panorama() -> CGImage { TestImages.make(512, 256) { x, y in (UInt8(x / 2), UInt8(y), 40, 255) } }

  func session(folder: URL = TestImages.tempFolder()) throws -> (PSSeamSession, URL) {
    (PSSeamSession(panorama: panorama(), plan: try plan(), folder: folder, italian: false, description: "a quiet lake"), folder)
  }

  func load(_ path: String) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  /// What the model made: a whole panorama (the size of the pass).
  func generated(_ rgb: (UInt8, UInt8, UInt8), width: Int = 512, height: Int = 256, in folder: URL) -> (path: String, width: Int, height: Int) {
    let url = TestImages.file(TestImages.solid(width, height, rgb.0, rgb.1, rgb.2), in: folder, name: "generated.png", type: "public.png")
    return (url.path, width, height)
  }

  @Test func theFirstPassIsTheWholePanoramaRolledWithTheGreenBand() throws {
    let (session, _) = try session()
    let pass = session.next(index: 1, count: 1)
    let start = try #require(pass["startImage"] as? [String: Any])
    let image = try load(try #require(start["path"] as? String))
    #expect(image.width == 512 && image.height == 256)
    let original = panorama()
    let p = try plan()
    // Outside the green the picture is the panorama rolled by half: column x of it is column (x + 256) % 512 of the original.
    for x in [0, 100, 200, 300, 511] where !(p.greenX..<(p.greenX + p.greenWidth)).contains(x) {
      let expected = TestImages.pixel(original, (x + p.rollColumns) % 512, 17)
      let got = TestImages.pixel(image, x, 17)
      #expect(got.r == expected.r && got.g == expected.g, "column \(x)")
    }
    // The green is an eighth of the width, centred on the old seam, over the whole height.
    #expect(p.greenWidth == 64)
    for y in [0, 128, 255] {
      for x in [p.greenX, p.greenX + 31, p.greenX + p.greenWidth - 1] {
        let g = TestImages.pixel(image, x, y)
        #expect(g.r == 0 && g.g == 255 && g.b == 0, "x \(x) y \(y): \(g)")
      }
      #expect(TestImages.pixel(image, p.greenX - 1, y).g != 255 || TestImages.pixel(image, p.greenX - 1, y).r != 0)
    }
    let size = try #require(pass["size"] as? [String: Any])
    #expect(size["width"] as? Int == 512 && size["height"] as? Int == 256, "the pass is the whole panorama")
    #expect(pass["preset"] as? String == "PAN · 360 ERP Fast" && pass["strength"] as? Double == 1)
    #expect(pass["mask"] == nil && pass["maskSettings"] == nil, "the model fills the green: no mask")
    #expect((pass["fields"] as? [String: Any])?["prompt"] as? String == "a quiet lake", "the description of the place is the prompt")
    #expect(pass["loras"] == nil, "the LoRA and its trigger belong to the preset")
    #expect(pass["done"] == nil)
  }

  @Test func withoutADescriptionThePromptIsSentEmpty() throws {
    let session = PSSeamSession(panorama: panorama(), plan: try plan(), folder: TestImages.tempFolder(), italian: false, description: "  \n")
    let pass = session.next(index: 1, count: 1)
    #expect((pass["fields"] as? [String: Any])?["prompt"] as? String == "", "sent anyway: the app would keep the one of the tab")
  }

  @Test func aSecondNextIsDone() throws {
    let (session, _) = try session()
    _ = session.next(index: 1, count: 1)
    #expect(session.next(index: 2, count: 1)["done"] as? Bool == true)
    #expect(try session.next(index: 3, count: 1)["done"] as? Bool == true)
  }

  @Test func endFinishedComposesAndRollsBack() throws {
    let (session, folder) = try session()
    _ = session.next(index: 1, count: 1)
    let outcome = session.end(reason: "finished", previous: generated((0, 0, 255), in: folder))
    guard case .montage(let image, let description) = outcome else { Issue.record("expected a montage: \(outcome)"); return }
    #expect(image.width == 512 && image.height == 256)
    // The band was in the middle of the rolled panorama; rolled back it is split over the two edges of the picture: the seam is closed.
    let left = TestImages.pixel(image, 0, 100), right = TestImages.pixel(image, 511, 100)
    #expect(left.b > 150 && right.b > 150, "both sides of the old seam come from the generated band: \(left) \(right)")
    #expect(TestImages.pixel(image, 256, 100).b == 40, "the middle of the panorama keeps the original")
    #expect(description.contains("128"), "names the band width: \(description)")
  }

  @Test func endWithoutAFinishedRunSendsNothing() throws {
    for (reason, problem) in [("stopped", PSSeamProblem.stopped), ("failed", .failed), ("closed", .closed), ("surprise", .failed)] {
      let (session, folder) = try session()
      _ = session.next(index: 1, count: 1)
      guard case .nothing(let found) = session.end(reason: reason, previous: generated((0, 0, 255), in: folder)) else {
        Issue.record("\(reason) must send nothing")
        continue
      }
      #expect(found == problem, "\(reason)")
    }
  }

  @Test func endFinishedWithoutThePictureOrWithAWrongOne() throws {
    let (session, folder) = try session()
    _ = session.next(index: 1, count: 1)
    guard case .nothing(.noPicture) = session.end(reason: "finished", previous: nil) else { Issue.record("no previous"); return }
    guard case .nothing(.wrongSize) = session.end(reason: "finished", previous: generated((0, 0, 255), width: 128, height: 128, in: folder)) else {
      Issue.record("wrong size")
      return
    }
    guard case .nothing(.unreadable) = session.end(reason: "finished", previous: ("/nowhere/x.png", 512, 256)) else {
      Issue.record("unreadable")
      return
    }
  }

  @Test func theMontageIsMadeOnlyOnce() throws {
    let (session, folder) = try session()
    _ = session.next(index: 1, count: 1)
    let previous = generated((0, 0, 255), in: folder)
    guard case .montage = session.end(reason: "finished", previous: previous) else { Issue.record("first end"); return }
    guard case .nothing = session.end(reason: "finished", previous: previous) else { Issue.record("a second end must do nothing"); return }
  }

  @Test func theEstimateNamesThePresetAndTheSize() throws {
    let (session, _) = try session()
    let estimate = session.estimate()
    #expect(estimate["preset"] as? String == "PAN · 360 ERP Fast")
    let size = estimate["size"] as? [String: Any]
    #expect(size?["width"] as? Int == 512 && size?["height"] as? Int == 256)
  }

  @Test func theFilesOfThePassAreRemovedWhenTheSessionEnds() throws {
    let (session, folder) = try session()
    let pass = session.next(index: 1, count: 1)
    let start = try #require((pass["startImage"] as? [String: Any])?["path"] as? String)
    #expect(FileManager.default.fileExists(atPath: start))
    _ = session.end(reason: "finished", previous: generated((0, 0, 255), in: folder))
    #expect(!FileManager.default.fileExists(atPath: start))
    let (second, other) = try self.session()
    let again = second.next(index: 1, count: 1)
    _ = second.end(reason: "stopped", previous: nil)
    #expect(!FileManager.default.fileExists(atPath: try #require((again["startImage"] as? [String: Any])?["path"] as? String)))
    _ = other
  }

  @Test func aLocalWriteFailureIsNotReportedAsTheAppsFault() throws {
    // The folder of the pass cannot be created (a file is in its place): next gives up, and the end says the pass failed here.
    let blocker = TestImages.tempFolder().appendingPathComponent("not-a-folder")
    try Data("x".utf8).write(to: blocker)
    let session = PSSeamSession(panorama: panorama(), plan: try plan(), folder: blocker.appendingPathComponent("inside"), italian: false, description: "")
    #expect(session.next(index: 1, count: 1)["done"] as? Bool == true)
    guard case .nothing(.failed) = session.end(reason: "finished", previous: nil) else { Issue.record("expected .failed"); return }
  }
}
