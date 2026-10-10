import Testing

@testable import AIAssistant

@Suite("Command gate")
struct CommandGateTests {
  @Test func bothCommandsOpenItAnywhereInTheText() {
    #expect(CommandGate.isOpen("ok <FALLO>"))
    #expect(CommandGate.isOpen("<DO IT> go"))
    #expect(CommandGate.isOpen("make it darker <DO IT> please"))
  }

  @Test func anythingElseKeepsItClosed() {
    for text in ["<fallo>", "fallo", "do it", "<FALLO", "<Do It>", "DO IT>", "<INVIA>", "<SEND>", "applica", ""] {
      #expect(!CommandGate.isOpen(text), "\(text)")
    }
  }
}
