import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// "Advise": a request (the current prompt, until the user writes another) and the LoRAs the language model picks for
/// it among those of the current model's family.
struct LAAdviceCard: View {
  @ObservedObject var state: LAState

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: state.text(.adviceTitle), prominent: true)
      TextEditor(text: Binding(get: { state.request }, set: { state.editRequest($0) }))
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(4)
        .frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .accessibilityLabel(state.text(.request))
      HStack(spacing: DS.controlGap) {
        Text(verbatim: L.text(.onlyFamily, state.familyLabel))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if state.requestEditedByUser {
          Button {
            state.resetRequest()
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }
          .buttonStyle(.plain)
          .help(state.text(.resetRequest))
          .accessibilityLabel(state.text(.resetRequest))
        }
        Spacer(minLength: 0)
        Button {
          Task { await state.advise() }
        } label: {
          if state.isAdvising { ProgressView().controlSize(.small) } else { Text(verbatim: state.text(.advise)) }
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(blocker != nil || state.isBusy || !state.active)
      }
      if let blocker {
        Text(verbatim: blocker).font(.caption).foregroundStyle(.secondary)
      }
      if let message = state.adviceMessage {
        Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: DS.controlGap) {
          ForEach(state.suggestions, id: \.file) { suggestion in
            if let lora = state.catalog.first(where: { $0.file == suggestion.file }) {
              card(suggestion, lora)
            }
          }
          if state.suggestions.count > 1 {
            HStack {
              Spacer(minLength: 0)
              Button(state.text(.addAll)) { Task { await state.addAll() } }
                .buttonStyle(DSPillButtonStyle())
                .disabled(!state.active)
            }
          }
        }
      }
      if let status = state.status {
        Text(verbatim: status).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(DS.panelPadding)
    .frame(width: LAView.sideWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .dsPanel()
  }

  /// Why "Advise" cannot work now.
  private var blocker: String? {
    if !state.hasLanguageModel { return state.text(.needsLLM) }
    if state.blocker == nil, state.candidates().isEmpty { return state.text(.noLoRAsForFamily) }
    return state.blocker == nil ? nil : ""
  }

  private func card(_ suggestion: LAAdvice.Suggestion, _ lora: DTHubCatalogLoRA) -> some View {
    let onTab = state.isOnTab(lora.file)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: DS.controlGap) {
        LAThumbnailView(url: state.thumbnailURL(for: lora.file), side: 44)
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: lora.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
          if onTab { LATag(text: state.text(.onTab)) }
        }
      }
      if !suggestion.why.isEmpty {
        Text(verbatim: suggestion.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: DS.controlGap) {
        TextField(
          state.text(.weight),
          value: Binding(get: { suggestion.weight }, set: { state.setWeight($0, forSuggestion: lora.file) }),
          format: .number.precision(.fractionLength(0...2))
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 60)
        Spacer(minLength: 0)
        Button(state.text(onTab ? .updateWeight : .add)) { Task { await state.add(lora, weight: suggestion.weight) } }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.active)
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius).fill(.background.opacity(0.35)))
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(.separator))
  }
}
