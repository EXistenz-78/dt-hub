import HubKit
import SwiftUI

/// The big prompt card, always first (spec §7).
struct PromptCard: View {
  @Bindable var controller: GenerationController

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.prompt"), systemImage: "text.cursor",
      isExpanded: controller.cards.binding("prompt")
    ) {
      TextEditor(text: $controller.prompt)
        .font(.body)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .padding(8)
        .frame(minHeight: 140)
        .background(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        )
        .overlay(alignment: .topLeading) {
          if controller.prompt.isEmpty {
            Text("card.prompt.placeholder")
              .foregroundStyle(DS.accent.opacity(0.75))
              .padding(.horizontal, 13)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
        .accessibilityLabel(String(localized: "card.prompt"))
    }
  }
}
