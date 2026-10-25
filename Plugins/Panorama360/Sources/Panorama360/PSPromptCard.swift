import DTHubDesign
import SwiftUI

/// What the buttons do; the plug-in fills it, a test leaves it empty.
struct PSViewActions {
  var improve: () -> Void = {}
  var send: () -> Void = {}
  static var none: PSViewActions { PSViewActions() }
}

/// The description of the place, «Improve prompt» and what goes with it.
struct PSPromptCard: View {
  @ObservedObject var state: PSState
  let actions: PSViewActions

  private var wordCount: Int { state.doc.description.split(whereSeparator: \.isWhitespace).count }

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: state.text(.promptTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        description
        HStack(spacing: DS.controlGap) {
          Button { actions.improve() } label: { Text(state.isImproving ? state.text(.improving) : state.text(.improve)) }
            .buttonStyle(DSPillButtonStyle()).disabled(state.isImproving)
          Button { state.undoImprove() } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.undo)).disabled(state.previousDescription == nil)
          Spacer(minLength: 0)
          Text(state.text(.words, wordCount)).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        if let message = state.error ?? state.warning ?? state.notice {
          Text(message).font(.callout).foregroundStyle(DS.remove).frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.boxPadding)
            .background(RoundedRectangle(cornerRadius: DS.minorRadius).fill(DS.remove.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: DS.minorRadius).stroke(DS.remove, lineWidth: 1))
        }
        sendRow
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  /// Normal / Fast and «Send to Generation».
  private var sendRow: some View {
    HStack(spacing: DS.controlGap) {
      Picker("", selection: Binding(get: { state.doc.mode }, set: { value in state.mutate { $0.mode = value } })) {
        Text(state.text(.modeNormal)).tag(PanoMode.normal)
        Text(state.text(.modeFast)).tag(PanoMode.fast)
      }
      .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 200)
      Spacer(minLength: 0)
      Button { actions.send() } label: { Text(state.text(.send)).lineLimit(1) }
        .buttonStyle(DSPillButtonStyle()).disabled(state.isSending || !state.doc.stickers.contains(where: \.visible))
    }
  }

  /// A multi-line field that reads the state, never a copy, so the cursor stays where it is while typing.
  private var description: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: Binding(get: { state.doc.description }, set: { value in state.mutate { $0.description = value } }))
        .font(.body).scrollContentBackground(.hidden).padding(6)
      if state.doc.description.isEmpty {
        Text(state.text(.promptPlaceholder)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
      }
    }
    .frame(minHeight: 120)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius).fill(Color.primary.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(Color.primary.opacity(0.18)))
  }
}
