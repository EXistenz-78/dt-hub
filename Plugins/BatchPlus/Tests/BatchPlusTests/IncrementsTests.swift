import Testing

@testable import BatchPlus

@Suite("Increments")
struct IncrementsTests {
  @Test func commaAndPointAreBothDecimalSeparators() {
    #expect(IncrementParse.parse("0,5", integer: false) == .success(0.5))
    #expect(IncrementParse.parse("0.5", integer: false) == .success(0.5))
    #expect(IncrementParse.parse("  1,25 ", integer: false) == .success(1.25))
  }

  @Test func theSignIsRead() {
    #expect(IncrementParse.parse("-2", integer: true) == .success(-2))
    #expect(IncrementParse.parse("+2", integer: true) == .success(2))
    #expect(IncrementParse.parse("\u{2212}0,5", integer: false) == .success(-0.5))
  }

  @Test func wholeNumbersRefuseDecimals() {
    #expect(IncrementParse.parse("1.5", integer: true) == .failure(.notAnInteger))
    #expect(IncrementParse.parse("2,0", integer: true) == .success(2))
  }

  @Test func emptyAndZeroMeanNoVariation() {
    #expect(IncrementParse.parse("", integer: false) == .success(nil))
    #expect(IncrementParse.parse("  ", integer: false) == .success(nil))
    #expect(IncrementParse.parse("0", integer: true) == .success(nil))
    #expect(IncrementParse.parse("0,0", integer: false) == .success(nil))
  }

  @Test func notANumberIsAnError() {
    #expect(IncrementParse.parse("abc", integer: false) == .failure(.notANumber))
    #expect(IncrementParse.parse("1,2,3", integer: false) == .failure(.notANumber))
    #expect(IncrementParse.parse("inf", integer: false) == .failure(.notANumber))
  }

  @Test func valuesGrowByTheIncrementStartingAtTheBase() {
    #expect(BatchPlusMath.values(base: 10, increment: 10, count: 3) == [10, 20, 30])
    #expect(BatchPlusMath.values(base: 3, increment: -0.5, count: 3) == [3, 2.5, 2])
    #expect(BatchPlusMath.values(base: 0.4, increment: 0.2, count: 3) == [0.4, 0.6, 0.8])
    #expect(BatchPlusMath.values(base: 5, increment: 1, count: 0).isEmpty)
  }
}
