import SwiftUI
import Testing

@testable import DTHubDesign

@Suite("DTHubDesign")
struct DTHubDesignTests {
  @Test func theTokensAreTheOnesOfTheApp() {
    #expect(DS.panelRadius == 19)
    #expect(DS.pillHeight == 40)
    #expect(DS.groupGap == 18)
  }

  @Test func theComponentsCanBeMade() {
    _ = DSPillButtonStyle(prominent: true)
    _ = DSCheckboxToggleStyle()
    _ = DSGlassCircleButtonStyle()
    _ = DSGroupHeader(title: "x", prominent: true)
    _ = DSPanelHeader(icon: "lightbulb", title: "x")
  }

  @Test func aCollapsibleCardCanCarryAnAccessoryNextToItsTitle() {
    // With and without: the existing calls (no accessory) keep compiling.
    _ = DSCollapsibleCard("x", isExpanded: .constant(true), trailing: { Image(systemName: "minus.circle") }) { Text("y") }
    _ = DSCollapsibleCard("x", systemImage: "lightbulb", tint: DS.remove, isExpanded: .constant(false)) { Text("y") }
  }
}
