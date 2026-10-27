import Foundation

// Saving a pipeline step (the queue keeps a plug-in's pipeline as a copy of its steps). Lenient like the other saved
// formats: a missing key takes its default, a field key that is not a `ContributionField` is left out.

extension FieldValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) {
      self = .bool(flag)
    } else if let number = try? container.decode(Int.self) {
      self = .int(number)
    } else if let number = try? container.decode(Double.self) {
      self = .double(number)
    } else {
      self = .text(try container.decode(String.self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let text): try container.encode(text)
    case .int(let number): try container.encode(number)
    case .double(let number): try container.encode(number)
    case .bool(let flag): try container.encode(flag)
    }
  }
}

extension FieldOverlay: Codable {
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode([String: FieldValue].self)
    var values: [ContributionField: FieldValue] = [:]
    for (key, value) in raw {
      if let field = ContributionField(rawValue: key) { values[field] = value }
    }
    self.init(values)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }))
  }
}

extension PluginImageRef: Codable {
  private enum CodingKeys: String, CodingKey { case name, path }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
    let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    self.init(name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name, path: path)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(path, forKey: .path)
  }
}

extension PipelineSize: Codable {
  private enum CodingKeys: String, CodingKey { case width, height }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 0,
      height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 0)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
  }
}

extension PipelineStep: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, preset, fields, loras, moodboard, startImage, useOutputAsStart, usesPresetModel, scale, strength, mask,
      maskSettings, size
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      preset: try container.decodeIfPresent(String.self, forKey: .preset) ?? "",
      fields: try container.decodeIfPresent(FieldOverlay.self, forKey: .fields) ?? FieldOverlay(),
      loras: try container.decodeIfPresent([LoRASelection].self, forKey: .loras) ?? [],
      moodboard: try container.decodeIfPresent([PluginImageRef].self, forKey: .moodboard),
      startImage: try container.decodeIfPresent(PluginImageRef.self, forKey: .startImage),
      useOutputAsStart: try container.decodeIfPresent(Bool.self, forKey: .useOutputAsStart) ?? false,
      usesPresetModel: try container.decodeIfPresent(Bool.self, forKey: .usesPresetModel) ?? false,
      scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
      strength: try container.decodeIfPresent(Double.self, forKey: .strength),
      mask: try container.decodeIfPresent(PluginImageRef.self, forKey: .mask),
      maskSettings: try container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings),
      size: try container.decodeIfPresent(PipelineSize.self, forKey: .size))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(preset, forKey: .preset)
    try container.encode(fields, forKey: .fields)
    try container.encode(loras, forKey: .loras)
    try container.encodeIfPresent(moodboard, forKey: .moodboard)
    try container.encodeIfPresent(startImage, forKey: .startImage)
    try container.encode(useOutputAsStart, forKey: .useOutputAsStart)
    try container.encode(usesPresetModel, forKey: .usesPresetModel)
    try container.encode(scale, forKey: .scale)
    try container.encodeIfPresent(strength, forKey: .strength)
    try container.encodeIfPresent(mask, forKey: .mask)
    try container.encodeIfPresent(maskSettings, forKey: .maskSettings)
    try container.encodeIfPresent(size, forKey: .size)
  }
}
