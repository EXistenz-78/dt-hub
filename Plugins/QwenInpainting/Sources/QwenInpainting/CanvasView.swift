import DTHubDesign
import SwiftUI

extension MarkColor {
  var swatch: Color {
    let (r, g, b) = rgb
    return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
  }
}

/// The start image with the marks over it. Drawing is a drag: rectangle, oval and arrow from corner to corner, the brush by
/// hand. The coordinates leave here as fractions of the image, limited to 0…1.
struct CanvasView: View {
  @ObservedObject var state: InpaintingState
  @State private var image: CGImage?
  @State private var imageWidth: Double = 1
  @State private var loadedPath: String?
  @State private var dragStart: CGPoint?
  @State private var dragPoints: [CGPoint] = []
  @State private var lastScreen: CGPoint?
  @State private var moved: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let area = proxy.size
      ZStack {
        RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
        if let image, state.startImagePath != nil {
          let shown = fitted(imageSize: CGSize(width: image.width, height: image.height), in: area)
          ZStack {
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
            Canvas { context, size in
              for mark in state.session.marks + (state.live.map { [$0] } ?? []) {
                let g = MarkGeometry.paths(for: mark, in: size, imageWidth: imageWidth)
                let color = mark.color.swatch
                context.stroke(
                  Path(g.stroke), with: .color(color),
                  style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round, lineJoin: .round))
                if let fill = g.fill { context.fill(Path(fill), with: .color(color)) }
              }
            }
            .allowsHitTesting(false)
          }
          .frame(width: shown.width, height: shown.height)
          .contentShape(Rectangle())
          .gesture(drawing(in: shown))
        } else {
          Text(L.text(.noImage)).foregroundStyle(.secondary).padding()
        }
      }
      .frame(width: area.width, height: area.height)
      .task(id: state.startImagePath) { await load() }
    }
  }

  private func fitted(imageSize: CGSize, in area: CGSize) -> CGSize {
    let scale = min((area.width - 12) / imageSize.width, (area.height - 12) / imageSize.height)
    return CGSize(width: max(1, imageSize.width * scale), height: max(1, imageSize.height * scale))
  }

  private func load() async {
    guard let path = state.startImagePath else {
      image = nil
      loadedPath = nil
      return
    }
    guard path != loadedPath else { return }
    let loaded = await Task.detached { Rasterizer.orientedImage(at: path, maxSide: 2048) }.value
    let size = Rasterizer.imageSize(at: path)
    image = loaded
    imageWidth = Double(size?.width ?? CGFloat(loaded?.width ?? 1))
    loadedPath = path
  }

  private func fraction(_ point: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: min(max(point.x / size.width, 0), 1), y: min(max(point.y / size.height, 0), 1))
  }

  private func drawing(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let now = fraction(value.location, in: size)
        let tool = state.session.tool
        if dragStart == nil {
          dragStart = fraction(value.startLocation, in: size)
          dragPoints = [dragStart!]
          lastScreen = value.startLocation
          moved = 0
        }
        moved = max(moved, hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y))
        if tool == .sketch {
          if let last = lastScreen, hypot(value.location.x - last.x, value.location.y - last.y) >= 1,
            dragPoints.count < Mark.maxPoints
          {
            dragPoints.append(now)
            lastScreen = value.location
          }
        } else {
          dragPoints = [dragStart ?? now, now]
        }
        state.live = mark(from: dragPoints)
      }
      .onEnded { _ in
        defer {
          dragStart = nil
          dragPoints = []
          lastScreen = nil
          state.live = nil
        }
        // A press that hardly moves makes nothing.
        guard moved >= 3, let mark = mark(from: dragPoints) else { return }
        state.add(mark)
      }
  }

  private func mark(from points: [CGPoint]) -> Mark? {
    guard !points.isEmpty else { return nil }
    return Mark(tool: state.session.tool, color: state.session.color, width: state.session.width, points: points).clamped()
  }
}
