import Foundation
import HubKit

/// What the Results sidebar shows for one image: sections of labelled rows, built from the job
/// and the file data of a `GeneratedImage` (spec 2026-10-08, §4.1). Pure logic, no UI.
public struct ResultInfo: Equatable, Sendable {
  public enum Field: Equatable, Sendable {
    case prompt, sentPrompt, negativePrompt
    case model, size, seed, steps, guidance, sampler, shift, cfgZero
    case lora
    case imageStrength, moodboard, mask
    case advanced(key: String), extra(key: String)
    case time, date, fileName, folder, notSaved
  }

  public enum Kind: Equatable, Sendable { case prompt, model, loras, input, advanced, extra, file }

  public struct Row: Equatable, Sendable {
    public let field: Field
    public let value: String
  }

  public struct Section: Equatable, Sendable {
    public let kind: Kind
    public let rows: [Row]
  }

  /// Only the sections with at least one row, in display order.
  public let sections: [Section]

  public init(_ image: GeneratedImage, locale: Locale = .current, timeZone: TimeZone = .current) {
    let job = image.job
    let p = job.parameters

    func number(_ value: Double) -> String {
      value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }
    func integer(_ value: Int) -> String {
      value.formatted(.number.grouping(.never).locale(locale))
    }

    var prompt: [Row] = []
    if !job.prompt.isEmpty { prompt.append(Row(field: .prompt, value: job.prompt)) }
    if !job.negativePrompt.isEmpty { prompt.append(Row(field: .negativePrompt, value: job.negativePrompt)) }
    let sent = job.promptWithTriggers
    if sent != job.prompt.trimmingCharacters(in: .whitespacesAndNewlines) {
      prompt.append(Row(field: .sentPrompt, value: sent))
    }

    var model: [Row] = []
    if !job.model.isEmpty { model.append(Row(field: .model, value: job.model)) }
    model.append(Row(field: .size, value: "\(p.width) × \(p.height)"))
    model.append(Row(field: .seed, value: String(p.seed)))
    model.append(Row(field: .steps, value: integer(p.steps)))
    model.append(Row(field: .guidance, value: number(p.guidanceScale)))
    model.append(Row(field: .sampler, value: p.sampler.displayName))
    model.append(Row(field: .shift, value: p.resolutionDependentShift ? "auto" : number(p.shift)))
    if p.cfgZeroStar { model.append(Row(field: .cfgZero, value: integer(p.cfgZeroInitSteps))) }

    let loras = p.loras.map { lora -> Row in
      var text = "\(lora.file) · \(number(lora.weight)) · \(Self.modeName(lora.mode))"
      let trigger = lora.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trigger.isEmpty { text += " · \(trigger)" }
      return Row(field: .lora, value: text)
    }

    var input: [Row] = []
    if let strength = job.imageStrength { input.append(Row(field: .imageStrength, value: number(strength))) }
    if job.moodboardCount > 0 { input.append(Row(field: .moodboard, value: integer(job.moodboardCount))) }
    if let mask = job.maskSettings {
      var text = "blur \(number(mask.blur)) · outset \(integer(mask.outset))"
      if mask.preserveOriginal { text += " · preserve" }
      input.append(Row(field: .mask, value: text))
    }

    let advanced = Self.advancedRows(p.advanced, number: number)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let extra = p.extra.keys.sorted().compactMap { key -> Row? in
      guard let data = try? encoder.encode(p.extra[key]), let text = String(data: data, encoding: .utf8) else {
        return nil
      }
      return Row(field: .extra(key: key), value: text)
    }

    var file: [Row] = []
    if let label = ElapsedText.label(image.elapsed) { file.append(Row(field: .time, value: label)) }
    file.append(
      Row(
        field: .date,
        value: image.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
      ))
    if let url = image.fileURL {
      file.append(Row(field: .fileName, value: url.lastPathComponent))
      file.append(Row(field: .folder, value: url.deletingLastPathComponent().path))
    }
    if let error = image.saveError { file.append(Row(field: .notSaved, value: error)) }

    let all: [(Kind, [Row])] = [
      (.prompt, prompt), (.model, model), (.loras, loras), (.input, input), (.advanced, advanced),
      (.extra, extra), (.file, file),
    ]
    sections = all.filter { !$0.1.isEmpty }.map { Section(kind: $0.0, rows: $0.1) }
  }

  private static func modeName(_ mode: LoRAMode) -> String {
    switch mode {
    case .all: "all"
    case .base: "base"
    case .refiner: "refiner"
    }
  }

  /// The advanced values that differ from `AdvancedParameters.default`, by JSON key, alphabetical.
  /// No hand-written list: a field added to `AdvancedParameters` shows up by itself.
  private static func advancedRows(_ value: AdvancedParameters, number: (Double) -> String) -> [Row] {
    func dictionary(_ parameters: AdvancedParameters) -> [String: Any] {
      guard let data = try? JSONEncoder().encode(parameters),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return [:] }
      return object
    }
    let current = dictionary(value)
    let defaults = dictionary(.default)
    return current.keys.sorted().compactMap { key -> Row? in
      guard let now = current[key], let base = defaults[key], !(now as AnyObject).isEqual(base) else { return nil }
      return Row(field: .advanced(key: key), value: text(now, number: number))
    }
  }

  private static func text(_ value: Any, number: (Double) -> String) -> String {
    if let string = value as? String { return string }
    if let n = value as? NSNumber {
      if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
      return number(n.doubleValue)
    }
    return String(describing: value)
  }
}
