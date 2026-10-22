import DTHubDesign
import SwiftUI

/// Il canvas: un rettangolo con le proporzioni della Generazione e i box degli elementi. Si trascina un box per spostarlo, un
/// angolo del selezionato per ridimensionarlo; sul vuoto non si crea niente (gli elementi nascono dal testo).
struct F3CanvasCard: View {
  @ObservedObject var state: F3State

  /// L'altezza massima del canvas: sotto servono le schede degli elementi.
  static let maxHeight: CGFloat = 240

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "rectangle.dashed", title: "3 · " + L.text(.canvasTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let size = state.generationSize {
          Text("\(L.text(.generation, italian: state.italian)): \(Int(size.width)) × \(Int(size.height))")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        Color.clear
          .aspectRatio(state.canvasAspect, contentMode: .fit)
          .overlay {
            GeometryReader { proxy in
              F3CanvasStage(state: state, geometry: CanvasGeometry(size: proxy.size))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
        Text(L.text(.canvasHint, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }
}

private struct F3CanvasStage: View {
  @ObservedObject var state: F3State
  let geometry: CanvasGeometry
  @State private var drag: CanvasDrag?

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
    let ordered = boxes.filter { $0.item.id != state.selectedElement } + boxes.filter { $0.item.id == state.selectedElement }
    ZStack(alignment: .topLeading) {
      Rectangle().fill(Color.primary.opacity(0.06))
      gridLines
      ForEach(ordered, id: \.item.id) { entry in box(entry.item, entry.rect) }
      ForEach(ordered, id: \.item.id) { entry in tag(entry.item, entry.rect) }
    }
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18)))
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          if drag == nil {
            let mode = geometry.begin(at: value.startLocation, items: state.canvasItems, selected: state.selectedElement)
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
    .accessibilityLabel(L.text(.canvasTitle, italian: state.italian))
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

  private func box(_ item: CanvasItem, _ rect: CGRect) -> some View {
    let selected = item.id == state.selectedElement
    let color = F3Palette.color(index: item.colorIndex)
    return Rectangle().fill(color.opacity(0.14))
      .overlay(Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
      .overlay(Rectangle().strokeBorder(Color.primary, lineWidth: selected ? 2 : 0).padding(-2))
      .overlay { if selected { handles(rect) } }
      .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
  }

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
    return Text(item.label).font(.system(size: 10, design: .monospaced).weight(.semibold))
      .foregroundStyle(Color.black.opacity(0.85)).lineLimit(1)
      .frame(width: place.width, height: place.height)
      .background(RoundedRectangle(cornerRadius: 4).fill(F3Palette.color(index: item.colorIndex)))
      .offset(x: place.minX, y: place.minY)
      .allowsHitTesting(false)
  }
}
