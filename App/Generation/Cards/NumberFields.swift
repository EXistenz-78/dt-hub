import HubKit
import SwiftUI

/// A whole number you can type or step. The text is read on every keystroke and kept only
/// when it is a valid number in range; when editing ends it is corrected (`commit`, e.g.
/// snapping to 64) and shown again. Arrows beside it step by `step`.
struct IntField: View {
  let label: String
  @Binding var value: Int
  let range: ClosedRange<Int>
  var step = 1
  var width: CGFloat = 64
  var commit: (Int) -> Int = { $0 }

  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 4) {
      TextField(label, text: $text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: width)
        .focused($focused)
        .onChange(of: text) {
          if let number = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(number) {
            value = number
          }
        }
        .onSubmit(finish)
        .onChange(of: focused) { if !focused { finish() } }
      Stepper(value: $value, in: range, step: step) { EmptyView() }
        .labelsHidden()
        .accessibilityLabel(label)
    }
    .onAppear { text = String(value) }
    .onChange(of: value) { if !focused { text = String(value) } }
  }

  private func finish() {
    value = commit(min(max(value, range.lowerBound), range.upperBound))
    text = String(value)
  }
}

/// A decimal number you can type (comma or point) or step; same rules as `IntField`.
struct DecimalField: View {
  let label: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var step = 0.1
  var fractionDigits = 1
  var width: CGFloat = 64

  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 4) {
      TextField(label, text: $text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: width)
        .focused($focused)
        .onChange(of: text) {
          let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
          if let number = Double(normalized), range.contains(number) { value = number }
        }
        .onSubmit(finish)
        .onChange(of: focused) { if !focused { finish() } }
      Stepper(value: $value, in: range, step: step) { EmptyView() }
        .labelsHidden()
        .accessibilityLabel(label)
    }
    .onAppear { text = formatted(value) }
    .onChange(of: value) { if !focused { text = formatted(value) } }
  }

  private func finish() {
    value = min(max(value, range.lowerBound), range.upperBound)
    text = formatted(value)
  }

  private func formatted(_ number: Double) -> String {
    number.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never))
  }
}
