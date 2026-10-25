import AppKit
import DTHubDesign
import SwiftUI

/// The stickers: the list (the top row is the top layer, rows can be dragged to reorder), duplicate and delete, and the numbers of the one selected.
struct PSStickerCard: View {
  @ObservedObject var state: PSState
  private static let rowPrefix = "p360-row:"

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "photo.on.rectangle", title: state.text(.stickersTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        list
        HStack(spacing: DS.controlGap) {
          iconButton("plus.square.on.square", help: state.text(.duplicate), enabled: state.selected != nil) { state.duplicateSelected() }
          iconButton("trash", help: state.text(.delete), enabled: state.selected != nil) { state.deleteSelected() }
        }
        fields
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  // MARK: List

  private var list: some View {
    VStack(spacing: 6) {
      ForEach(Array(state.doc.stickers.enumerated()).reversed(), id: \.element.id) { index, sticker in
        row(sticker, layer: index + 1)
      }
    }
  }

  private func row(_ sticker: Sticker, layer: Int) -> some View {
    let selected = sticker.id == state.doc.selectedID
    return HStack(spacing: 8) {
      thumbnail(sticker)
      Text(sticker.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
      Text(verbatim: "z\(layer)").font(.caption.monospaced()).foregroundStyle(.secondary)
      Button { state.setVisible(sticker.id, !sticker.visible) } label: {
        Image(systemName: sticker.visible ? "eye" : "eye.slash").frame(width: 24, height: 24)
      }
      .buttonStyle(.plain).help(state.text(.toggleVisible))
    }
    .padding(6)
    .opacity(sticker.visible ? 1 : 0.45)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius).fill(Color.primary.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: DS.minorRadius).stroke(selected ? DS.accent : Color.clear, lineWidth: 2))
    .contentShape(Rectangle())
    .onTapGesture { state.select(sticker.id) }
    .draggable(Self.rowPrefix + sticker.id.uuidString)
    .dropDestination(for: String.self) { items, _ in
      guard let raw = items.first, raw.hasPrefix(Self.rowPrefix), let id = UUID(uuidString: String(raw.dropFirst(Self.rowPrefix.count)))
      else { return false }
      state.moveSticker(id, inFrontOf: sticker.id)
      return true
    }
  }

  @ViewBuilder private func thumbnail(_ sticker: Sticker) -> some View {
    if let image = state.image(for: sticker) {
      Image(decorative: image, scale: 1).resizable().scaledToFill().frame(width: 46, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
    } else {
      RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.15)).frame(width: 46, height: 30)
    }
  }

  private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }
      .buttonStyle(DSGlassCircleButtonStyle()).help(help).disabled(!enabled)
  }

  // MARK: Numbers

  private var fields: some View {
    let id = state.doc.selectedID
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 8) {
      field(.yaw, id: id, \.yaw)
      field(.pitch, id: id, \.pitch)
      field(.rotation, id: id, \.rot)
      field(.fieldOfView, id: id, \.hfov)
      VStack(alignment: .leading, spacing: 3) {
        Text(state.text(.verticalFieldOfView)).font(.caption).foregroundStyle(.secondary)
        Text(verbatim: state.selected.map { String(format: "%.1f", state.verticalFOV(of: $0)) } ?? "—")
          .font(.body.monospaced()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 8).padding(.vertical, 4)
      }
      field(.opacity, id: id, \.opacity)
    }
  }

  /// A number of the selected sticker; it reads the state (never a copy), so the cursor stays where it is while it is typed into.
  private func field(_ title: L.Key, id: UUID?, _ keyPath: WritableKeyPath<Sticker, Double>) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(state.text(title)).font(.caption).foregroundStyle(.secondary)
      TextField("", value: id.map { state.binding($0, keyPath) } ?? .constant(0), format: .number.precision(.fractionLength(0...2)))
        .textFieldStyle(.roundedBorder).font(.body.monospaced()).disabled(id == nil)
    }
  }
}
