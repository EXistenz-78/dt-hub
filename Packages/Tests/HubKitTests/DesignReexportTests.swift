import SwiftUI
import Testing

import HubKit  // only HubKit: the design system must still come with it

@Suite("Design system re-export")
struct DesignReexportTests {
  @Test func hubKitStillGivesTheWholeDesignSystem() {
    #expect(DS.panelRadius == 19)
    #expect(DS.pillHeight == 40)
    _ = DSPillButtonStyle(prominent: true)
    _ = DSCheckboxToggleStyle()
    _ = DSGlassCircleButtonStyle()
    _ = DSGroupHeader(title: "x")
    _ = DSStatusDot(status: .connected)  // the one component that stayed in HubKit
  }
}
