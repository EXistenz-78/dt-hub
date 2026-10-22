import AppKit
import DTHubDesign
import SwiftUI

/// Una tela con l'immagine di sfondo e i riquadri sopra (spec §5). Vale per tutte e due: la tela del Moodboard (l'immagine
/// intera) e quella dell'immagine di partenza (il canvas di uscita, con l'immagine posizionata come in Control).
struct ImageStage: View {
  let geometry: StageGeometry
  let imagePath: String?
  let items: [StageItem]
  var arrows: [StageArrow] = []
  let selectedElement: String?
  /// Il numero che l'immagine ha nel prompt (lo stesso badge del tab Control) e il suo nome (`ref_image_N`).
  let badge: Int
  let caption: String
  let accessibilityName: String
  /// L'altezza massima della tela.
  var maxHeight: CGFloat = 300
  let onDraw: (BBox) -> Void
  let onChange: (String, BBox) -> Void
  /// Un riquadro cliccato (`nil`: il vuoto).
  let onSelect: (String?) -> Void

  var body: some View {
    Color.clear
      .aspectRatio(geometry.canvasAspect, contentMode: .fit)
      .overlay {
        GeometryReader { proxy in
          StageCanvas(
            geometry: geometry, canvas: CanvasGeometry(size: proxy.size), imagePath: imagePath, items: items, arrows: arrows,
            selectedElement: selectedElement, badge: badge, caption: caption, onDraw: onDraw, onChange: onChange, onSelect: onSelect
          )
          .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: maxHeight)
      .accessibilityLabel(accessibilityName)
  }
}

private struct StageCanvas: View {
  let geometry: StageGeometry
  let canvas: CanvasGeometry
  let imagePath: String?
  let items: [StageItem]
  let arrows: [StageArrow]
  let selectedElement: String?
  let badge: Int
  let caption: String
  let onDraw: (BBox) -> Void
  let onChange: (String, BBox) -> Void
  let onSelect: (String?) -> Void
  @State private var drag: CanvasDrag?
  @State private var image: NSImage?

  private var canvasItems: [CanvasItem] {
    items.map { CanvasItem(id: $0.id, colorIndex: $0.colorIndex, box: $0.box, caption: $0.caption) }
  }

  /// Per gli angoli e le etichette conta il riquadro dell'elemento selezionato (il primo di questa tela).
  private var selectedItemID: String? { items.first { $0.elementID == selectedElement }?.id }

  private func rect(of item: StageItem) -> CGRect {
    guard let drag, let area = canvas.preview(of: drag) else { return canvas.rect(of: item.box) }
    switch drag.mode {
    case .move(let id, _), .resize(let id, _, _): return id == item.id ? canvas.rect(of: area) : canvas.rect(of: item.box)
    default: return canvas.rect(of: item.box)
    }
  }

  var body: some View {
    let size = canvas.size
    let frame = geometry.imageFrame
    ZStack(alignment: .topLeading) {
      Rectangle().fill(Color.primary.opacity(0.08))
      if let image {
        Image(nsImage: image).resizable()
          .frame(width: frame.width * size.width, height: frame.height * size.height)
          .offset(x: frame.minX * size.width, y: frame.minY * size.height)
      }
      ForEach(arrows.indices, id: \.self) { index in arrow(arrows[index]) }
      ForEach(items.filter { $0.elementID != selectedElement } + items.filter { $0.elementID == selectedElement }) { item in
        box(item, rect(of: item))
      }
      if let drag, case .draw = drag.mode, let area = canvas.preview(of: drag) {
        let r = canvas.rect(of: area)
        Rectangle().strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5, 3])).frame(width: r.width, height: r.height)
          .offset(x: r.minX, y: r.minY)
      }
      ForEach(items) { item in tag(item, rect(of: item)) }
      HStack(spacing: 6) {
        Text(caption).font(.system(size: 11, design: .monospaced).weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 1)
          .background(Capsule().fill(Color.black.opacity(0.55))).foregroundStyle(.white)
        Spacer(minLength: 0)
        Text(verbatim: "\(badge)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
          .frame(minWidth: 22, minHeight: 22).background(Circle().fill(DS.accent))
          .overlay(Circle().strokeBorder(Color.black.opacity(0.35)))
      }
      .padding(5).frame(width: size.width, height: size.height, alignment: .bottom).allowsHitTesting(false)
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.25)))
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          if drag == nil {
            let mode = canvas.begin(at: value.startLocation, items: canvasItems, selected: selectedItemID)
            drag = CanvasDrag(mode: mode, start: value.startLocation, current: value.location)
          } else {
            drag?.current = value.location
          }
        }
        .onEnded { value in
          guard var finished = drag else { return }
          finished.current = value.location
          drag = nil
          end(finished)
        }
    )
    .task(id: imagePath) {
      guard let path = imagePath else { return image = nil }
      image = await Task.detached { ImageLoader.thumbnail(path: path) }.value
    }
  }

  private func end(_ drag: CanvasDrag) {
    switch drag.mode {
    case .none: break
    case .draw:
      if drag.moved { if let box = canvas.result(of: drag) { onDraw(box) } } else { onSelect(nil) }
    case .tag(let id): if !drag.moved { onSelect(id) }
    case .move(let id, _), .resize(let id, _, _):
      onSelect(id)
      if drag.moved, let box = canvas.result(of: drag) { onChange(id, box) }
    }
  }

  private func box(_ item: StageItem, _ rect: CGRect) -> some View {
    let selected = item.elementID == selectedElement
    let color = EditPalette.color(index: item.colorIndex)
    return Rectangle().fill(color.opacity(item.dashed ? 0.06 : 0.16))
      .overlay(
        Rectangle().strokeBorder(color, style: item.dashed ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 2))
      )
      .overlay {
        if item.crossed {
          GeometryReader { proxy in
            Path { path in
              path.move(to: .zero)
              path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
              path.move(to: CGPoint(x: proxy.size.width, y: 0))
              path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
            }
            .stroke(color, lineWidth: 2)
          }
        }
      }
      .overlay(Rectangle().strokeBorder(Color.white, lineWidth: selected ? 2 : 0).padding(-2))
      .overlay { if selected { handles(rect) } }
      .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
  }

  private func handles(_ rect: CGRect) -> some View {
    ZStack {
      ForEach(CanvasCorner.allCases, id: \.self) { corner in
        let point = canvas.handlePoint(corner, of: CGRect(origin: .zero, size: rect.size))
        RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 10, height: 10).position(x: point.x, y: point.y)
      }
    }
  }

  private func tag(_ item: StageItem, _ rect: CGRect) -> some View {
    let ci = CanvasItem(id: item.id, colorIndex: item.colorIndex, box: item.box, caption: item.caption)
    let place = canvas.tagRect(for: ci, boxRect: rect)
    return Text(item.caption).font(.system(size: 10, design: .monospaced).weight(.semibold))
      .foregroundStyle(Color.black.opacity(0.85)).lineLimit(1)
      .frame(width: place.width, height: place.height)
      .background(RoundedRectangle(cornerRadius: 4).fill(EditPalette.color(index: item.colorIndex)))
      .offset(x: place.minX, y: place.minY).allowsHitTesting(false)
  }

  private func arrow(_ arrow: StageArrow) -> some View {
    let a = canvas.rect(of: arrow.from), b = canvas.rect(of: arrow.to)
    let start = CGPoint(x: a.midX, y: a.midY), end = CGPoint(x: b.midX, y: b.midY)
    let angle = atan2(end.y - start.y, end.x - start.x), head: CGFloat = 10
    return Path { path in
      path.move(to: start)
      path.addLine(to: end)
      path.move(to: end)
      path.addLine(to: CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6)))
      path.move(to: end)
      path.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6)))
    }
    .stroke(EditPalette.color(index: arrow.colorIndex), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    .allowsHitTesting(false)
  }
}
