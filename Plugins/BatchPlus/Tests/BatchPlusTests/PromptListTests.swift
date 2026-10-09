import Testing

@testable import BatchPlus

@Suite("Prompt list")
struct PromptListTests {
  @Test func eachBulletIsAnItem() {
    #expect(PromptList.items("- a\n- b") == ["a", "b"])
    #expect(PromptList.items("  • a\n\t* b\n- c") == ["a", "b", "c"])
  }

  @Test func linesWithoutABulletContinueTheItem() {
    #expect(PromptList.items("- a cat\n  on a roof\n- b") == ["a cat on a roof", "b"])
    #expect(PromptList.items("- a cat\n\n  on a roof") == ["a cat on a roof"])
  }

  @Test func emptyItemsAreDropped() {
    #expect(PromptList.items("- \n- b\n-") == ["b"])
  }

  @Test func textWithoutBulletsHasNoItems() {
    #expect(PromptList.items("just a sentence\nand another") == [])
    #expect(PromptList.items("").isEmpty)
  }

  @Test func textBeforeTheFirstBulletIsIgnored() {
    #expect(PromptList.items("intro\n- a") == ["a"])
  }
}
