import DTHubDesign
import SwiftUI

/// La card di destra in basso: i livelli, dallo sfondo (L1) al primo piano, una scheda ciascuno (quella nuova si apre da sola),
/// e in fondo Importa, Annulla, Svuota, Scrivi con LLM, Invia.
struct MingLayersCard: View {
  @ObservedObject var state: MingState
  let send: () -> Void
  let write: () -> Void
  let importPrompt: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.3.layers.3d", title: L.text(.layersTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(spacing: 8) {
              if state.document.layers.isEmpty {
                Text(L.text(.noLayers, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              ForEach(Array(state.document.layers.enumerated()), id: \.element.id) { index, layer in
                LayerCard(state: state, layer: layer, index: index).id(layer.id)
              }
            }
          }
          .scrollIndicators(.hidden)
          .onChange(of: state.selectedLayer) { _, id in
            if let id { withAnimation { reader.scrollTo(id, anchor: .center) } }
          }
        }
        .frame(minHeight: 140, maxHeight: .infinity)
        buttons
        ForEach(state.statusLines, id: \.self) { line in
          Text(line).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private func iconPill(_ help: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: icon) }
      .buttonStyle(DSPillButtonStyle())
      .disabled(disabled)
      .help(help)
      .accessibilityLabel(help)
  }

  private func pill(_ title: String, _ icon: String, prominent: Bool = false, disabled: Bool, busy: Bool = false, busyTitle: String = "",
                    action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: DS.pillIconGap) {
        if busy {
          ProgressView().controlSize(.small)
          Text(busyTitle)
        } else {
          Image(systemName: icon)
          Text(title)
        }
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: prominent))
    .disabled(disabled)
  }

  private var buttons: some View {
    HStack(spacing: DS.controlGap) {
      iconPill(L.text(.importFromGeneration, italian: state.italian), "square.and.arrow.down",
        disabled: state.isWriting || state.isSending || (state.generationPrompt ?? "").isEmpty, action: importPrompt)
      iconPill(L.text(.undo, italian: state.italian), "arrow.uturn.backward", disabled: !state.canUndo) { state.undo() }
      iconPill(L.text(.clearAll, italian: state.italian), "trash", disabled: state.isWriting || state.document.layers.isEmpty) {
        state.clearAll()
      }
      Spacer(minLength: 0)
      pill(L.text(.writeWithLLM, italian: state.italian), "sparkles", disabled: !state.canWrite, busy: state.isWriting,
        busyTitle: L.text(.writing, italian: state.italian), action: write)
      pill(L.text(.send, italian: state.italian), "paperplane", prominent: true, disabled: !state.canSend, busy: state.isSending,
        busyTitle: L.text(.sending, italian: state.italian), action: send)
    }
  }
}

private struct LayerCard: View {
  @ObservedObject var state: MingState
  let layer: MingLayer
  let index: Int

  private var excerpt: String {
    let source = layer.kind == .text && !layer.text.isEmpty ? "“\(layer.text)”" : layer.description
    let line = source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    if line.isEmpty { return L.text(.noDescription, italian: state.italian) }
    return line.count > 46 ? String(line.prefix(46)) + "…" : line
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(layer.expanded ? 90 : 0))
        Text("L\(index + 1) · \(L.name(of: layer.kind, italian: state.italian).lowercased())")
          .font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.black.opacity(0.85))
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(RoundedRectangle(cornerRadius: 5).fill(MingPalette.color(for: layer.kind)))
        Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        iconButton("arrow.up", help: L.text(.moveUp, italian: state.italian), enabled: index > 0) { state.moveLayer(layer.id, by: -1) }
        iconButton("arrow.down", help: L.text(.moveDown, italian: state.italian), enabled: index < state.document.layers.count - 1) {
          state.moveLayer(layer.id, by: 1)
        }
        Button { state.removeLayer(layer.id) } label: { Image(systemName: "xmark").font(.caption) }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeLayer, italian: state.italian))
      }
      .padding(10).contentShape(Rectangle())
      .onTapGesture {
        state.update(layer: layer.id) { $0.expanded.toggle() }
        state.selectedLayer = layer.id
      }
      if layer.expanded { details.padding([.horizontal, .bottom], 10) }
    }
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    .overlay(
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .strokeBorder(DS.accent, lineWidth: state.selectedLayer == layer.id ? 2 : 0))
  }

  private func iconButton(_ name: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: name).font(.caption) }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!enabled).help(help)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("", selection: Binding(get: { layer.kind }, set: { state.setKind($0, for: layer.id) })) {
        ForEach(MingKind.allCases, id: \.self) { Text(L.name(of: $0, italian: state.italian)).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden()
      if layer.kind == .text {
        HStack {
          FieldLabel(text: L.text(.textLabel, italian: state.italian))
          Text(L.text(.verbatim, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        }
        NoteField(
          text: state.layerBinding(layer.id, \.text, fallback: layer.text),
          placeholder: L.text(.textPlaceholder, italian: state.italian), minHeight: 44, maxHeight: 90)
        FieldLabel(text: L.text(.lookLabel, italian: state.italian))
        NoteField(
          text: state.layerBinding(layer.id, \.description, fallback: layer.description),
          placeholder: L.text(.lookPlaceholder, italian: state.italian), minHeight: 56, maxHeight: 110)
      } else {
        FieldLabel(text: L.text(.descriptionLabel, italian: state.italian))
        NoteField(
          text: state.layerBinding(layer.id, \.description, fallback: layer.description),
          placeholder: L.text(.objectPlaceholder, italian: state.italian), minHeight: 56, maxHeight: 140)
      }
      FieldLabel(text: L.text(.relationLabel, italian: state.italian))
      TextField(L.text(.relationPlaceholder, italian: state.italian), text: state.layerBinding(layer.id, \.relation, fallback: layer.relation))
        .textFieldStyle(.roundedBorder)
      FieldLabel(text: L.text(.position, italian: state.italian))
      PositionField(state: state, layer: layer)
      FieldLabel(text: L.text(.colorsLabel, italian: state.italian))
      PaletteRow(
        colors: layer.colors, limit: Palette.elementLimit,
        removeHelp: L.text(.removeColor, italian: state.italian), addHelp: L.text(.addColor, italian: state.italian),
        set: { state.setColor($1, at: $0, in: layer.id) }, remove: { state.removeColor(at: $0, from: layer.id) },
        add: { state.addColor(to: layer.id) })
    }
  }
}

/// La posizione come la scrive Ming: `cx: …, cy: …, w: …, h: …`. Si tiene appena si legge; un testo illeggibile resta com'è, con
/// una riga che spiega cos'è una posizione, e il box resta quello di prima.
private struct PositionField: View {
  @ObservedObject var state: MingState
  let layer: MingLayer
  @State private var text = ""
  @FocusState private var focused: Bool

  private var canonical: String { state.positionText(of: layer.id) }
  private var isUnreadable: Bool { !text.isEmpty && MingGeometry.parse(text) == nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("cx, cy, w, h", text: $text)
        .textFieldStyle(.roundedBorder).font(.body.monospaced())
        .focused($focused)
        .onAppear { text = canonical }
        .onChange(of: text) { _, new in
          if focused { state.setPosition(new, of: layer.id) }
        }
        .onChange(of: layer.box) { _, _ in
          if !focused { text = canonical }
        }
        .onChange(of: focused) { _, isFocused in
          if !isFocused && !isUnreadable { text = canonical }
        }
        .onSubmit { if !isUnreadable { text = canonical } }
      if isUnreadable {
        Text(L.text(.positionInvalid, italian: state.italian)).font(.caption).foregroundStyle(DS.remove)
      }
    }
  }
}
