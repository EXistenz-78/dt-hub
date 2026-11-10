import AppKit
import DTHubDesign
import SwiftUI

/// A row of color swatches (a system color picker each, with a small × to take it away) and a + that adds a random one.
struct PaletteRow: View {
  let colors: [String]
  let limit: Int
  let removeHelp: String
  let addHelp: String
  let set: (Int, String) -> Void
  let remove: (Int) -> Void
  let add: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(colors.enumerated()), id: \.offset) { index, hex in
        ColorPicker(
          "",
          selection: Binding(
            get: { Color(hex: hex) ?? .gray },
            set: { if let value = $0.hexString { set(index, value) } }),
          supportsOpacity: false
        )
        .labelsHidden()
        .overlay(alignment: .topTrailing) {
          Button { remove(index) } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(DS.remove)
          }
          .buttonStyle(.plain).offset(x: 6, y: -6).help(removeHelp)
        }
      }
      Button(action: add) {
        Image(systemName: "plus").frame(width: 28, height: 28)
          .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3])))
      }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(colors.count >= limit)
      .help(addHelp)
      Spacer(minLength: 0)
      Text("\(colors.count)/\(limit)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }
    .padding(.vertical, 4)
  }
}

extension Color {
  /// A color from `#RRGGBB`.
  init?(hex: String) {
    guard let parts = Palette.components(hex) else { return nil }
    self.init(.sRGB, red: parts.red, green: parts.green, blue: parts.blue, opacity: 1)
  }

  /// `#RRGGBB` in sRGB.
  var hexString: String? {
    guard let value = NSColor(self).usingColorSpace(.sRGB) else { return nil }
    return Palette.hex(red: Double(value.redComponent), green: Double(value.greenComponent), blue: Double(value.blueComponent))
  }
}
