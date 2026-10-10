import Testing

@testable import LLMChat

@Suite("Command gate")
struct CommandGateTests {
  @Test func bothCommandsOpenItAnywhereInTheText() {
    #expect(CommandGate.isOpen("ok <INVIA>"))
    #expect(CommandGate.isOpen("<SEND> go"))
    #expect(CommandGate.isOpen("make it darker <SEND> please"))
  }

  @Test func anythingElseKeepsItClosed() {
    for text in ["<invia>", "invia", "send", "<INVIA", "<Send>", "INVIA>", "applica", ""] {
      #expect(!CommandGate.isOpen(text), "\(text)")
    }
  }
}
