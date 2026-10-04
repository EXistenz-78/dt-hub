import SwiftUI

/// One light: a block that opens and closes, with its five controls.
struct LightControlView: View {
  @Binding var light: LightParams
  let index: Int
  @Binding var isExpanded: Bool
  let canRemove: Bool
  let onRemove: () -> Void
  let onChange: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if isExpanded {
        VStack(alignment: .leading, spacing: 10) {
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
  }

  private var header: some View {
    HStack {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
          Text(L.format(.light, index + 1)).font(.headline)
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if canRemove {
        Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
          .buttonStyle(.plain)
          .foregroundStyle(.orange)
          .help(L.text(.removeLight))
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
      Slider(value: value, in: range).controlSize(.small)
        .onChange(of: value.wrappedValue) { _, _ in onChange() }
    }
  }
}
