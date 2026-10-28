import Testing

@testable import Panorama360F3

struct PFSizesTests {
  @Test func largerFromTheStandardIs2176x1088() {
    #expect(PFSizes.larger(PFSizes.standard) == PFSize(width: 2176, height: 1088))
  }

  @Test func smallerFromTheStandardIs1920x960() {
    #expect(PFSizes.smaller(PFSizes.standard) == PFSize(width: 1920, height: 960))
  }

  @Test func largerAtTheMaximumIsNil() {
    #expect(PFSizes.larger(PFSizes.maximum) == nil)
  }

  @Test func smallerAtTheMinimumIsNil() {
    #expect(PFSizes.smaller(PFSizes.minimum) == nil)
  }

  @Test func everyStepIsTwoToOneAndAMultipleOf64() {
    var size = PFSizes.minimum
    var count = 1
    while let next = PFSizes.larger(size) {
      #expect(next.width == 2 * next.height)
      #expect(next.height % 64 == 0)
      size = next
      count += 1
    }
    #expect(size == PFSizes.maximum)
    #expect(count == 57)
  }

  @Test func isValidRejectsOffTheLadderAndAcceptsTheLadder() {
    #expect(!PFSizes.isValid(PFSize(width: 2048, height: 1000)))
    #expect(!PFSizes.isValid(PFSize(width: 2000, height: 1000)))
    #expect(!PFSizes.isValid(PFSize(width: 512, height: 256)))
    #expect(PFSizes.isValid(PFSizes.standard) && PFSizes.isValid(PFSizes.minimum) && PFSizes.isValid(PFSizes.maximum))
  }
}
