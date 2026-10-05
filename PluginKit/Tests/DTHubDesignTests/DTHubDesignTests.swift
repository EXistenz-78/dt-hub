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
}
