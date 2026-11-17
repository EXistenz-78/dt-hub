import Foundation
import HubKit

/// The steps, the guidance and the shift a Turbo LoRA needs. A nil field is not touched.
public struct TurboValues: Equatable, Sendable {
  public var steps: Int?
  public var guidance: Double?
  public var shift: Double?

  public init(steps: Int? = nil, guidance: Double? = nil, shift: Double? = nil) {
    self.steps = steps
    self.guidance = guidance
    self.shift = shift
  }

  /// True when no value is set: there is nothing to apply.
  public var isEmpty: Bool { steps == nil && guidance == nil && shift == nil }
}

/// The Turbo LoRAs the app activated, in order, with what they changed in the parameters, so that removing one puts
/// back what was there before. A value the user changed by hand since is never touched.
public struct TurboLoRAs: Equatable, Sendable {
  private struct Activation: Equatable, Sendable {
    var file: String
    /// The parameters before the activation (inherited from the one below when that one is removed out of order).
    var before: Snapshot
    /// What the activation really set (already inside the ranges).
    var applied: TurboValues
  }

  private struct Snapshot: Equatable, Sendable {
    var steps: Int
    var guidance: Double
    var shift: Double
  }

  private var stack: [Activation] = []

  public init() {}

  /// The files of the active Turbo LoRAs, in order of activation.
  public var files: [String] { stack.map(\.file) }

  /// What the activation of this file set, nil when it is not in the stack.
  public func applied(for file: String) -> TurboValues? {
    stack.first { $0.file == file }?.applied
  }

  /// The values the activation of this file set that the parameters still hold. Nil when the file is not chosen, not in
  /// the stack, or none of its values is current any more (a bulk assignment or a new model overwrote them).
  public func stillApplied(for file: String, in parameters: GenerationParameters) -> TurboValues? {
    guard parameters.loras.contains(where: { $0.file == file }), let applied = applied(for: file) else { return nil }
    var current = TurboValues()
    if let steps = applied.steps, parameters.steps == steps { current.steps = steps }
    if let guidance = applied.guidance, parameters.guidanceScale == guidance { current.guidance = guidance }
    if let shift = applied.shift, parameters.shift == shift { current.shift = shift }
    return current.isEmpty ? nil : current
  }

  /// Sets the values (brought into range) and remembers the parameters before. A file already in the stack, or values with
  /// nothing in them, change nothing.
  public mutating func activate(file: String, values: TurboValues, in parameters: inout GenerationParameters) {
    guard !values.isEmpty, !stack.contains(where: { $0.file == file }) else { return }
    let before = Snapshot(steps: parameters.steps, guidance: parameters.guidanceScale, shift: parameters.shift)
    var applied = TurboValues()
    if let steps = values.steps {
      let clean = Self.clamp(steps, GenerationParameters.stepsRange)
      parameters.steps = clean
      applied.steps = clean
    }
    if let guidance = values.guidance, !guidance.isNaN {
      let clean = Self.clamp(guidance, GenerationParameters.guidanceRange)
      parameters.guidanceScale = clean
      applied.guidance = clean
    }
    if let shift = values.shift, !shift.isNaN {
      let clean = Self.clamp(shift, GenerationParameters.shiftRange)
      parameters.shift = clean
      applied.shift = clean
    }
    guard !applied.isEmpty else { return }
    stack.append(Activation(file: file, before: before, applied: applied))
  }

  /// Takes the file out of the stack. If it is the last one, each value it set that is still as it left it goes back to
  /// what it was before. If another activation is above it, the parameters stay and that one inherits the "before" of the
  /// values that were its starting point.
  public mutating func deactivate(file: String, in parameters: inout GenerationParameters) {
    guard let index = stack.firstIndex(where: { $0.file == file }) else { return }
    let removed = stack[index]
    if index == stack.count - 1 {
      if let steps = removed.applied.steps, parameters.steps == steps { parameters.steps = removed.before.steps }
      if let guidance = removed.applied.guidance, parameters.guidanceScale == guidance {
        parameters.guidanceScale = removed.before.guidance
      }
      if let shift = removed.applied.shift, parameters.shift == shift { parameters.shift = removed.before.shift }
    } else {
      // The activation above inherits what its starting point was; if it does not own the parameter, it takes it over
      // (the current value is the removed one's), so removing it later restores the inherited value.
      var above = stack[index + 1]
      if let steps = removed.applied.steps, above.before.steps == steps {
        above.before.steps = removed.before.steps
        if above.applied.steps == nil { above.applied.steps = steps }
      }
      if let guidance = removed.applied.guidance, above.before.guidance == guidance {
        above.before.guidance = removed.before.guidance
        if above.applied.guidance == nil { above.applied.guidance = guidance }
      }
      if let shift = removed.applied.shift, above.before.shift == shift {
        above.before.shift = removed.before.shift
        if above.applied.shift == nil { above.applied.shift = shift }
      }
      stack[index + 1] = above
    }
    stack.remove(at: index)
  }

  /// Forgets the activations of files no longer among `files` (the parameters are not touched).
  public mutating func prune(keeping files: Set<String>) {
    stack.removeAll { !files.contains($0.file) }
  }

  private static func clamp<Value: Comparable>(_ value: Value, _ range: ClosedRange<Value>) -> Value {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
