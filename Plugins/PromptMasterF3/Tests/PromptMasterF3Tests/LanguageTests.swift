import Testing

@testable import PromptMasterF3

struct LanguageTests {
  @Test func italianTextIsRecognized() {
    #expect(F3Language.looksItalian("Una ragazza <girl_1> regge un ombrello <umbrella> tradizionale bianco, sullo sfondo si vede una lanterna"))
    #expect(F3Language.looksItalian("una antica lanterna di pietra ricoperta di muschio, con dentro una fiamma accesa"))
  }

  @Test func englishTextIsNot() {
    #expect(!F3Language.looksItalian("A girl <girl_1> holds a traditional white umbrella <umbrella> and a lantern in the background"))
    #expect(!F3Language.looksItalian("Red umbrella, wet pavement"))
    #expect(!F3Language.looksItalian("A rainy street at night."))
  }

  @Test func shortOrEmptyTextIsNotFlagged() {
    #expect(!F3Language.looksItalian(""))
    #expect(!F3Language.looksItalian("la lanterna"))
  }

  @Test func idsDoNotCount() {
    #expect(!F3Language.looksItalian("<la_la_la> <di_che> <un_una>"))
  }
}
