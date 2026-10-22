import Testing

@testable import Flux3Editing

struct AutocompleteTests {
  /// Types `typed` at `caret` (a character offset) in `text`; what the editor holds after that, and where its caret is.
  private func type(_ typed: Character, in text: String, at caret: Int) -> (old: String, new: String, caret: Int) {
    var characters = Array(text)
    characters.insert(typed, at: caret)
    return (text, String(characters), caret + 1)
  }

  private func result(_ typed: Character, in text: String, at caret: Int) -> (text: String, caret: Int)? {
    let edit = type(typed, in: text, at: caret)
    return ProseAutocomplete.complete(old: edit.old, new: edit.new, caret: edit.caret).map { ($0.text, $0.caret) }
  }

  @Test func anEAfterAnOpeningAngleBecomesElUnderscore() {
    let done = result("e", in: "Add <", at: 5)
    #expect(done?.text == "Add <el_" && done?.caret == 8)
  }

  @Test func anRAfterAnOpeningAngleBecomesRefImageUnderscore() {
    let done = result("r", in: "From <", at: 6)
    #expect(done?.text == "From <ref_image_" && done?.caret == 16)
  }

  @Test func theLettersAreCaseInsensitive() {
    #expect(result("E", in: "<", at: 1)?.text == "<el_")
    #expect(result("R", in: "<", at: 1)?.text == "<ref_image_")
  }

  @Test func aDigitAfterElUnderscoreClosesTheTagAndStaysInsideIt() {
    let done = result("3", in: "Add <el_ now", at: 8)
    #expect(done?.text == "Add <el_3> now" && done?.caret == 9)
  }

  @Test func aDigitAfterRefImageUnderscoreClosesTheTag() {
    let done = result("2", in: "from <ref_image_", at: 16)
    #expect(done?.text == "from <ref_image_2>" && done?.caret == 17)
  }

  @Test func aSecondDigitExtendsTheNumberBeforeTheClosingAngle() {
    // After "<el_1>" with the caret before ">" a new digit makes <el_12>, with no second ">".
    #expect(result("2", in: "<el_1>", at: 5) == nil)
  }

  @Test func nothingHappensElsewhere() {
    #expect(result("e", in: "Add the", at: 7) == nil)  // no "<" before
    #expect(result("x", in: "Add <", at: 5) == nil)  // another letter
    #expect(result("3", in: "Add 2", at: 5) == nil)  // a digit not after <el_ or <ref_image_
    #expect(result("3", in: "<el_x", at: 5) == nil)
  }

  @Test func onlyASingleTypedCharacterIsCompleted() {
    #expect(ProseAutocomplete.complete(old: "Add ", new: "Add <e", caret: 6) == nil)  // a paste of two characters
    #expect(ProseAutocomplete.complete(old: "Add <e", new: "Add <", caret: 5) == nil)  // a deletion
    #expect(ProseAutocomplete.complete(old: "same", new: "same", caret: 4) == nil)
  }

  @Test func itWorksInTheMiddleOfTheText() {
    let done = result("e", in: "Move <, then add", at: 6)
    #expect(done?.text == "Move <el_, then add" && done?.caret == 9)
  }
}
