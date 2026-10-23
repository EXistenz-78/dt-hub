import Testing

@testable import PromptMasterMOSS

struct LanguageTests {
  @Test func italianTextIsRecognized() {
    #expect(MossLanguage.looksItalian("Una ragazza regge un ombrello tradizionale bianco, sullo sfondo si vede una lanterna"))
    #expect(MossLanguage.looksItalian("una antica lanterna di pietra ricoperta di muschio, con dentro una fiamma accesa"))
  }

  @Test func englishTextIsNot() {
    #expect(!MossLanguage.looksItalian("A girl holds a traditional white umbrella and a lantern in the background"))
    #expect(!MossLanguage.looksItalian("Red umbrella, wet pavement"))
    #expect(!MossLanguage.looksItalian("A rainy street at night."))
  }

  @Test func shortOrEmptyTextIsNotFlagged() {
    #expect(!MossLanguage.looksItalian(""))
    #expect(!MossLanguage.looksItalian("la lanterna"))
  }
}
