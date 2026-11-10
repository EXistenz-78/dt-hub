import DTHubDesign
import SwiftUI

/// The orange cross at the right of a card title: empties the card.
struct ClearButton: View {
  let help: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(DS.remove)
    }
    .buttonStyle(.plain)
    .padding(.trailing, DS.panelPadding)
    .help(help)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
  }
}
