import Foundation

/// An image a plug-in hands over: a file in the folder the app gave it (`PluginContext.tempFolder`).
public struct PluginImageRef: Equatable, Sendable {
  public var name: String
  public var path: String

  public init(name: String, path: String) {
    self.name = name
    self.path = path
  }

  init?(_ value: JSONValue?) {
    guard case .object(let object)? = value, case .string(let path)? = object["path"], !path.isEmpty else { return nil }
    let fallback = URL(fileURLWithPath: path).lastPathComponent
    if case .string(let name)? = object["name"], !name.isEmpty {
      self.init(name: name, path: path)
    } else {
      self.init(name: fallback, path: path)
    }
  }
}

/// One pass of a pipeline: changes to the configuration, the inputs, and whether the picture the previous
/// pass made becomes the start image (plug-in design §7).
public struct PipelineStep: Equatable, Sendable {
  public var title: String
  public var fields: FieldOverlay
  /// The LoRAs of this pass; nil keeps the ones on the tab.
  public var loras: [LoRASelection]?
  /// The Moodboard of this pass; nil keeps the one on the tab.
  public var moodboard: [PluginImageRef]?
  public var startImage: PluginImageRef?
  public var useOutputAsStart: Bool

  public init(
    title: String = "", fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection]? = nil,
    moodboard: [PluginImageRef]? = nil, startImage: PluginImageRef? = nil, useOutputAsStart: Bool = false
  ) {
    self.title = title
    self.fields = fields
    self.loras = loras
    self.moodboard = moodboard
    self.startImage = startImage
    self.useOutputAsStart = useOutputAsStart
  }

  init(_ object: [String: JSONValue]) {
    var title = ""
    if case .string(let text)? = object["title"] { title = text }
    var fields = FieldOverlay()
    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
    var useOutput = false
    if case .bool(let flag)? = object["useOutputAsStart"] { useOutput = flag }
    self.init(
      title: title, fields: fields, loras: PluginContribution.loras(object["loras"]),
      moodboard: PluginContribution.images(object["moodboard"]), startImage: PluginImageRef(object["startImage"]),
      useOutputAsStart: useOutput)
  }
}

extension PipelineStep {
  /// What this pass runs with: the tab's fields with the pass's changes on top, and its own LoRAs when it
  /// has some (an empty list means no LoRA at all).
  public func fields(over base: GenerationFields) -> GenerationFields {
    var result = fields.applied(to: base)
    if let loras { result.parameters.loras = loras }
    return result
  }
}

/// A list of passes that RUN executes one after the other.
public struct PluginPipeline: Equatable, Sendable {
  public var name: String
  public var steps: [PipelineStep]

  public init(name: String = "", steps: [PipelineStep]) {
    self.name = name
    self.steps = steps
  }
}

/// The `contribute` message (plug-in → app): values for fields, LoRAs and Moodboard pictures to add, a
/// start image, a pipeline. Every part is optional; what cannot be read is left out.
public struct PluginContribution: Equatable, Sendable {
  public var fields: FieldOverlay
  public var loras: [LoRASelection]
  public var moodboard: [PluginImageRef]
  public var startImage: PluginImageRef?
  public var pipeline: PluginPipeline?

  public init(
    fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection] = [], moodboard: [PluginImageRef] = [],
    startImage: PluginImageRef? = nil, pipeline: PluginPipeline? = nil
  ) {
    self.fields = fields
    self.loras = loras
    self.moodboard = moodboard
    self.startImage = startImage
    self.pipeline = pipeline
  }

  /// Nil when the data is not a JSON object.
  public init?(message: Data) {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: message), case .object(let object) = root else {
      return nil
    }
    var fields = FieldOverlay()
    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
    var pipeline: PluginPipeline?
    if case .object(let body)? = object["pipeline"], case .array(let list)? = body["steps"] {
      let steps = list.compactMap { value -> PipelineStep? in
        guard case .object(let step) = value else { return nil }
        return PipelineStep(step)
      }
      var name = ""
      if case .string(let text)? = body["name"] { name = text }
      if !steps.isEmpty { pipeline = PluginPipeline(name: name, steps: steps) }
    }
    self.init(
      fields: fields, loras: Self.loras(object["loras"]) ?? [], moodboard: Self.images(object["moodboard"]) ?? [],
      startImage: PluginImageRef(object["startImage"]), pipeline: pipeline)
  }

  /// True when the message carries nothing the app can use.
  public var isEmpty: Bool {
    fields.isEmpty && loras.isEmpty && moodboard.isEmpty && startImage == nil && pipeline == nil
  }

  static func loras(_ value: JSONValue?) -> [LoRASelection]? {
    guard case .array(let list)? = value else { return nil }
    return list.compactMap { item in
      guard let data = try? JSONEncoder().encode(item), var lora = try? JSONDecoder().decode(LoRASelection.self, from: data)
      else { return nil }
      // The weight is limited like the LoRA card limits it.
      lora.weight = min(max(lora.weight, LoRASelection.weightRange.lowerBound), LoRASelection.weightRange.upperBound)
      return lora
    }
  }

  static func images(_ value: JSONValue?) -> [PluginImageRef]? {
    guard case .array(let list)? = value else { return nil }
    return list.compactMap { PluginImageRef($0) }
  }
}
