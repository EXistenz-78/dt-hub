import DTHubDesign
import SwiftUI

/// Il canvas: un rettangolo con le proporzioni della Generazione e i box degli elementi. Si trascina sul vuoto per fare un box, un
/// box per spostarlo, l'angolo di quello selezionato per ridimensionarlo; un clic sull'etichetta apre il menu dei cinque tipi.
struct MossCanvasCard: View {
  @ObservedObject var state: MossState

  /// L'altezza massima della tela: sotto servono gli elementi (il tab è alto circa 650 punti).
  static let maxHeight: CGFloat = 240

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "rectangle.dashed", title: L.text(.canvas, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let size = state.generationSize {
          Text("\(L.text(.generation, italian: state.italian)): \(size.width) × \(size.height)")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        if let notice = state.sizeNotice {
          HStack(alignment: .top, spacing: 8) {
            Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { state.dismissSizeNotice() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).font(.caption)
          }
        }
        // Lo spazio è esattamente la tela: le proporzioni della Generazione, alta al più `maxHeight`.
        Color.clear
          .aspectRatio(state.canvasAspect, contentMode: .fit)
          .overlay {
            GeometryReader { proxy in
              CanvasStage(
                state: state,
                geometry: CanvasGeometry(size: proxy.size, pixels: state.generationSize ?? PixelSize(width: 1024, height: 1024))
              )
              .frame(width: proxy.size.width, height: proxy.size.height)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }
}

/// La superficie di disegno e il suo unico gesto, che decide cosa fa dove comincia (`CanvasGeometry.begin`).
private struct CanvasStage: View {
  @ObservedObject var state: MossState
  let geometry: CanvasGeometry
  @State private var drag: CanvasDrag?

  /// I box come sono disegnati adesso: quello che si sposta o ridimensiona mostra dove andrà a finire.
  private var shown: [(item: CanvasItem, rect: CGRect)] {
    state.canvasItems.map { item in
      guard let drag, let area = geometry.preview(of: drag) else { return (item, geometry.rect(of: item.box)) }
      switch drag.mode {
      case .move(let id, _), .resize(let id, _, _):
        return id == item.id ? (item, geometry.rect(of: area)) : (item, geometry.rect(of: item.box))
      default:
        return (item, geometry.rect(of: item.box))
      }
    }
  }

  var body: some View {
    let boxes = shown
    // Il box selezionato è disegnato per ultimo, sopra gli altri, come lo tratta il hit test.
    let ordered = boxes.filter { $0.item.id != state.selectedItem } + boxes.filter { $0.item.id == state.selectedItem }
    ZStack(alignment: .topLeading) {
      Rectangle().fill(Color.primary.opacity(0.06))
      gridLines
      ForEach(ordered, id: \.item.id) { entry in box(entry.item, entry.rect) }
      if let drag, drag.mode == .draw, let area = geometry.preview(of: drag) {
        let rect = geometry.rect(of: area)
        Rectangle().fill(Color.white.opacity(0.08))
          .overlay(Rectangle().strokeBorder(Color.primary, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
          .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
      }
      origin
      ForEach(ordered, id: \.item.id) { entry in tag(entry.item, entry.rect) }
      if let id = state.typeMenuItem, let entry = ordered.first(where: { $0.item.id == id }) { typeMenu(entry.item, entry.rect) }
    }
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18)))
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          if drag == nil {
            let mode = geometry.begin(at: value.startLocation, items: state.canvasItems, selected: state.selectedItem)
            drag = CanvasDrag(mode: mode, start: value.startLocation, current: value.location)
          } else {
            drag?.current = value.location
          }
        }
        .onEnded { value in
          guard var finished = drag else { return }
          finished.current = value.location
          drag = nil
          state.canvasEnd(finished, geometry: geometry)
        }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L.text(.canvas, italian: state.italian))
  }

  private var gridLines: some View {
    Path { path in
      for step in 1..<10 {
        let x = geometry.size.width * CGFloat(step) / 10, y = geometry.size.height * CGFloat(step) / 10
        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
      }
    }
    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
  }

  /// Il centro della tela: l'origine delle coordinate che partono con «Invia».
  private var origin: some View {
    Circle().fill(Color.orange).frame(width: 8, height: 8)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2).allowsHitTesting(false)
  }

  private func box(_ item: CanvasItem, _ rect: CGRect) -> some View {
    let selected = item.id == state.selectedItem, color = MossPalette.color(for: item.label)
    return Rectangle().fill(color.opacity(0.14))
      .overlay(Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
      .overlay(Rectangle().strokeBorder(Color.primary, lineWidth: selected ? 2 : 0).padding(-2))
      .overlay { if selected { handles(rect) } }
      .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
  }

  /// I quattro angoli del box selezionato, nelle coordinate del box stesso.
  private func handles(_ rect: CGRect) -> some View {
    ZStack {
      ForEach(CanvasCorner.allCases, id: \.self) { corner in
        let point = geometry.handlePoint(corner, of: CGRect(origin: .zero, size: rect.size))
        RoundedRectangle(cornerRadius: 3).fill(Color.primary).frame(width: 10, height: 10).position(x: point.x, y: point.y)
      }
    }
  }

  private func tag(_ item: CanvasItem, _ rect: CGRect) -> some View {
    let place = geometry.tagRect(for: item, boxRect: rect)
    return Text(item.tag + " ▾").font(.system(size: 10, design: .monospaced).weight(.semibold))
      .foregroundStyle(Color.black.opacity(0.85))
      .frame(width: place.width, height: place.height)
      .background(RoundedRectangle(cornerRadius: 4).fill(MossPalette.color(for: item.label)))
      .offset(x: place.minX, y: place.minY)
      .allowsHitTesting(false)
  }

  /// Il menu dei cinque tipi, sotto l'etichetta del riquadro (dentro la tela).
  private func typeMenu(_ item: CanvasItem, _ rect: CGRect) -> some View {
    let place = geometry.tagRect(for: item, boxRect: rect)
    return VStack(alignment: .leading, spacing: 2) {
      ForEach(MossLabel.allCases, id: \.self) { label in
        Button { state.chooseLabel(label, for: item.id) } label: {
          HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(MossPalette.color(for: label)).frame(width: 10, height: 10)
            Text(L.name(of: label, italian: state.italian)).font(.caption)
            Spacer(minLength: 8)
            Text(label.rawValue).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(RoundedRectangle(cornerRadius: 6).fill(label == item.label ? Color.primary.opacity(0.12) : .clear))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4).frame(width: 170)
    .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.18)))
    .offset(x: min(place.minX, max(0, geometry.size.width - 170)), y: min(place.maxY + 2, max(0, geometry.size.height - 124)))
  }
}
