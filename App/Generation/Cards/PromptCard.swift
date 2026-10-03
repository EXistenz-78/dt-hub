import HubCore
import HubKit
import SwiftUI

/// The big prompt card, always first (spec §7). Below the prompt, the negative prompt in the
/// orange tint, only for families that use it (spec §6).
struct PromptCard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(ContributionStore.self) private var contributions: ContributionStore?

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.prompt"), systemImage: "text.cursor",
      isExpanded: controller.cards.binding("prompt")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        PromptEditor(
          text: $controller.prompt, placeholder: String(localized: "card.prompt.placeholder"),
          accessibilityLabel: String(localized: "card.prompt"), tint: DS.accent, minHeight: 140,
          isContributed: contributions?.marks[.prompt]?.isOverridden == false)
        if controller.traits(in: connection).usesNegativePrompt {
          PromptEditor(
            text: $controller.negativePrompt, placeholder: String(localized: "card.prompt.negative.placeholder"),
            accessibilityLabel: String(localized: "card.prompt.negative"), tint: DS.remove, minHeight: 60,
            isContributed: contributions?.marks[.negativePrompt]?.isOverridden == false)
          if !controller.negativePrompt.isEmpty, controller.parameters.guidanceScale <= 1 {
            Text("card.prompt.negative.noEffect")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

/// A text editor with a placeholder in the given tint and a faint tinted background.
private struct PromptEditor: View {
  @Binding var text: String
  let placeholder: String
  let accessibilityLabel: String
  let tint: Color
  let minHeight: CGFloat
  /// A plug-in wrote this prompt and it has not been changed since: teal at 30%.
  var isContributed = false

  var body: some View {
    TextEditor(text: $text)
      .font(.body)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.never)
      .padding(8)
      .frame(minHeight: minHeight)
      .background(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(isContributed ? DS.accent.opacity(0.3) : tint == DS.accent ? Color.primary.opacity(0.06) : tint.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .strokeBorder(tint == DS.accent ? Color.clear : tint.opacity(0.35), lineWidth: 1)
      )
      .overlay(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholder)
            .foregroundStyle(tint.opacity(0.75))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
      }
      .accessibilityLabel(accessibilityLabel)
  }
}
