import Foundation
import HubKit

/// A pipeline the user made by lining up presets (`2026-10-12-pipeline-di-preset-utente-design.md` §4). The name is
/// the name of its file.
public struct UserPipeline: Equatable, Sendable {
  public struct Step: Equatable, Sendable {
    /// The preset to run, by name; nil is "Current settings": Generation and Control as they are when it runs.
    public var preset: String?
    /// The size of the previous pass is multiplied by this (from the second pass on).
    public var scale: Double
    /// How much the start image is changed (0…1); nil is automatic, as on the Control tab.
    public var strength: Double?

    public init(preset: String?, scale: Double = 1, strength: Double? = nil) {
      self.preset = preset
      self.scale = min(max(scale, UserPipeline.scaleRange.lowerBound), UserPipeline.scaleRange.upperBound)
      self.strength = strength.map { min(1, max(0, $0)) }
    }

    /// Nil for what is not a step: not an object, or a `preset` that is neither null nor a name.
    init?(_ value: JSONValue) {
      guard case .object(let object) = value, let named = object["preset"] else { return nil }
      var preset: String?
      switch named {
      case .null: preset = nil
      case .string(let text):
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        preset = name
      default: return nil
      }
      self.init(preset: preset, scale: Self.number(object["scale"]) ?? 1, strength: Self.number(object["strength"]))
    }

    private static func number(_ value: JSONValue?) -> Double? {
      switch value {
      case .double(let number)? where number.isFinite: number
      case .int(let number)?: Double(number)
      default: nil
      }
    }
  }

  public static let scaleRange = 0.25...4.0

  /// From the second pass on, the picture a pass makes is the start image of the next one.
  public var chain: Bool
  public var steps: [Step]

  public init(chain: Bool = true, steps: [Step]) {
    self.chain = chain
    self.steps = steps
  }

  /// Lenient: a step that cannot be read is left out, a value out of its limits comes back within them. Nil when
  /// the data is not a pipeline at all, or has no step left.
  public init?(data: Data) {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let object) = root,
      case .array(let list)? = object["steps"]
    else { return nil }
    let steps = list.compactMap { Step($0) }
    guard !steps.isEmpty else { return nil }
    var chain = true
    if case .bool(let flag)? = object["chain"] { chain = flag }
    self.init(chain: chain, steps: steps)
  }

  /// The file: `{"chain": …, "steps": [{"preset": … or null, "scale": …, "strength": …}]}`.
  public func data() -> Data {
    let list: [[String: Any]] = steps.map { step in
      var object: [String: Any] = ["preset": step.preset as Any? ?? NSNull(), "scale": step.scale]
      if let strength = step.strength { object["strength"] = strength }
      return object
    }
    let root: [String: Any] = ["chain": chain, "steps": list]
    return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
  }

  /// The presets the pipeline names, once each, in the order of the passes.
  public var presetNames: [String] {
    var names: [String] = []
    for name in steps.compactMap(\.preset) where !names.contains(name) { names.append(name) }
    return names
  }

  /// The pipeline as RUN executes it. The first pass has no scale and no strength of its own (it uses the tab's
  /// size and the Control tab), and neither has a "Current settings" pass a strength.
  public func pluginPipeline(named name: String) -> PluginPipeline {
    PluginPipeline(
      name: name,
      steps: steps.enumerated().map { index, step in
        PipelineStep(
          preset: step.preset ?? "", useOutputAsStart: chain && index > 0, usesPresetModel: true,
          scale: index == 0 ? 1 : step.scale, strength: index == 0 || step.preset == nil ? nil : step.strength)
      })
  }
}
