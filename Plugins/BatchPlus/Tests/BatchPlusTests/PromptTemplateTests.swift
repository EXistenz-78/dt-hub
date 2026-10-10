import Testing

@testable import BatchPlus

@Suite("Prompt template")
struct PromptTemplateTests {
  func prompts(_ text: String, shuffle: Bool = false, seed: UInt64 = 1) -> [String] {
    PromptTemplate.prompts(from: text, shuffle: shuffle, seed: seed)
  }

  @Test func termsOnSeparateLinesAreOneListOfPrompts() {
    #expect(prompts("<testo1>\n<testo2>\n<testo3>") == ["testo1", "testo2", "testo3"])
    #expect(PromptTemplate.lists("<testo1>\n<testo2>\n<testo3>") == [["testo1", "testo2", "testo3"]])
  }

  @Test func twoListsInASentenceAreUsedInOrderNotCombined() {
    let text = "Foto di un <cane|gatto|scoiattolo> che <corre|salta|si rotola> su un prato"
    #expect(
      prompts(text) == [
        "Foto di un cane che corre su un prato", "Foto di un gatto che salta su un prato",
        "Foto di un scoiattolo che si rotola su un prato",
      ])
  }

  @Test func theFourDelimiterPairsAreTerms() {
    // <…> alone, <…|, |…|, |…>
    #expect(PromptTemplate.lists("<a>") == [["a"]])
    #expect(PromptTemplate.lists("<a|b>") == [["a", "b"]])
    #expect(PromptTemplate.lists("<a|b|c|d>") == [["a", "b", "c", "d"]])
  }

  @Test func aShorterListKeepsItsLastTermWithoutShuffle() {
    let text = "Foto di un <cane|gatto|scoiattolo> che <corre|salta|si rotola|vola> su un prato"
    let result = prompts(text)
    #expect(result.count == 4)
    #expect(result[3] == "Foto di un scoiattolo che vola su un prato")
    #expect(result[2] == "Foto di un scoiattolo che si rotola su un prato")
  }

  @Test func aLoneGreaterThanOrLessThanIsPlainText() {
    #expect(prompts("a > b <x|y>") == ["a > b x", "a > b y"])
    #expect(prompts("<a < b|c>") == ["a < b", "c"])
    // No `><` as a way to chain terms: it is two lists that touch, which join like blank space does.
    #expect(PromptTemplate.lists("<a><b>") == [["a", "b"]])
  }

  @Test func anUnclosedListIsPlainText() {
    #expect(prompts("foto <cane|gatto") == ["foto <cane|gatto"])
    #expect(PromptTemplate.lists("foto <cane|gatto").isEmpty)
  }

  @Test func textWithoutListsIsOnePassSoItCannotBeSent() {
    #expect(PromptTemplate.passCount("just a sentence") == 1)
    #expect(PromptTemplate.passCount("") == 1)
    #expect(PromptTemplate.passCount("<a|b|c>") == 3)
  }

  @Test func termsAreTrimmedAndAnEmptyTermIsAllowed() {
    #expect(prompts("un < cane | gatto >!") == ["un cane!", "un gatto!"])
    #expect(prompts("foto <con cappello||senza>") == ["foto con cappello", "foto", "foto senza"])
  }

  @Test func shuffleMixesEachListOnItsOwnAndIsRepeatableWithTheSeed() {
    let text = "<a|b|c|d> <1|2|3|4>"
    // Two lists separated only by blank space are ONE list: use text in between to have two lists.
    let two = "<a|b|c|d> e <1|2|3|4>"
    let first = prompts(two, shuffle: true, seed: 7)
    #expect(first == prompts(two, shuffle: true, seed: 7))
    #expect(first != prompts(two, shuffle: false))
    #expect(Set(first.map { $0.split(separator: " ")[0] }) == ["a", "b", "c", "d"])
    #expect(Set(first.map { $0.split(separator: " ")[2] }) == ["1", "2", "3", "4"])
    _ = text
  }

  @Test func withShuffleAShorterListGoesOnInAFreshRandomOrder() {
    let text = "<a|b|c|d|e|f> x <1|2>"
    let result = prompts(text, shuffle: true, seed: 3)
    #expect(result.count == 6)
    let numbers = result.map { String($0.split(separator: " ").last!) }
    #expect(Set(numbers) == ["1", "2"])
    #expect(numbers.filter { $0 == "1" }.count == 3)  // each pass of the short list is used the same number of times
  }
}
