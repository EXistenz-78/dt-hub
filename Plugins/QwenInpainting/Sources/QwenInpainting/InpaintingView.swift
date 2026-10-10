import DTHubDesign
import SwiftUI

/// The tab: the bar of tools and colours, the canvas with the cards of text beside it, and the row that sends.
struct InpaintingView: View {
  @ObservedObject var state: InpaintingState
  let send: () -> Void
  @State private var confirmingClear = false

  var body: some View {
    VStack(spacing: DS.rowGap) {
      bar
      HStack(alignment: .top, spacing: DS.rowGap) {
        CanvasView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
        cards.frame(width: 340)
      }
      sendRow
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .confirmationDialog(L.text(.clearConfirm), isPresented: $confirmingClear, titleVisibility: .visible) {
      Button(L.text(.clearAll), role: .destructive) { state.clearAll() }
      Button(L.text(.cancel), role: .cancel) {}
    }
  }

  // MARK: Bar

  private var bar: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        ForEach(MarkTool.allCases, id: \.self) { tool in toolButton(tool) }
        Divider().frame(height: 24)
        ForEach(MarkColor.allCases, id: \.self) { color in colorDot(color) }
        Divider().frame(height: 24)
        Button { confirmingClear = true } label: { Image(systemName: "trash").foregroundStyle(DS.remove) }
          .buttonStyle(.plain).help(L.text(.clearAll)).accessibilityLabel(L.text(.clearAll))
          .disabled(state.session.marks.isEmpty)
        Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }
          .buttonStyle(.plain).help(L.text(.undo)).accessibilityLabel(L.text(.undo)).disabled(!state.canUndo)
        Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }
          .buttonStyle(.plain).help(L.text(.redo)).accessibilityLabel(L.text(.redo)).disabled(!state.canRedo)
        Spacer(minLength: 0)
      }
      HStack(spacing: DS.controlGap) {
        Text(L.text(.width)).foregroundStyle(.secondary)
        Slider(value: $state.session.width, in: Mark.widthRange, step: 1).frame(maxWidth: 260)
        Text("\(Int(state.session.width)) px").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
      }
    }
    .disabled(state.startImagePath == nil)
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .dsPanel()
  }

  private func toolButton(_ tool: MarkTool) -> some View {
    let (icon, label): (String, String) =
      switch tool {
      case .sketch: ("paintbrush.pointed", L.text(.toolSketch))
      case .box: ("rectangle", L.text(.toolBox))
      case .circle: ("oval", L.text(.toolCircle))
      case .arrow: ("arrow.up.right", L.text(.toolArrow))
      }
    let selected = state.session.tool == tool
    return Button { state.session.tool = tool } label: {
      Image(systemName: icon)
        .frame(width: 30, height: 30)
        .background(Circle().fill(selected ? DS.accent.opacity(0.3) : Color.clear))
    }
    .buttonStyle(.plain).help(label).accessibilityLabel(label)
  }

  private func colorDot(_ color: MarkColor) -> some View {
    let names: [MarkColor: L.Key] = [
      .yellow: .cYellow, .red: .cRed, .blue: .cBlue, .cyan: .cCyan, .magenta: .cMagenta, .green: .cGreen,
      .purple: .cPurple, .white: .cWhite, .black: .cBlack,
    ]
    let label = L.text(names[color] ?? .cRed)
    return Button { state.session.color = color } label: {
      Circle().fill(color.swatch).frame(width: 20, height: 20)
        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
        .padding(3)
        .overlay(Circle().stroke(state.session.color == color ? DS.accent : Color.clear, lineWidth: 2))
    }
    .buttonStyle(.plain).help(label).accessibilityLabel(label)
  }

  // MARK: Cards

  private var cards: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ForEach(state.cards, id: \.key) { card in
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              Circle().fill(card.key.color.swatch).frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
              Text(Cards.title(card.key, count: card.count)).font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            TextField(
              L.text(.cardPlaceholder),
              text: Binding(get: { state.session.texts[card.key.rawValue] ?? "" }, set: { state.setText($0, for: card.key) }),
              axis: .vertical
            )
            .lineLimit(2...6)
            .textFieldStyle(.plain)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
          }
        }
      }
      .padding(DS.panelPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxHeight: .infinity)
    .dsPanel()
  }

  // MARK: Send

  @ViewBuilder private var sendRow: some View {
    if !state.active {
      Text(L.text(.notActive)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.panelPadding).dsPanel()
    } else {
      VStack(alignment: .leading, spacing: DS.controlGap) {
        DSGroupHeader(title: L.text(.previewTitle))
        Text(verbatim: state.composedPrompt.isEmpty ? L.text(.previewEmpty) : state.composedPrompt)
          .font(.caption).foregroundStyle(state.composedPrompt.isEmpty ? .secondary : .primary)
          .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: DS.controlGap) {
          if let model = state.enhancer {
            Toggle(L.format(.usePE, model.name), isOn: $state.session.usePE).toggleStyle(DSCheckboxToggleStyle())
          }
          Spacer(minLength: DS.controlGap)
          Button(action: send) {
            if state.isSending { ProgressView().controlSize(.small) } else { Text(L.text(.send)) }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(!state.canSend)
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(state.statusIsError ? Color.red : Color.secondary)
        }
      }
      .padding(DS.panelPadding)
      .dsPanel()
    }
  }
}
