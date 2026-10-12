import Foundation

/// What the "Create pipeline" window holds (`2026-10-12-pipeline-di-preset-utente-design.md` §6): the rows that are
/// ticked, in the order they were ticked, and the text of their Scale and Strength fields.
public struct PipelineDraft: Equatable, Sendable {
  public enum Row: Hashable, Sendable {
    /// "Current settings": Generation and Control as they are when the pipeline runs.
    case current
    case preset(String)
  }

  public enum Strength: Equatable, Sendable {
    case automatic
    case value(Double)
    case invalid
  }

  public var name = ""
  public var chain = true
  /// The ticked rows: the passes, in order.
  public private(set) var order: [Row] = []
  /// The text of the Scale fields; a row that is not here shows "1".
  public var scaleText: [Row: String] = [:]
  /// The text of the Strength fields (a percentage); a row that is not here is empty: automatic.
  public var strengthText: [Row: String] = [:]

  public init() {}

  /// Ticks a row, which becomes the last pass, or takes its tick away: the passes after it move up.
  public mutating func toggle(_ row: Row) {
    if let index = order.firstIndex(of: row) { order.remove(at: index) } else { order.append(row) }
  }

  /// The number of the pass (from 1); nil for a row that is not ticked.
  public func number(of row: Row) -> Int? { order.firstIndex(of: row).map { $0 + 1 } }

  /// The first pass has the tab's size: only the passes after it have a scale.
  public func editsScale(_ row: Row) -> Bool { (number(of: row) ?? 0) > 1 }

  /// The first pass and "Current settings" follow the Control tab.
  public func editsStrength(_ row: Row) -> Bool { editsScale(row) && row != .current }

  /// A scale within 0.25…4, written with a comma or a point; nil for anything else.
  public static func scale(_ text: String) -> Double? {
    guard let number = number(text), UserPipeline.scaleRange.contains(number) else { return nil }
    return number
  }

  /// A percentage within 0…100 as 0…1; an empty field is the automatic strength.
  public static func strength(_ text: String) -> Strength {
    if text.trimmingCharacters(in: .whitespaces).isEmpty { return .automatic }
    guard let number = number(text), (0...100).contains(number) else { return .invalid }
    return .value(number / 100)
  }

  /// True for a row whose scale is not used.
  public func isScaleValid(_ row: Row) -> Bool { !editsScale(row) || Self.scale(scaleText[row] ?? "1") != nil }

  /// True for a row whose strength is not used.
  public func isStrengthValid(_ row: Row) -> Bool {
    !editsStrength(row) || Self.strength(strengthText[row] ?? "") != .invalid
  }

  public var hasValidName: Bool { NamedJSONFolder.isValidName(name) }

  /// A name the file system takes, at least two passes, and every value that is used valid.
  public var canSave: Bool { hasValidName && pipeline != nil }

  /// The pipeline to save; nil with fewer than two passes or a value that is not valid.
  public var pipeline: UserPipeline? {
    guard order.count >= 2, order.allSatisfy({ isScaleValid($0) && isStrengthValid($0) }) else { return nil }
    let steps = order.map { row -> UserPipeline.Step in
      var preset: String?
      if case .preset(let name) = row { preset = name }
      var strength: Double?
      if editsStrength(row), case .value(let value) = Self.strength(strengthText[row] ?? "") { strength = value }
      return UserPipeline.Step(
        preset: preset, scale: editsScale(row) ? Self.scale(scaleText[row] ?? "1") ?? 1 : 1, strength: strength)
    }
    return UserPipeline(chain: chain, steps: steps)
  }

  /// Digits with at most one comma or point: what a person types, not everything `Double` reads ("nan", "0x10").
  private static func number(_ raw: String) -> Double? {
    let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
    else { return nil }
    return Double(text)
  }
}
