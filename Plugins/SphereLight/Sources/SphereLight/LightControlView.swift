import DTHubDesign
import SwiftUI

/// One light: a card of the app's look that opens and closes, with its four sliders and its colour.
struct LightControlView: View {
  @Binding var light: LightParams
  let index: Int
  @Binding var isExpanded: Bool
  let canRemove: Bool
  let onRemove: () -> Void
  let onChange: () -> Void

  var body: some View {
    DSCollapsibleCard(
      L.format(.light, index + 1), systemImage: "lightbulb", isExpanded: $isExpanded,
      trailing: {
        if canRemove {
          Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
            .buttonStyle(.plain)
            .foregroundStyle(DS.remove)
            .help(L.text(.removeLight))
        }
      }
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        sliderRow(L.text(.rotation), value: $light.rotationDeg, range: -180...180, format: "%.0f°")
        sliderRow(L.text(.elevation), value: $light.elevationDeg, range: -90...90, format: "%.0f°")
        sliderRow(L.text(.intensity), value: $light.intensity, range: 0.2...3, format: "%.2f")
        sliderRow(L.text(.hardness), value: $light.hardness, range: 0...1, format: "%.2f")
        HStack {
          Text(L.text(.color)).font(.subheadline.weight(.semibold))
          Spacer()
          ColorPicker("", selection: $light.color, supportsOpacity: false)
            .labelsHidden()
            .onChange(of: light.color) { _, _ in onChange() }
        }
      }
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold))
        Spacer()
        Text(String(format: format, value.wrappedValue)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      Slider(value: value, in: range)
        .controlSize(.small)
        .tint(DS.accent)
        .onChange(of: value.wrappedValue) { _, _ in onChange() }
    }
  }
}
