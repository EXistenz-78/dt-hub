import Foundation

/// A field of the Generation tab a plug-in can fill (plug-in design §7). The raw value is the key in the
/// `fields` object of the `contribute` message.
public enum ContributionField: String, CaseIterable, Codable, Hashable, Sendable {
  case prompt, negativePrompt
  case width, height, steps, guidanceScale, cfgZeroStar, cfgZeroInitSteps, sampler, shift, resolutionDependentShift
  case seed, randomSeed, batchSize, batchCount
}

/// What a field holds, as a plug-in sends it. The sampler is its raw value.
public enum FieldValue: Equatable, Sendable {
  case text(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
}

/// The prompt, the negative prompt and the base parameters: everything `ContributionField` names.
public struct GenerationFields: Equatable, Sendable {
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters

  public init(prompt: String = "", negativePrompt: String = "", parameters: GenerationParameters = .default) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
  }

  public func value(of field: ContributionField) -> FieldValue {
    switch field {
    case .prompt: .text(prompt)
    case .negativePrompt: .text(negativePrompt)
    case .width: .int(parameters.width)
    case .height: .int(parameters.height)
    case .steps: .int(parameters.steps)
    case .guidanceScale: .double(parameters.guidanceScale)
    case .cfgZeroStar: .bool(parameters.cfgZeroStar)
    case .cfgZeroInitSteps: .int(parameters.cfgZeroInitSteps)
    case .sampler: .int(parameters.sampler.rawValue)
    case .shift: .double(parameters.shift)
    case .resolutionDependentShift: .bool(parameters.resolutionDependentShift)
    case .seed: .int(Int(parameters.seed))
    case .randomSeed: .bool(parameters.randomSeed)
    case .batchSize: .int(parameters.batchSize)
    case .batchCount: .int(parameters.batchCount)
    }
  }

  /// Puts a value in a field; a value of the wrong kind is ignored. Numbers are not limited here:
  /// `FieldOverlay.applied(to:)` limits them all at once.
  public mutating func set(_ value: FieldValue, for field: ContributionField) {
    switch (field, value) {
    case (.prompt, .text(let text)): prompt = text
    case (.negativePrompt, .text(let text)): negativePrompt = text
    case (.width, .int(let number)): parameters.width = number
    case (.height, .int(let number)): parameters.height = number
    case (.steps, .int(let number)): parameters.steps = number
    case (.guidanceScale, .double(let number)): parameters.guidanceScale = number
    case (.cfgZeroStar, .bool(let flag)): parameters.cfgZeroStar = flag
    case (.cfgZeroInitSteps, .int(let number)): parameters.cfgZeroInitSteps = number
    case (.sampler, .int(let number)): if let sampler = Sampler(rawValue: number) { parameters.sampler = sampler }
    case (.shift, .double(let number)): parameters.shift = number
    case (.resolutionDependentShift, .bool(let flag)): parameters.resolutionDependentShift = flag
    case (.seed, .int(let number)): parameters.seed = UInt32(clamping: max(number, 0))
    case (.randomSeed, .bool(let flag)): parameters.randomSeed = flag
    case (.batchSize, .int(let number)): parameters.batchSize = number
    case (.batchCount, .int(let number)): parameters.batchCount = number
    default: break
    }
  }
}

/// Values for some fields, read from the JSON a plug-in sends. A key that is not a field, or a value of
/// the wrong kind, is left out: a plug-in cannot break the app with a bad message.
public struct FieldOverlay: Equatable, Sendable {
  public private(set) var values: [ContributionField: FieldValue]

  public init(_ values: [ContributionField: FieldValue] = [:]) { self.values = values }

  public init(json: [String: JSONValue]) {
    var values: [ContributionField: FieldValue] = [:]
    for (key, raw) in json {
      guard let field = ContributionField(rawValue: key), let value = Self.value(raw, for: field) else { continue }
      values[field] = value
    }
    self.values = values
  }

  public var isEmpty: Bool { values.isEmpty }

  /// The fields, in the order of the Generation tab.
  public var fields: [ContributionField] { ContributionField.allCases.filter { values[$0] != nil } }

  /// The fields with these values, limited to what the tab accepts (sizes in multiples of 64, ranges).
  public func applied(to fields: GenerationFields) -> GenerationFields {
    var result = fields
    for (field, value) in values { result.set(value, for: field) }
    result.parameters = result.parameters.clamped()
    return result
  }

  private static func value(_ raw: JSONValue, for field: ContributionField) -> FieldValue? {
    switch field {
    case .prompt, .negativePrompt:
      if case .string(let text) = raw { return .text(text) }
    case .width, .height, .steps, .cfgZeroInitSteps, .seed, .batchSize, .batchCount:
      if let number = integer(raw) { return .int(number) }
    case .guidanceScale, .shift:
      switch raw {
      case .double(let number) where number.isFinite: return .double(number)
      case .int(let number): return .double(Double(number))
      default: break
      }
    case .cfgZeroStar, .resolutionDependentShift, .randomSeed:
      if case .bool(let flag) = raw { return .bool(flag) }
    case .sampler:
      if let number = integer(raw), Sampler(rawValue: number) != nil { return .int(number) }
      if case .string(let name) = raw,
        let sampler = Sampler.allCases.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame })
      {
        return .int(sampler.rawValue)
      }
    }
    return nil
  }

  private static func integer(_ raw: JSONValue) -> Int? {
    switch raw {
    case .int(let number): return number
    case .double(let number) where number.isFinite && number == number.rounded() && abs(number) < 1e12:
      return Int(number)
    default: return nil
    }
  }
}
