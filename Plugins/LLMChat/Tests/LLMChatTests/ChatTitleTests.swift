import Foundation
import Testing

@testable import LLMChat

@Suite("Chat title")
struct ChatTitleTests {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let utc = TimeZone(identifier: "UTC")!

  @Test func theFirstLineWithoutTheCommand() {
    #expect(ChatTitle.make(from: "Rendi il prompt più cupo <FALLO>\naltro", date: date, italian: true) == "Rendi il prompt più cupo")
    #expect(ChatTitle.make(from: "<DO IT> make it darker", date: date, italian: false) == "make it darker")
  }

  @Test func aLongTitleIsCutAt40WithAnEllipsis() {
    let title = ChatTitle.make(from: String(repeating: "a", count: 60), date: date, italian: false)
    #expect(title == String(repeating: "a", count: 40) + "…")
    #expect(ChatTitle.make(from: String(repeating: "b", count: 40), date: date, italian: false).count == 40)
  }

  @Test func aMessageWithOnlyTheCommandGetsTheDate() {
    let it = ChatTitle.make(from: "<FALLO>", date: date, italian: true, timeZone: utc)
    let en = ChatTitle.make(from: "<DO IT>", date: date, italian: false, timeZone: utc)
    #expect(it.hasPrefix("Chat del ") && en.hasPrefix("Chat of "))
    #expect(it != en)
  }
}
