import DTHubDesign
import SwiftUI

/// La card Moodboard: la tela dell'immagine mostrata, con `‹` `›` per passare alle altre.
struct MoodboardCard: View {
  @ObservedObject var state: EditState

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.grid.2x2", title: L.text(.moodboardTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let ref = state.currentReference {
          HStack(spacing: 8) {
            navButton("chevron.left", help: L.text(.previousImage, italian: state.italian), enabled: state.document.referenceIndex > 0) {
              state.showReference(by: -1)
            }
            ImageStage(
              geometry: state.referenceGeometry(of: ref), imagePath: ref.path, items: state.referenceItems,
              selectedElement: state.selected, badge: ref.number + 1, caption: "ref_image_\(ref.number)",
              accessibilityName: ref.fileName, onDraw: { state.drawOnReference($0) }, onChange: { state.setBox($1, itemID: $0) },
              onSelect: { state.selectItem($0) })
            navButton(
              "chevron.right", help: L.text(.nextImage, italian: state.italian),
              enabled: state.document.referenceIndex < state.refs.count - 1
            ) { state.showReference(by: 1) }
          }
          HStack {
            Text(ref.fileName).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Text(L.format(.imageCounter, state.document.referenceIndex + 1, state.refs.count, italian: state.italian))
              .font(.caption).foregroundStyle(.secondary).monospacedDigit()
          }
          Text(L.text(.drawOnReferenceHint, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        } else {
          Text(L.text(.emptyMoodboard, italian: state.italian)).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private func navButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
        .background(Circle().fill(Color.primary.opacity(0.10)))
    }
    .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3).help(help)
  }
}

/// La card dell'immagine di partenza: il canvas di uscita con l'immagine come in Control.
struct StartImageCard: View {
  @ObservedObject var state: EditState

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "photo", title: L.text(.startImageTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let start = state.startImage {
          ImageStage(
            geometry: state.startGeometry, imagePath: start.path, items: state.canvasItems, arrows: state.arrows,
            selectedElement: state.selected, badge: RefNumbering.startImageNumber + 1, caption: "ref_image_0",
            accessibilityName: start.lastPathComponent, onDraw: { state.drawOnCanvas($0) },
            onChange: { state.setBox($1, itemID: $0) }, onSelect: { state.selectItem($0) })
          HStack {
            if let size = state.generationSize {
              Text(L.format(.generationCanvas, Int(size.width), Int(size.height), italian: state.italian))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
          }
          Text(L.text(.drawOnCanvasHint, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
          if let note = state.windowNote { Text(note).font(.caption).foregroundStyle(DS.remove) }
        } else {
          Text(L.text(.needsStartImage, italian: state.italian)).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }
}
