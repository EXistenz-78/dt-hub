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
    (PSSeamSession(panorama: panorama(), plan: try plan(), folder: folder, italian: false), folder)
  }

  func load(_ path: String) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  func square(_ rgb: (UInt8, UInt8, UInt8), size: Int = 256, in folder: URL) -> (path: String, width: Int, height: Int) {
    let url = TestImages.file(TestImages.solid(size, size, rgb.0, rgb.1, rgb.2), in: folder, name: "generated.png", type: "public.png")
    return (url.path, size, size)
  }

  @Test func theFirstPassIsAutonomous() throws {
    let (session, _) = try session()
    let pass = session.next(index: 1, count: 1)
    let start = try #require(pass["startImage"] as? [String: Any])
    let mask = try #require(pass["mask"] as? [String: Any])
    let image = try load(try #require(start["path"] as? String))
    #expect(image.width == 256 && image.height == 256)
    // The start picture is the central square of the panorama rolled by half: its first column is column cropX of the rolled one.
    let original = panorama()
    let p = try plan()
    let expected = TestImages.pixel(original, (p.cropX + p.rollColumns) % 512, 17)
    #expect(TestImages.pixel(image, 0, 17).r == expected.r && TestImages.pixel(image, 0, 17).g == expected.g)
    let maskImage = try load(try #require(mask["path"] as? String))
    #expect(maskImage.width == 256 && maskImage.height == 256)
    let size = try #require(pass["size"] as? [String: Any])
    #expect(size["width"] as? Int == 256 && size["height"] as? Int == 256)
    #expect(pass["preset"] as? String == "PANO Test" && pass["strength"] as? Double == 1)
    let settings = try #require(pass["maskSettings"] as? [String: Any])
    #expect(settings["blur"] as? Int == 24 && settings["outset"] as? Int == 0 && settings["preserveOriginal"] as? Bool == true)
    #expect(pass["fields"] == nil && pass["loras"] == nil, "the prompt and the parameters belong to the preset")
    #expect(pass["done"] == nil)
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
    let outcome = session.end(reason: "finished", previous: square((0, 0, 255), in: folder))
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
      guard case .nothing(let found) = session.end(reason: reason, previous: square((0, 0, 255), in: folder)) else {
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
    guard case .nothing(.wrongSize) = session.end(reason: "finished", previous: square((0, 0, 255), size: 128, in: folder)) else {
      Issue.record("wrong size")
      return
    }
    guard case .nothing(.unreadable) = session.end(reason: "finished", previous: ("/nowhere/x.png", 256, 256)) else {
      Issue.record("unreadable")
      return
    }
  }

  @Test func theMontageIsMadeOnlyOnce() throws {
    let (session, folder) = try session()
    _ = session.next(index: 1, count: 1)
    let previous = square((0, 0, 255), in: folder)
    guard case .montage = session.end(reason: "finished", previous: previous) else { Issue.record("first end"); return }
    guard case .nothing = session.end(reason: "finished", previous: previous) else { Issue.record("a second end must do nothing"); return }
  }

  @Test func theEstimateNamesThePresetAndTheSize() throws {
    let (session, _) = try session()
    let estimate = session.estimate()
    #expect(estimate["preset"] as? String == "PANO Test")
    let size = estimate["size"] as? [String: Any]
    #expect(size?["width"] as? Int == 256 && size?["height"] as? Int == 256)
  }
}
