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
        enhanceRow
        PromptAssistError(assistant: controller.assistant, hiding: .noImage)
        if controller.assistant.note == .imagesNotSent {
          Text("prompt.assist.note.imagesNotSent")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  /// Enhance Prompt (the language model rewrites the prompt), its spinner, and Undo while the fields still hold the result.
  private var enhanceRow: some View {
    HStack(spacing: DS.controlGap) {
      Button {
        Task { await controller.enhancePrompt(in: connection) }
      } label: {
        Label("prompt.enhance", systemImage: "wand.and.stars")
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "prompt.enhance.help"))
      .disabled(controller.assistant.working != nil)
      if controller.assistant.working == .enhance { ProgressView().controlSize(.small) }
      Spacer(minLength: 0)
      PromptAssistUndo(controller: controller)
    }
  }
}

/// The Undo link of Enhance/Generate Prompt: shown while the fields still hold what the last operation wrote.
struct PromptAssistUndo: View {
  let controller: GenerationController

  var body: some View {
    let current = PromptPair(prompt: controller.prompt, negative: controller.negativePrompt)
    if let before = controller.assistant.undoOffer(current: current) {
      Button("prompt.undo") {
        controller.prompt = before.prompt
        controller.negativePrompt = before.negative
        controller.assistant.clearUndo()
      }
      .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
    }
  }
}

/// Why the last Enhance/Generate Prompt produced nothing. `hiding` is the failure that belongs to the other button.
struct PromptAssistError: View {
  let assistant: PromptAssistant
  let hiding: PromptAssistant.Failure

  var body: some View {
    if let failure = assistant.failure, failure != hiding {
      Text(verbatim: PromptAssistantText.message(failure))
        .font(.caption)
        .foregroundStyle(DS.remove)
        .fixedSize(horizontal: false, vertical: true)
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
