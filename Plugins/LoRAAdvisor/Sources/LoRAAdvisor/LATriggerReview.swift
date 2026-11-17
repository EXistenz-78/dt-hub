import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// "Triggers to check · n": the trigger words the analysis found that differ from the ones of the app. Nothing is applied
/// without a click (spec §5). Shown only while there is something to check.
struct LATriggerReview: View {
  @ObservedObject var state: LAState

  var body: some View {
    let proposals = state.triggerProposals
    if !proposals.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: DS.controlGap) {
          Text(verbatim: L.text(.triggersToCheck, proposals.count, italian: state.italian))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Button(state.text(.applyAll)) { Task { await state.applyAllProposals() } }
            .buttonStyle(DSPillButtonStyle())
            .controlSize(.small)
            .disabled(!state.canSaveSettings)
        }
        ForEach(proposals, id: \.lora.file) { item in
          HStack(spacing: DS.controlGap) {
            VStack(alignment: .leading, spacing: 1) {
              Text(verbatim: item.lora.name).lineLimit(1).truncationMode(.middle)
              Text(verbatim: current(of: item.lora) + " · " + L.text(.foundTrigger, item.proposal, italian: state.italian))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(state.text(.apply)) { Task { await state.applyProposal(for: item.lora.file) } }
              .buttonStyle(DSPillButtonStyle())
              .controlSize(.small)
              .disabled(!state.canSaveSettings)
            Button(state.text(.notThisTrigger)) { state.dismissProposal(for: item.lora.file) }
              .buttonStyle(DSPillButtonStyle())
              .controlSize(.small)
          }
        }
        if let message = state.settingsMessage {
          Text(verbatim: message).font(.caption).foregroundStyle(DS.remove)
        }
      }
      .padding(8)
      .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.35)))
    }
  }


  private func current(of lora: DTHubCatalogLoRA) -> String {
    lora.trigger.isEmpty ? state.text(.noTrigger) : L.text(.trigger, lora.trigger, italian: state.italian)
  }
}
