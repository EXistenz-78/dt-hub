import CoreGraphics
import DTHubPluginKit
import Foundation

/// The tools Tiled Upscale offers to agents (MCP clients) through DT Hub: what the tab does, without the tab. The app lists them
/// as `plugin__tiledupscale__<name>` while the plug-in is active and the model is one it has a preset for, and sends
/// `tool.call`. Whatever text comes back (the name of the picture, the notice of the tab) is data for the agent, and the app
/// marks it so.
///
/// `upscale` is the one that generates. It does what Prepare does (sets the picture and the choices, registers the preset,
/// proposes the guided pipeline) and then answers `startsRun`: the app presses RUN through its own Run path, the same as
/// `run_pipeline`. The budget therefore counts the exact number of tiles, the user's threshold may ask them, and the agent
/// follows the job with `wait_for_job`. A big job (over 100 megapixels or 100 tiles) needs `confirm_large`, the argument form
/// of the second press of Prepare.
enum TUTools {
  /// The families the plug-in has a preset for (`TUPresetTable`).
  static let families = ["flux2_9b", "flux3_5b", "qwen_image_2.1"]

  private static let setupParameters: [DTHubToolParameter] = [
    DTHubToolParameter(
      name: "image",
      description:
        "The picture to enlarge: a result_id from list_results, or the path of a picture file in a folder DT Hub allows (the project, output and Results folders, or one the user allowed). Leave it out to use the picture already on the plug-in's tab.",
      format: DTHubToolParameter.imageFormat),
    DTHubToolParameter(
      name: "factor", type: "integer",
      description: "The enlargement: 2 or 4 (default: the tab's, 2 at first)."),
    DTHubToolParameter(
      name: "overlap", type: "integer",
      description: "The overlap between tiles in pixels, 256 or 320. Changing it puts the advanced values of the mask back to the defaults of that overlap."),
    DTHubToolParameter(
      name: "tile_size", type: "integer",
      description:
        "The longest side of a tile, a multiple of 64 from 1024 to 2048. By default the plug-in picks the smallest that needs at most three tiles along the shorter side; a bigger tile means fewer tiles and joins and a longer pass."),
    DTHubToolParameter(
      name: "lora_weight", type: "number",
      description: "The strength of the preset's LoRA, -4 to 4 (default: the preset's own, see get_options)."),
    DTHubToolParameter(
      name: "extra_prompt",
      description: "Instructions added after the preset's prompt of every tile (an empty text clears them). Keep them short."),
    DTHubToolParameter(
      name: "reset_advanced", type: "boolean",
      description: "Put the advanced values (free, blur, outset, fade, tone_strength, tone_radius) back to the defaults first."),
    DTHubToolParameter(
      name: "free", type: "integer", description: "Advanced: pixels of the overlap the masks leave as they were (0 to the overlap)."),
    DTHubToolParameter(name: "blur", type: "number", description: "Advanced: softness of the mask's edge, 0 to 30."),
    DTHubToolParameter(name: "outset", type: "integer", description: "Advanced: how far the mask's edge reaches, 0 to 100."),
    DTHubToolParameter(
      name: "fade", type: "integer",
      description: "Advanced: pixels over which the neighbour's result fades into the source (0 to what the overlap leaves after free)."),
    DTHubToolParameter(
      name: "tone_strength", type: "integer", description: "Advanced: how much of the brightness correction is applied, 0 to 100 %."),
    DTHubToolParameter(name: "tone_radius", type: "integer", description: "Advanced: radius of the brightness correction, 16 to 256 px."),
    DTHubToolParameter(
      name: "confirm_large", type: "boolean",
      description:
        "Set it to true only after the user agreed to a big job (over 100 megapixels or 100 tiles); without it the tool refuses one. An enlargement over 16384 px on a side or 268 megapixels is always refused."),
  ]

  static let declarations: [DTHubTool] = [
    DTHubTool(
      name: "get_status",
      description:
        "The plug-in's tab as it is now: the picture (name and size), the enlargement and the choices, what the job will be (final size, tile grid, number of tiles = passes, megapixels the model will make, a rough measure of the time), the preset of the model in the header, whether the job is prepared, and the plug-in's last notice.",
      level: .read, families: families),
    DTHubTool(
      name: "get_options",
      description:
        "What can be chosen: the enlargements, overlaps, tile sizes, LoRA strengths and the advanced values with their ranges, defaults and current values, and the plug-in's presets by model family (steps, guidance, sampler, shift, LoRA). The saved preset the user may have edited in DT Hub's Preset menu wins over this table when a tile is made.",
      level: .read, families: families),
    DTHubTool(
      name: "prepare_upscale",
      description:
        "Sets the picture and the choices on the plug-in's tab (arguments you leave out stay as they are) and proposes the guided pipeline to the app, as the Prepare button does, WITHOUT generating: it answers the final size and the number of tiles, so you can judge the job before paying for it. Then upscale (no arguments) runs it. Changes the tab (the user sees the choices), so it needs «Modify the tab» or more.",
      level: .edit, parameters: setupParameters, families: families, timeout: 120),
    DTHubTool(
      name: "upscale",
      description:
        "Enlarges a picture 2× or 4× tile by tile with the model in the header and starts the job: it does what prepare_upscale does and then presses RUN. Returns at once with a job_id (and the tile count): follow it with wait_for_job; the enlarged picture becomes a result of the session (get_results / get_image). Every tile counts as one image against the session budget; a job over the user's threshold may wait for the user's yes in DT Hub. Without arguments it runs what prepare_upscale prepared. One job at a time. Takes minutes to hours (about 9 tiles of 1536 px took 360 s on a fast Mac); the user can stop it.",
      level: .generate, parameters: setupParameters, families: families, timeout: 120),
  ]

  /// What the tools need from the plug-in beyond the tab: the two messages to the app (a test gives its own).
  struct Connection {
    var contribute: ([String: Any]) async -> [String: Any]?
    var registerPreset: ([String: Any]) async -> [String: Any]?
  }

  struct Failure: Error { var text: String }

  @MainActor
  static func handle(_ call: DTHubToolCall, state: TUState, connection: Connection) async -> Data {
    do {
      switch call.tool {
      case "get_status": return DTHubMessage.toolResult(try status(state))
      case "get_options": return DTHubMessage.toolResult(try options(state))
      case "prepare_upscale": return DTHubMessage.toolResult(try await prepareJob(call, state, connection))
      case "upscale":
        let text = try await prepareJob(call, state, connection)
        return DTHubMessage.toolResult(text, startsRun: true)
      default: return DTHubMessage.bare("unsupported")
      }
    } catch let failure as Failure {
      return DTHubMessage.toolResult(failure.text, isError: true)
    } catch {
      return DTHubMessage.toolResult(error.localizedDescription, isError: true)
    }
  }

  // MARK: Reading

  @MainActor
  private static func status(_ state: TUState) throws -> String {
    try ready(state)
    var object: [String: Any] = [
      "family": null(state.family), "preset": null(state.preset?.name), "hasPicture": state.image != nil,
      "factor": state.factor, "overlap": state.overlap.rawValue, "tileSize": state.tileSize, "loraWeight": state.loraWeight,
      "extraPrompt": state.extraPrompt, "advanced": advanced(state), "prepared": state.isPrepared,
      "resultReady": state.resultReady, "canRegenerateTile": state.canRegenerate, "notice": null(state.notice),
    ]
    if state.image != nil {
      object["picture"] = pictureInfo(state)
      if let summary = state.summary { object["job"] = job(summary, state) }
    }
    return try json(object)
  }

  @MainActor
  private static func options(_ state: TUState) throws -> String {
    try ready(state)
    func range<T: Comparable>(_ r: ClosedRange<T>) -> [String: Any] { ["min": r.lowerBound, "max": r.upperBound] }
    let defaults = TUSettings.defaults(for: state.overlap)
    let current = state.settings
    func entry(_ name: String, _ now: Any, _ initial: Any, _ limits: [String: Any], _ what: String) -> [String: Any] {
      ["argument": name, "current": now, "default": initial, "range": limits, "what": what]
    }
    let advanced: [[String: Any]] = [
      entry("free", current.free, defaults.free, ["min": 0, "max": state.overlap.rawValue], "pixels of the overlap left as they were"),
      entry("blur", current.blur, defaults.blur, range(TUSettings.blurRange), "softness of the mask's edge"),
      entry("outset", current.outset, defaults.outset, range(TUSettings.outsetRange), "how far the mask's edge reaches"),
      entry("fade", current.fade, defaults.fade, ["min": 0, "max": state.fadeRange.upperBound], "pixels the neighbour's result fades into the source"),
      entry("tone_strength", current.toneStrength, defaults.toneStrength, range(TUSettings.toneStrengthRange), "brightness correction applied, in %"),
      entry("tone_radius", current.toneRadius, defaults.toneRadius, range(TUSettings.toneRadiusRange), "radius of the brightness correction, px"),
    ]
    let presets: [[String: Any]] = [
      ("flux2_9b", nil), ("flux3_5b", nil), ("qwen_image_2.1", "turbo"), ("qwen_image_2.1", "standard"),
    ].compactMap { family, model in
      guard let preset = TUPresetTable.preset(forFamily: family, model: model) else { return nil }
      return [
        "family": family, "name": preset.name, "steps": preset.steps, "guidanceScale": preset.guidanceScale, "shift": preset.shift,
        "resolutionDependentShift": preset.resolutionDependentShift, "loraFile": preset.loraFile,
        "defaultLoRAWeight": preset.defaultLoRAWeight, "turboModel": model == "turbo",
      ]
    }
    return try json([
      "factors": TUSettings.factors, "overlaps": TileOverlap.allCases.map(\.rawValue),
      "tileSize": ["min": TUSettings.tileRange.lowerBound, "max": TUSettings.tileRange.upperBound, "step": 64],
      "loraWeight": range(TUPresetTable.loraWeightRange), "advanced": advanced, "presets": presets,
      "currentPreset": null(state.preset?.name),
      "limits": [
        "refuseOverSide": TileLimits.maxSide, "refuseOverMegapixels": TileLimits.maxPixels / 1_000_000,
        "confirmLargeOverMegapixels": TileLimits.warnPixels / 1_000_000, "confirmLargeOverTiles": TileLimits.warnPasses,
      ],
    ])
  }

  // MARK: Preparing

  /// Sets what the call names, proposes the pipeline and answers what the job is. Throws why not; nothing is changed when
  /// an argument is out of range.
  @MainActor
  private static func prepareJob(_ call: DTHubToolCall, _ state: TUState, _ connection: Connection) async throws -> String {
    try ready(state)
    guard state.preset != nil else {
      throw Failure(text: "The model in the header has no Tiled Upscale preset: use FLUX.2 [klein] 9B, FLUX.3 [klein] or Qwen Image 2.1.")
    }
    let setup = try parse(call, state)
    let givesNothing = setup.isEmpty && call.string("image") == nil
    if givesNothing, state.isPrepared, call.tool == "upscale", state.summary != nil {
      // `prepare_upscale` already did the work: only the run is left.
      return try json(["prepared": true, "job": job(state.summary!, state), "picture": pictureInfo(state)])
    }
    var loaded: CGImageBox?
    if let path = call.string("image") {
      guard let image = TUImage.load(URL(fileURLWithPath: path)) else {
        throw Failure(text: "The picture could not be read as an image (PNG, JPEG, HEIC or WebP).")
      }
      loaded = CGImageBox(image: image, name: URL(fileURLWithPath: path).lastPathComponent)
    } else if state.image == nil {
      throw Failure(text: "No picture: give 'image' (a result_id from list_results or a picture file in an allowed folder).")
    }
    // Everything is checked: now the tab changes. The order matters: the picture and the enlargement set the tile size by
    // themselves, the overlap sets the free part, and a value the call names wins over what was set by itself.
    if let loaded { state.setImage(loaded.image, name: loaded.name) }
    if let factor = setup.factor, factor != state.factor { state.factor = factor }
    if let overlap = setup.overlap, overlap != state.overlap { state.overlap = overlap }
    if setup.resetAdvanced { state.resetAdvanced() }
    if let free = setup.free { state.maskFree = free }
    if let blur = setup.blur { state.maskBlur = blur }
    if let outset = setup.outset { state.maskOutset = outset }
    if let fade = setup.fade { state.junctionFade = fade }
    if let value = setup.toneStrength { state.toneStrength = value }
    if let value = setup.toneRadius { state.toneRadius = value }
    if let tile = setup.tileSize { state.tileSize = tile }
    if let weight = setup.loraWeight { state.loraWeight = weight }
    if let text = setup.extraPrompt { state.extraPrompt = text }

    guard let summary = state.summary else { throw Failure(text: "No picture.") }
    switch summary.verdict {
    case .refuse:
      throw Failure(
        text:
          "Too big: \(summary.width)×\(summary.height) px (\(megapixels(summary)) megapixels). The plug-in refuses over \(TileLimits.maxSide) px on a side or \(TileLimits.maxPixels / 1_000_000) megapixels. Use factor 2, or a smaller picture."
      )
    case .warn where call.bool("confirm_large") != true:
      throw Failure(
        text:
          "This is a big job: \(summary.width)×\(summary.height) px (\(megapixels(summary)) megapixels), \(summary.passes) tiles. Over \(TileLimits.warnPixels / 1_000_000) megapixels or \(TileLimits.warnPasses) tiles it needs the user's agreement: ask them, and only then call again with confirm_large=true."
      )
    default: break
    }
    await state.prepare(confirmed: true, contribute: connection.contribute, registerPreset: connection.registerPreset)
    guard state.isPrepared else {
      throw Failure(text: state.notice ?? "DT Hub did not take the pipeline: it may be busy with another one.")
    }
    return try json(["prepared": true, "job": job(summary, state), "picture": pictureInfo(state)])
  }

  private struct CGImageBox {
    let image: CGImage
    let name: String
  }

  /// The values a call names, checked. `isEmpty` when it names none of the choices.
  private struct Setup {
    var factor: Int?
    var overlap: TileOverlap?
    var tileSize: Int?
    var loraWeight: Double?
    var extraPrompt: String?
    var resetAdvanced = false
    var free: Int?
    var blur: Double?
    var outset: Int?
    var fade: Int?
    var toneStrength: Int?
    var toneRadius: Int?

    var isEmpty: Bool {
      factor == nil && overlap == nil && tileSize == nil && loraWeight == nil && extraPrompt == nil && !resetAdvanced
        && free == nil && blur == nil && outset == nil && fade == nil && toneStrength == nil && toneRadius == nil
    }
  }

  @MainActor
  private static func parse(_ call: DTHubToolCall, _ state: TUState) throws -> Setup {
    var setup = Setup()
    func whole(_ key: String, _ range: ClosedRange<Int>) throws -> Int? {
      guard call.arguments[key] != nil, !(call.arguments[key] is NSNull) else { return nil }
      guard let value = call.integer(key), range.contains(value) else {
        throw Failure(text: "'\(key)' must be a whole number from \(range.lowerBound) to \(range.upperBound).")
      }
      return value
    }
    if let value = try whole("factor", (TUSettings.factors.min() ?? 2)...(TUSettings.factors.max() ?? 4)) {
      guard TUSettings.factors.contains(value) else { throw Failure(text: "'factor' must be one of \(TUSettings.factors).") }
      setup.factor = value
    }
    if let value = try whole("overlap", 0...1000) {
      guard let overlap = TileOverlap(rawValue: value) else {
        throw Failure(text: "'overlap' must be one of \(TileOverlap.allCases.map(\.rawValue)).")
      }
      setup.overlap = overlap
    }
    if let value = try whole("tile_size", TUSettings.tileRange) {
      guard value % 64 == 0 else { throw Failure(text: "'tile_size' must be a multiple of 64.") }
      setup.tileSize = value
    }
    if call.arguments["lora_weight"] != nil {
      guard let value = call.number("lora_weight"), TUPresetTable.loraWeightRange.contains(value) else {
        throw Failure(text: "'lora_weight' must be a number from -4 to 4.")
      }
      setup.loraWeight = value
    }
    if let text = call.string("extra_prompt") {
      guard text.count <= 1000 else { throw Failure(text: "'extra_prompt' is longer than 1000 characters.") }
      setup.extraPrompt = text
    }
    setup.resetAdvanced = call.bool("reset_advanced") == true
    // The free part and the fade depend on the overlap the job will have, and on the free part left by the reset or by the new overlap.
    let overlap = (setup.overlap ?? state.overlap).rawValue
    let resets = setup.resetAdvanced || (setup.overlap != nil && setup.overlap != state.overlap)
    let freeNow = setup.free ?? (resets ? TUSettings.defaultFree(for: TileOverlap(rawValue: overlap) ?? .standard) : state.maskFree)
    setup.free = try whole("free", 0...overlap)
    let fadeLimit = max(0, overlap - (setup.free ?? freeNow))
    setup.fade = try whole("fade", 0...fadeLimit)
    setup.outset = try whole("outset", TUSettings.outsetRange)
    setup.toneStrength = try whole("tone_strength", TUSettings.toneStrengthRange)
    setup.toneRadius = try whole("tone_radius", TUSettings.toneRadiusRange)
    if call.arguments["blur"] != nil {
      guard let value = call.number("blur"), TUSettings.blurRange.contains(value) else {
        throw Failure(text: "'blur' must be a number from 0 to 30.")
      }
      setup.blur = value
    }
    return setup
  }

  // MARK: Helpers

  @MainActor
  private static func ready(_ state: TUState) throws {
    guard state.active else { throw Failure(text: "Tiled Upscale is not active for the job.") }
    guard state.tempFolder != nil else {
      throw Failure(text: "DT Hub has not sent the plug-in its context yet: try again in a moment.")
    }
  }

  private static func megapixels(_ summary: TUSummary) -> Int { summary.width * summary.height / 1_000_000 }

  @MainActor
  private static func pictureInfo(_ state: TUState) -> [String: Any] {
    guard let image = state.image else { return [:] }
    return ["name": state.imageName, "width": image.width, "height": image.height]
  }

  @MainActor
  private static func advanced(_ state: TUState) -> [String: Any] {
    [
      "free": state.maskFree, "blur": state.maskBlur, "outset": state.maskOutset, "fade": state.junctionFade,
      "tone_strength": state.toneStrength, "tone_radius": state.toneRadius,
    ]
  }

  @MainActor
  private static func job(_ summary: TUSummary, _ state: TUState) -> [String: Any] {
    [
      "finalWidth": summary.width, "finalHeight": summary.height, "finalMegapixels": Double(summary.width * summary.height) / 1_000_000,
      "columns": summary.columns, "rows": summary.rows, "tiles": summary.passes, "tileSize": state.tileSize,
      "generatedMegapixels": (summary.generatedMegapixels * 10).rounded() / 10, "croppedTo64": summary.cropped,
      "verdict": "\(summary.verdict)", "factor": state.factor, "overlap": state.overlap.rawValue,
      "preset": null(state.preset?.name), "loraWeight": state.loraWeight, "stepsPerTile": null(state.preset?.steps),
      "note":
        "generatedMegapixels is a rough measure of the time: the area of every tile, overlaps counted each time. Each tile is one image for the budget.",
    ]
  }

  private static func null(_ value: Any?) -> Any { value ?? NSNull() }

  private static func json(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    return String(decoding: data, as: UTF8.self)
  }
}
