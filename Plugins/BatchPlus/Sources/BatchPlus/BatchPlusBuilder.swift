import Foundation

/// The values of the Generation tab the series starts from (the plug-in reads them from the app's `context`).
struct BatchBase: Equatable {
  struct LoRA: Equatable {
    var file: String
    var weight: Double
  }

  var steps: Int?
  var guidanceScale: Double?
  var shift: Double?
  var cfgZeroInitSteps: Int?
  var seed: UInt32?
  var loras: [LoRA] = []

  func value(of key: BatchPlusKey) -> Double? {
    switch key {
    case .steps: steps.map(Double.init)
    case .guidanceScale: guidanceScale
    case .shift: shift
    case .cfgZeroInitSteps: cfgZeroInitSteps.map(Double.init)
    case .seed: seed.map(Double.init)
    }
  }
}

/// A series of the Parameters mode: which values grow, by how much, and for how many passes.
struct ParameterBatch: Equatable {
  var increments: [BatchPlusKey: Double] = [:]
  /// By LoRA file.
  var loraIncrements: [String: Double] = [:]
  var count = 3
  var fixedSeed = true
}

/// The `pipeline` the plug-in sends to DT Hub (`contribute`). Pure, so it can be tested. Never a preset, never a size.
enum BatchPlusBuilder {
  static let prefix = "Batch plus"

  /// The label of each varying value, for the pipeline's name and the passes' titles.
  static func label(_ key: BatchPlusKey, italian: Bool) -> String {
    switch key {
    case .steps: L.text(.steps, italian: italian)
    case .guidanceScale: L.text(.guidance, italian: italian)
    case .shift: L.text(.shift, italian: italian)
    case .cfgZeroInitSteps: L.text(.cfgZero, italian: italian)
    case .seed: L.text(.seed, italian: italian)
    }
  }

  /// The columns that vary: the numeric parameters in the order of the tab, then the LoRAs in the order of the card.
  /// Identifiers: the key's raw value, or `lora:<file>`.
  static func varying(_ batch: ParameterBatch, base: BatchBase) -> [String] {
    var result = BatchPlusKey.allCases.filter { batch.increments[$0] != nil }.map(\.rawValue)
    result += base.loras.filter { batch.loraIncrements[$0.file] != nil }.map { "lora:\($0.file)" }
    return result
  }

  private static func stem(_ file: String) -> String { (file as NSString).deletingPathExtension }

  static func columnLabel(_ id: String, italian: Bool) -> String {
    if id.hasPrefix("lora:") { return stem(String(id.dropFirst(5))) }
    return BatchPlusKey(rawValue: id).map { label($0, italian: italian) } ?? id
  }

  /// The value of every varying column at each pass, from the first one (the current values).
  static func preview(_ batch: ParameterBatch, from base: BatchBase) -> [[String: Double]] {
    let columns = varying(batch, base: base)
    return (0..<max(batch.count, 0)).map { k in
      var row: [String: Double] = [:]
      for id in columns {
        if id.hasPrefix("lora:") {
          let file = String(id.dropFirst(5))
          let start = base.loras.first { $0.file == file }?.weight ?? 0
          row[id] = BatchPlusMath.values(base: start, increment: batch.loraIncrements[file] ?? 0, count: k + 1)[k]
        } else if let key = BatchPlusKey(rawValue: id) {
          row[id] = BatchPlusMath.values(base: base.value(of: key) ?? 0, increment: batch.increments[key] ?? 0, count: k + 1)[k]
        }
      }
      return row
    }
  }

  private static func number(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
  }

  private static func clampedSeed(_ value: Double) -> Int { Int(min(max(value, 0), 4_294_967_295)) }

  static func pipeline(_ batch: ParameterBatch, from base: BatchBase, italian: Bool = L.systemIsItalian) -> [String: Any] {
    let columns = varying(batch, base: base)
    let rows = preview(batch, from: base)
    let seedVaries = batch.increments[.seed] != nil
    var steps: [[String: Any]] = []
    for row in rows {
      var fields: [String: Any] = [:]
      var loras: [[String: Any]] = []
      var parts: [String] = []
      for id in columns {
        guard let value = row[id] else { continue }
        parts.append("\(columnLabel(id, italian: italian)) \(number(value))")
        if id.hasPrefix("lora:") {
          loras.append(["file": String(id.dropFirst(5)), "weight": value])
        } else if let key = BatchPlusKey(rawValue: id) {
          switch key {
          case .steps, .cfgZeroInitSteps: fields[key.rawValue] = Int(value.rounded())
          case .seed: fields[key.rawValue] = clampedSeed(value)
          case .guidanceScale, .shift: fields[key.rawValue] = value
          }
        }
      }
      if seedVaries {
        fields["randomSeed"] = false
      } else if batch.fixedSeed {
        if let seed = base.seed { fields["seed"] = Int(seed) }
        fields["randomSeed"] = false
      }
      var step: [String: Any] = ["title": parts.joined(separator: " · "), "fields": fields]
      if !loras.isEmpty { step["loras"] = loras }
      steps.append(step)
    }
    let names = columns.map { columnLabel($0, italian: italian) }.joined(separator: ", ")
    return ["name": "\(prefix) · \(names)", "steps": steps]
  }

  static func pipeline(prompts: [String], fixedSeed: Bool, seed: UInt32?, italian: Bool = L.systemIsItalian) -> [String: Any] {
    let steps: [[String: Any]] = prompts.enumerated().map { index, prompt in
      var fields: [String: Any] = ["prompt": prompt]
      if fixedSeed {
        if let seed { fields["seed"] = Int(seed) }
        fields["randomSeed"] = false
      }
      return ["title": L.format(.promptTitle, index + 1, italian: italian), "fields": fields]
    }
    return ["name": "\(prefix) · \(L.text(.modePrompts, italian: italian))", "steps": steps]
  }
}
