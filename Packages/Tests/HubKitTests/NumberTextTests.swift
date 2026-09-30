import HubKit
import Testing

struct NumberTextTests {
  @Test func aWholeNumberAboveTheRangeBecomesTheMaximum() {
    #expect(NumberText.int("200", in: 1...150) == 150)
    #expect(NumberText.int("3000", in: 64...2048) == 2048)
    #expect(NumberText.int("99999999999999999999999", in: 1...100) == 100)
  }

  @Test func aWholeNumberBelowTheRangeBecomesTheMinimum() {
    #expect(NumberText.int("5", in: 64...2048) == 64)
    #expect(NumberText.int(" 512 ", in: 64...2048) == 512)
  }

  @Test func textThatIsNotAWholeNumberIsRejected() {
    #expect(NumberText.int("", in: 1...10) == nil)
    #expect(NumberText.int("abc", in: 1...10) == nil)
    #expect(NumberText.int("1,5", in: 1...10) == nil)
  }

  @Test func decimalsAcceptCommaOrPointAndAreClamped() {
    #expect(NumberText.decimal("4,5", in: 0...50) == 4.5)
    #expect(NumberText.decimal("4.5", in: 0...50) == 4.5)
    #expect(NumberText.decimal("60", in: 0...50) == 50)
    #expect(NumberText.decimal("-1", in: 0...50) == 0)
    #expect(NumberText.decimal("x", in: 0...50) == nil)
  }
}
