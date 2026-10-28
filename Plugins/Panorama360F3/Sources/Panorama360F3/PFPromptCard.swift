import DTHubDesign
import SwiftUI

/// What the buttons do; the plug-in fills it, a test leaves it empty.
struct PFViewActions {
  var improve: () -> Void = {}
  var send: () -> Void = {}
  var fixSeam: () -> Void = {}
  static var none: PFViewActions { PFViewActions() }
}

/// The description of the place, the size, «Improve prompt» and «Send to Generation».
struct PFPromptCard: View {
  @ObservedObject var state: PFState
  let actions: PFViewActions

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
        if let message = state.error ?? state.notice {
          let isError = state.error != nil
          Text(message).font(.callout).foregroundStyle(isError ? DS.remove : Color.primary).frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.boxPadding)
            .background(RoundedRectangle(cornerRadius: DS.minorRadius).fill((isError ? DS.remove : DS.accent).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: DS.minorRadius).stroke(isError ? DS.remove : DS.accent, lineWidth: 1))
        }
        sendRow
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  /// The size selector (always 2:1) and «Send to Generation».
  private var sendRow: some View {
    HStack(spacing: DS.controlGap) {
      Text(verbatim: "\(state.doc.size.width) × \(state.doc.size.height)").font(.body.monospaced())
      VStack(spacing: 2) {
        Button { state.sizeUp() } label: { Image(systemName: "chevron.up") }
          .buttonStyle(.plain).help(state.text(.sizeUp)).disabled(PFSizes.larger(state.doc.size) == nil)
        Button { state.sizeDown() } label: { Image(systemName: "chevron.down") }
          .buttonStyle(.plain).help(state.text(.sizeDown)).disabled(PFSizes.smaller(state.doc.size) == nil)
      }
      Spacer(minLength: 0)
      Button { actions.send() } label: { Text(state.text(.send)).lineLimit(1) }
        .buttonStyle(DSPillButtonStyle()).disabled(!state.canSend)
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
