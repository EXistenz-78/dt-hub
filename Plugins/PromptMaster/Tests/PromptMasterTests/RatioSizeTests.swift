import Foundation
import Testing

@testable import PromptMaster

@Suite("From a format to a size")
struct RatioSizeTests {
  private let area = 1024 * 1024

  @Test func theSameAreaInTheSuggestedRatioInMultiplesOf64() {
    #expect(RatioSize.size(ratio: "1:1", area: area)! == (1024, 1024))
    #expect(RatioSize.size(ratio: "3:2", area: area)! == (1280, 832))
    #expect(RatioSize.size(ratio: "2:3", area: area)! == (832, 1280))
    #expect(RatioSize.size(ratio: "16:9", area: area)! == (1344, 768))
    #expect(RatioSize.size(ratio: "9:16", area: area)! == (768, 1344))
    #expect(RatioSize.size(ratio: "21:9", area: area)! == (1536, 640))
  }

  @Test func theAreaOfTheCurrentSizeIsKept() {
    #expect(RatioSize.size(ratio: "3:2", area: 512 * 512)! == (640, 448))
    #expect(RatioSize.size(ratio: "1:1", area: 1280 * 832)! == (1024, 1024))
  }

  @Test func everySideIsAMultipleOf64BetweenTheLimits() {
    for ratio in ["1:1", "3:2", "4:5", "5:4", "9:21", "3:1", "1:3", "2:1", "7:3", "18:39"] {
      let size = RatioSize.size(ratio: ratio, area: 1_000_000)!
      #expect(size.width % 64 == 0 && size.height % 64 == 0, "\(ratio)")
      #expect(RatioSize.limits.contains(size.width) && RatioSize.limits.contains(size.height), "\(ratio)")
    }
    // A very thin format is held at the limits.
    let thin = RatioSize.size(ratio: "1:100", area: area)!
    #expect(thin.height == 4096 && thin.width >= 64)
    let tiny = RatioSize.size(ratio: "1:1", area: 100)!
    #expect(tiny == (64, 64))
  }

  @Test func aFormatThatCannotBeReadGivesNothing() {
    for ratio in ["", "abc", "0:3", "3:0", "3:", ":3", "1:2:3", "-3:2", "3.5:2", "3;2", "3/2"] {
      #expect(RatioSize.size(ratio: ratio, area: area) == nil, "\(ratio)")
    }
    #expect(RatioSize.size(ratio: "3:2", area: 0) == nil)
    #expect(RatioSize.size(ratio: "3:2", area: -5) == nil)
  }

  @Test func spacesAroundTheNumbersDoNotMatter() {
    #expect(RatioSize.size(ratio: " 3 : 2 ", area: area)! == (1280, 832))
  }

  @Test func theCurrentSizeComesFromTheContextMessage() {
    let message = Data(#"{"type": "context", "family": "flux2_9b", "parameters": {"width": 1024, "height": 832, "steps": 8}}"#.utf8)
    #expect(RatioSize.currentSize(inContext: message)! == (1024, 832))
    #expect(RatioSize.currentSize(inContext: Data(#"{"type": "context"}"#.utf8)) == nil)
    #expect(RatioSize.currentSize(inContext: Data(#"{"parameters": {"width": 0, "height": 5}}"#.utf8)) == nil)
    #expect(RatioSize.currentSize(inContext: Data("nope".utf8)) == nil)
  }
}
