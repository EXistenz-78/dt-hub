import AppKit
import DTHubDesign
import SwiftUI

/// A row that opens and closes: a chevron, a title, and on the right what is chosen under it.
struct DisclosureRow: View {
  let title: String
  let detail: String?
  let count: Int
  let isOpen: Bool
  let isSection: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(isOpen ? 90 : 0))
        if isSection {
          DSGroupHeader(title: title, prominent: true)
        } else {
          Text(title).font(.subheadline.weight(.semibold))
        }
        Spacer(minLength: 0)
        if let detail, !detail.isEmpty {
          Text(detail).font(.caption).foregroundStyle(DS.accent).lineLimit(1).truncationMode(.tail)
        }
        if count > 0 {
          Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(DS.accent.opacity(0.25)))
        }
      }
      .padding(.vertical, isSection ? 7 : 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A row of color swatches (a system color picker each, with a small × to take it away) and a + that adds a random one.
struct PaletteRow: View {
  let colors: [String]
  let limit: Int
  let italian: Bool
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
          .buttonStyle(.plain).offset(x: 6, y: -6).help(L.text(.removeColor, italian: italian))
        }
      }
      Button(action: add) {
        Image(systemName: "plus").frame(width: 28, height: 28)
          .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3])))
      }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(colors.count >= limit)
      .help(L.text(.addColor, italian: italian))
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

/// A multi-line text field with a placeholder, in the look of the app.
struct NoteField: View {
  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 70
  var maxHeight: CGFloat = 170

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(6)
      if text.isEmpty {
        Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
      }
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}

/// A small caption above a field.
struct FieldLabel: View {
  let text: String
  var body: some View {
    Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
  }
}
