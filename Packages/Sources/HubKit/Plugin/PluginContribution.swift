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

/// A size in pixels.
public struct PipelineSize: Equatable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// One pass of a pipeline (`2026-10-04-preset-pipeline-design.md` §4): a preset to run, by name, and the inputs a
/// preset does not hold. The preset's values are the user's to see and change in the Preset menu.
public struct PipelineStep: Equatable, Sendable {
  public var title: String
  /// The preset to run; empty runs the tab's fields as they are.
  public var preset: String
  /// The values this pass changes on the tab's fields (after the preset, when there is one); the keys of
  /// `contribute.fields`. Empty changes nothing. A size in it is ignored when the pass runs.
  public var fields: FieldOverlay
  /// LoRAs this pass sets: one already on the tab gets the weight (and the mode or trigger word, when given); a new
  /// one is added at the end.
  public var loras: [LoRASelection]
  /// The Moodboard of this pass; nil keeps the one on the tab.
  public var moodboard: [PluginImageRef]?
  public var startImage: PluginImageRef?
  /// The picture the previous pass made becomes the start image of this one.
  public var useOutputAsStart: Bool
  /// The three values below belong to the pipelines the user makes in the Preset menu
  /// (`2026-10-12-pipeline-di-preset-utente-design.md` §5); they are never read from a plug-in's JSON.
  /// The pass runs with the model of its preset, when the preset names one; false keeps the header's model.
  public var usesPresetModel: Bool
  /// The size of the previous pass is multiplied by this (from the second pass on).
  public var scale: Double
  /// The strength of this pass (0…1); nil is the automatic one.
  public var strength: Double?
  /// The next three belong to the passes a plug-in hands over one at a time (a guided pipeline); a static pass ignores them.
  /// The inpaint mask of the pass: a PNG the size of the pass, 255 where the model regenerates (like `MaskBitmap`).
  public var mask: PluginImageRef?
  /// How Draw Things treats that mask; nil keeps the Control tab's.
  public var maskSettings: MaskSettings?
  /// The size the pass generates at, in pixels (a multiple of 64).
  public var size: PipelineSize?

  public init(
    title: String = "", preset: String = "", fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection] = [],
    moodboard: [PluginImageRef]? = nil, startImage: PluginImageRef? = nil, useOutputAsStart: Bool = false,
    usesPresetModel: Bool = false, scale: Double = 1, strength: Double? = nil, mask: PluginImageRef? = nil,
    maskSettings: MaskSettings? = nil, size: PipelineSize? = nil
  ) {
    self.mask = mask
    self.maskSettings = maskSettings
    self.size = size
    self.usesPresetModel = usesPresetModel
    self.scale = scale
    self.strength = strength
    self.title = title
    self.preset = preset
    self.fields = fields
    self.loras = loras
    self.moodboard = moodboard
    self.startImage = startImage
    self.useOutputAsStart = useOutputAsStart
  }

  init(_ object: [String: JSONValue]) {
    var title = ""
    if case .string(let text)? = object["title"] { title = text }
    var preset = ""
    if case .string(let text)? = object["preset"] { preset = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var useOutput = false
    if case .bool(let flag)? = object["useOutputAsStart"] { useOutput = flag }
    var fields = FieldOverlay()
    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
    var maskSettings: MaskSettings?
    if let raw = object["maskSettings"], let data = try? JSONEncoder().encode(raw) {
      maskSettings = (try? JSONDecoder().decode(MaskSettings.self, from: data))?.clamped()
    }
    var size: PipelineSize?
    if case .object(let box)? = object["size"], let width = PluginContribution.integer(box["width"]),
      let height = PluginContribution.integer(box["height"])
    {
      size = PipelineSize(width: width, height: height)
    }
    self.init(
      title: title, preset: preset, fields: fields, loras: PluginContribution.loras(object["loras"]) ?? [],
      moodboard: PluginContribution.images(object["moodboard"]),
      startImage: PluginImageRef(object["startImage"]), useOutputAsStart: useOutput,
      mask: PluginImageRef(object["mask"]), maskSettings: maskSettings, size: size)
  }
}

/// A finished picture a plug-in made (a composed enlargement): the app keeps it as a result, in the project's folder and in
/// the Results strip. `description` takes the place of the prompt in the Results window's side panel.
public struct PluginResult: Equatable, Sendable {
  public var image: PluginImageRef
  public var description: String

  public init(image: PluginImageRef, description: String = "") {
    self.image = image
    self.description = description
  }
}

/// A list of passes that RUN executes one after the other.
public struct PluginPipeline: Equatable, Sendable {
  public var name: String
  public var steps: [PipelineStep]
  /// A pipeline the plug-in guides: no list of passes, the app asks the plug-in for each one (`session.next`).
  public var guided: GuidedPipeline?

  public init(name: String = "", steps: [PipelineStep], guided: GuidedPipeline? = nil) {
    self.name = name
    self.steps = steps
    self.guided = guided
  }

  /// How many passes RUN will make: the ones declared by a guided pipeline, or the listed ones.
  public var passCount: Int { guided?.passes ?? steps.count }
}

/// A pipeline whose passes the plug-in hands over one at a time (`session.next`). `estimate` is a pass like the real ones
/// (the biggest), so the CU meter can measure `passes` of them.
public struct GuidedPipeline: Equatable, Sendable {
  public var passes: Int
  public var estimate: PipelineStep

  public init(passes: Int, estimate: PipelineStep = PipelineStep()) {
    self.passes = passes
    self.estimate = estimate
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
  /// How much the start image is changed (0…1), as the Control tab's slider; applied only with a start image.
  public var strength: Double?
  /// A drawing (a PNG with transparency) that becomes the Brush layer of the Control tab, over the start image.
  public var paint: PluginImageRef?
  /// A finished picture to keep as a result (a PNG in the plug-in's folder).
  public var result: PluginResult?

  public init(
    fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection] = [], moodboard: [PluginImageRef] = [],
    startImage: PluginImageRef? = nil, pipeline: PluginPipeline? = nil, strength: Double? = nil,
    paint: PluginImageRef? = nil, result: PluginResult? = nil
  ) {
    self.result = result
    self.strength = strength
    self.paint = paint
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
    } else if case .object(let body)? = object["pipeline"], case .bool(true)? = body["guided"],
      let passes = Self.integer(body["passes"]), passes >= 1
    {
      var name = ""
      if case .string(let text)? = body["name"] { name = text }
      var estimate = PipelineStep()
      if case .object(let json)? = body["estimate"] { estimate = PipelineStep(json) }
      pipeline = PluginPipeline(name: name, steps: [], guided: GuidedPipeline(passes: passes, estimate: estimate))
    }
    self.init(
      fields: fields, loras: Self.loras(object["loras"]) ?? [], moodboard: Self.images(object["moodboard"]) ?? [],
      startImage: PluginImageRef(object["startImage"]), pipeline: pipeline, strength: Self.strength(object["strength"]),
      paint: PluginImageRef(object["paint"]), result: Self.result(object["result"]))
  }

  /// `{"path","name","description"}`; nothing without a path.
  static func result(_ value: JSONValue?) -> PluginResult? {
    guard let image = PluginImageRef(value), case .object(let object)? = value else { return nil }
    var description = ""
    if case .string(let text)? = object["description"] { description = text }
    return PluginResult(image: image, description: description)
  }

  /// A whole number (an integer or a double with no fraction); anything else is nothing.
  static func integer(_ value: JSONValue?) -> Int? {
    switch value {
    case .int(let number)?: number
    case .double(let number)? where number.isFinite && number == number.rounded(): Int(number)
    default: nil
    }
  }

  /// A number, brought into 0…1; anything else is nothing.
  static func strength(_ value: JSONValue?) -> Double? {
    switch value {
    case .double(let number)? where number.isFinite: min(1, max(0, number))
    case .int(let number)?: min(1, max(0, Double(number)))
    default: nil
    }
  }

  /// True when the message carries nothing the app can use.
  public var isEmpty: Bool {
    fields.isEmpty && loras.isEmpty && moodboard.isEmpty && startImage == nil && pipeline == nil && strength == nil
      && paint == nil && result == nil
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
