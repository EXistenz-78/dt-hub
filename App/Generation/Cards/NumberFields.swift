import HubKit
import SwiftUI

/// A whole number you can type or step. The whole text is read on every keystroke
/// (`NumberText`: out of range → nearest bound), so a RUN started mid-edit uses what is typed.
/// When editing ends the value is corrected (`commit`, e.g. snapping to 64) and shown again;
/// text that is not a number goes back to the value. Arrows beside it step by `step`.
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
          if let number = NumberText.int(text, in: range), number != value { value = number }
        }
        .onSubmit(finish)
        .onChange(of: focused) { if !focused { finish() } }
      Stepper(value: $value, in: range, step: step) { EmptyView() }
        .labelsHidden()
        .accessibilityLabel(label)
    }
    .onAppear { text = String(value) }
    // Also while focused, when the change did not come from the text (arrows, ratio lock).
    .onChange(of: value) {
      if !focused || NumberText.int(text, in: range) != value { text = String(value) }
    }
  }

  private func finish() {
    let typed = NumberText.int(text, in: range) ?? value
    value = commit(min(max(typed, range.lowerBound), range.upperBound))
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
  /// The user's own limits (LoRA Advisor): the arrows never go beyond them, but a value typed beyond them (still in
  /// `range`) is kept and the field gets an orange border.
  var limits: ClosedRange<Double>?

  @State private var text = ""
  @FocusState private var focused: Bool

  private var outsideLimits: Bool {
    guard let limits else { return false }
    return value < limits.lowerBound || value > limits.upperBound
  }

  var body: some View {
    HStack(spacing: 4) {
      TextField(label, text: $text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: width)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.remove, lineWidth: 1.5).opacity(outsideLimits ? 1 : 0))
        .focused($focused)
        .onChange(of: text) {
          if let number = NumberText.decimal(text, in: range), number != value { value = number }
        }
        .onSubmit(finish)
        .onChange(of: focused) { if !focused { finish() } }
      if let limits {
        Stepper {
          EmptyView()
        } onIncrement: {
          // From beyond the top the arrow does not move; from below it stops at the top.
          if value < limits.upperBound { value = Self.rounded(min(value + step, limits.upperBound), step: step) }
        } onDecrement: {
          if value > limits.lowerBound { value = Self.rounded(max(value - step, limits.lowerBound), step: step) }
        }
        .labelsHidden()
        .accessibilityLabel(label)
      } else {
        Stepper(value: $value, in: range, step: step) { EmptyView() }
          .labelsHidden()
          .accessibilityLabel(label)
      }
    }
    .onAppear { text = formatted(value) }
    .onChange(of: value) {
      if !focused || NumberText.decimal(text, in: range) != value { text = formatted(value) }
    }
  }

  private func finish() {
    value = NumberText.decimal(text, in: range) ?? min(max(value, range.lowerBound), range.upperBound)
    text = formatted(value)
  }

  /// A step off the limit keeps the grid of `step`: 0.05 steps do not drift.
  private static func rounded(_ number: Double, step: Double) -> Double { (number / step).rounded() * step }

  private func formatted(_ number: Double) -> String {
    number.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never))
  }
}
