import DTHubPluginKit
import Foundation
import Testing

@testable import CharacterSheet

@MainActor
@Suite("CharacterSheetPlugin")
struct CharacterSheetPluginTests {
  /// Its settings (kind of sheet, switch, model) are preferences for every project, so the `project` message is
  /// understood and needs nothing: an `unsupported` answer would make the app tell the user the plug-in does not keep
  /// its state per project.
  @Test func theProjectMessageIsUnderstood() async {
    let message = Data(#"{"type":"project","name":"A","folder":"/tmp/x","adoptLegacy":false}"#.utf8)
    let answer = await CharacterSheetPlugin().handle(message)
    #expect(DTHubMessage.type(of: answer ?? DTHubMessage.bare("ok")) != "unsupported")
  }

  @Test func anUnknownMessageIsStillUnsupported() async {
    let answer = await CharacterSheetPlugin().handle(Data(#"{"type":"nonsense"}"#.utf8))
    #expect(DTHubMessage.type(of: answer ?? Data()) == "unsupported")
  }
}
