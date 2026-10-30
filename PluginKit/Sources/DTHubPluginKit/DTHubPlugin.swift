import AppKit
import Foundation

/// What a plug-in says about itself (the JSON `dthubManifest` returns).
public struct DTHubManifest: Codable, Sendable {
  public var id: String
  public var name: String
  public var version: String
  /// The contract version this plug-in was made for.
  public var contract: Int
  /// An SF Symbol name for the tab.
  public var symbol: String
  /// Model families it works with; nil = all.
  public var families: [String]?
  /// True when the plug-in only makes sense with an edit or in-context model (one that takes pictures as references,
  /// like FLUX.2 [klein], Qwen Image Edit or Kontext): DT Hub switches it off with any other model. nil = any model.
  /// An app older than 0.3.0 ignores it and keeps the plug-in on.
  public var requiresEditModel: Bool?

  public init(
    id: String, name: String, version: String = "1.0", contract: Int = DTHubContract.current,
    symbol: String = "puzzlepiece.extension", families: [String]? = nil, requiresEditModel: Bool? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.contract = contract
    self.symbol = symbol
    self.families = families
    self.requiresEditModel = requiresEditModel
  }
}

public enum DTHubContract {
  public static let current = 1
}

/// JSON messages are objects with a `type`.
public enum DTHubMessage {
  public static func type(of data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }

  public static func bare(_ type: String) -> Data { Data(#"{"type":"\#(type)"}"#.utf8) }

  /// `{"type":"ok"}`, with `"state"` when given: the answer to `queue.capture` (the state is yours to define), or a bare `ok`.
  public static func ok(state: [String: Any]? = nil) -> Data {
    var message: [String: Any] = ["type": "ok"]
    if let state { message["state"] = state }
    return (try? JSONSerialization.data(withJSONObject: message)) ?? bare("ok")
  }

  /// `{"type":"error","text":text}`: a message you cannot do.
  public static func failure(_ text: String) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["type": "error", "text": text])) ?? bare("error")
  }
}

/// App → plug-in: `queue.capture`. The user put the guided pipeline that is on RUN in the queue: write the files you will need
/// to guide it again (the picture you start from) into `folder`, then answer `DTHubMessage.ok(state:)` with an object that names
/// them (relative names) and holds your choices, or `DTHubMessage.failure(_:)` when there is nothing prepared to capture.
public struct DTHubQueueCapture {
  /// The plug-in's own folder inside the queue entry; it exists.
  public var folder: URL

  public init?(_ data: Data) {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let path = object["folder"] as? String
    else { return nil }
    folder = URL(fileURLWithPath: path, isDirectory: true)
  }
}

/// App → plug-in: `queue.prepare`. The entry runs now: rebuild your session from `folder` and `state` (what you answered to
/// `queue.capture`), show that state as if the user had set it, and propose the guided pipeline with `contribute` as your own
/// Prepare does, **without asking for any confirmation**. Answer `DTHubMessage.ok()` once the app has accepted the pipeline,
/// or `DTHubMessage.failure(_:)`. `model` and `family` are the header's model for the entry (a plug-in that is not active has
/// not been told): take them before looking for a preset.
public struct DTHubQueuePrepare {
  public var folder: URL
  public var state: [String: Any]
  public var model: String?
  public var family: String?

  public init?(_ data: Data) {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let path = object["folder"] as? String, let state = object["state"] as? [String: Any]
    else { return nil }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    self.state = state
    model = object["model"] as? String
    family = object["family"] as? String
  }
}

/// App → plug-in: a project was opened (message type `project`). Keep the state in `folder` (for example
/// `state.json`) and load what is there: no file, or one that cannot be read, is the initial state. `adoptLegacy` is true
/// once, for the first project ever: if `folder` has no state yet, move the state you had before projects into it.
public struct DTHubProject: Decodable, Sendable {
  public var name: String
  /// The plug-in's own folder inside the project; it exists.
  public var folder: String
  public var adoptLegacy: Bool

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    folder = try container.decode(String.self, forKey: .folder)
    adoptLegacy = try container.decodeIfPresent(Bool.self, forKey: .adoptLegacy) ?? false
  }

  private enum CodingKeys: String, CodingKey { case name, folder, adoptLegacy }
}

/// A language model of the app's models folder (an entry of `DTHubContext.languageModels`).
public struct DTHubLanguageModel: Decodable, Equatable, Sendable {
  /// The name `askLanguageModel(model:)` asks for.
  public var name: String
  /// Its folder, to read files that come with the model.
  public var path: String
  /// True for a vision-language model: it can be given images.
  public var supportsImages: Bool
  /// The family the user assigned it to in Settings › LLM: "*" = all others, else the family key (Draw Things
  /// `version`, e.g. "qwen_image_2.1"); nil = none (or an app that does not say).
  public var family: String?
  /// What it is for: "enhance", "describe", "both" or "plugins"; nil when the app does not say.
  public var use: String?

  public init(name: String, path: String, supportsImages: Bool, family: String? = nil, use: String? = nil) {
    self.name = name
    self.path = path
    self.supportsImages = supportsImages
    self.family = family
    self.use = use
  }
}

/// App → plug-in: where the app stands (message type `context`).
public struct DTHubContext: Decodable, Sendable {
  public var model: String?
  public var family: String?
  /// A folder to exchange image files through.
  public var tempFolder: String
  /// The path of the start image of the Control tab; nil when there is none.
  public var startImage: String?
  /// The Moodboard pictures that are on, as files, in the order of the thumbnails; nil when there are none.
  public var moodboard: [String]?
  /// The language models of the app's models folder; nil when the app does not say.
  public var languageModels: [DTHubLanguageModel]?
  /// The Generation tab's parameters as they are now; nil when the app does not say.
  public var parameters: DTHubParameters?
  /// The Generation tab's prompt ("" when empty); nil from an app that does not send it.
  public var prompt: String?
  public var negativePrompt: String?
  /// How much the start image is changed (0…1), as the Control tab shows it; nil without a start image.
  public var strength: Double?
  /// How to write prompts for the chosen model's family; nil when the app has no guide for it (or does not send it).
  public var promptGuide: DTHubPromptGuide?
  /// The LoRAs of the server, with the trigger words and weights of the app's LoRA manager. Empty when there are none;
  /// nil from an app that does not send it (before 0.2.2).
  public var loraCatalog: [DTHubCatalogLoRA]?
  /// Where the start image sits in the canvas of the Generation: the part of the image that fills it, in the image's
  /// pixels from the top-left (it can be larger than the image: the rest is margin). nil without a start image or from
  /// an app older than 0.4.0.
  public var startImageWindow: DTHubImageWindow?
  /// The start image as the canvas has it (the size of the canvas): cut, zoomed, turned, margins filled; a PNG. Nil without a
  /// start image or from an older app. A plug-in where the user draws on the start image shows this one and sends the drawing
  /// as `paint` with `"space": "canvas"`.
  public var startImageFramed: String?
  /// The newest result of the open project (a file); nil when there is none or from an app older than the release after 0.4.3.
  public var lastResult: DTHubLastResult?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    startImageWindow = (try? container.decodeIfPresent(DTHubImageWindow.self, forKey: .startImageWindow)) ?? nil
    startImageFramed = (try? container.decodeIfPresent(String.self, forKey: .startImageFramed)) ?? nil
    lastResult = (try? container.decodeIfPresent(DTHubLastResult.self, forKey: .lastResult)) ?? nil
    model = try container.decodeIfPresent(String.self, forKey: .model)
    family = try container.decodeIfPresent(String.self, forKey: .family)
    tempFolder = try container.decode(String.self, forKey: .tempFolder)
    startImage = try container.decodeIfPresent(String.self, forKey: .startImage)
    moodboard = try container.decodeIfPresent([String].self, forKey: .moodboard)
    languageModels = try container.decodeIfPresent([DTHubLanguageModel].self, forKey: .languageModels)
    // Whatever is wrong in `parameters` must not cost the plug-in the rest of its context.
    parameters = (try? container.decodeIfPresent(DTHubParameters.self, forKey: .parameters)) ?? nil
    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? nil
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? nil
    strength = (try? container.decodeIfPresent(Double.self, forKey: .strength)) ?? nil
    promptGuide = (try? container.decodeIfPresent(DTHubPromptGuide.self, forKey: .promptGuide)) ?? nil
    // An entry that cannot be read is left out; a catalog that is not a list is no catalog.
    loraCatalog = ((try? container.decodeIfPresent([Lenient<DTHubCatalogLoRA>].self, forKey: .loraCatalog)) ?? nil)?
      .compactMap(\.value)
  }

  private enum CodingKeys: String, CodingKey {
    case model, family, tempFolder, startImage, moodboard, languageModels, parameters, prompt, negativePrompt, strength
    case promptGuide, loraCatalog, startImageWindow, startImageFramed, lastResult
  }
}

/// The newest result of the project (`DTHubContext.lastResult`).
public struct DTHubLastResult: Decodable, Equatable, Sendable {
  public var path: String
  public var name: String

  public init(path: String, name: String) {
    self.path = path
    self.name = name
  }
}

/// The part of the start image that fills the canvas (`DTHubContext.startImageWindow`).
public struct DTHubImageWindow: Decodable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  /// Degrees, clockwise, about the centre of the image; nil when it is not turned. The window is the cut before the turn.
  public var rotation: Double?

  public init(x: Double, y: Double, width: Double, height: Double, rotation: Double? = nil) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.rotation = rotation
  }
}

/// An element of a list that may fail to decode without costing the rest of the list.
private struct Lenient<Value: Decodable>: Decodable {
  let value: Value?
  init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

/// A LoRA of the server (`DTHubContext.loraCatalog`).
public struct DTHubCatalogLoRA: Decodable, Equatable, Sendable {
  public var file: String
  /// The name Draw Things shows; the file's name when the app gives none.
  public var name: String
  /// The family of models the LoRA was made for; nil when the server does not say.
  public var family: String?
  /// The trigger word; empty when there is none.
  public var trigger: String
  /// The weight the LoRA starts with.
  public var weight: Double
  /// The user's lowest and highest weight for the LoRA; nil when there is no limit.
  public var minWeight: Double?
  public var maxWeight: Double?

  public init(
    file: String, name: String, family: String? = nil, trigger: String = "", weight: Double = 1, minWeight: Double? = nil,
    maxWeight: Double? = nil
  ) {
    self.minWeight = minWeight
    self.maxWeight = maxWeight
    self.file = file
    self.name = name
    self.family = family
    self.trigger = trigger
    self.weight = weight
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    file = try container.decode(String.self, forKey: .file)
    guard !file.isEmpty else {
      throw DecodingError.dataCorruptedError(forKey: .file, in: container, debugDescription: "empty file name")
    }
    name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? file
    family = (try? container.decodeIfPresent(String.self, forKey: .family)) ?? nil
    trigger = ((try? container.decodeIfPresent(String.self, forKey: .trigger)) ?? nil) ?? ""
    weight = ((try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? nil) ?? 1
    minWeight = (try? container.decodeIfPresent(Double.self, forKey: .minWeight)) ?? nil
    maxWeight = (try? container.decodeIfPresent(Double.self, forKey: .maxWeight)) ?? nil
  }

  private enum CodingKeys: String, CodingKey {
    case file, name, family, trigger, weight, minWeight, maxWeight
  }
}

/// How to write prompts for the family of the chosen model (`DTHubContext.promptGuide`): the same guide the app's Enhance
/// Prompt follows.
public struct DTHubPromptGuide: Decodable, Equatable, Sendable {
  /// The family as the app names it ("Qwen Image 2.1").
  public var label: String
  /// The family reads a negative prompt.
  public var usesNegative: Bool
  /// The notes, a bullet list in English.
  public var notes: String
  /// The whole Family prompt, placeholders resolved: the rule for the answer and the notes. Nil from an older app.
  public var familyPrompt: String?
  /// How long the prompt should be, and the most it can be (words, or tags for some families).
  public var words: String?
  public var maxWords: String?

  public init(
    label: String, usesNegative: Bool, notes: String, familyPrompt: String? = nil, words: String? = nil,
    maxWords: String? = nil
  ) {
    self.label = label
    self.usesNegative = usesNegative
    self.notes = notes
    self.familyPrompt = familyPrompt
    self.words = words
    self.maxWords = maxWords
  }
}

/// A LoRA of the Generation tab (an entry of `DTHubParameters.loras`).
public struct DTHubLoRA: Decodable, Equatable, Sendable {
  public var file: String
  public var weight: Double
  /// 0 = all, 1 = base, 2 = refiner.
  public var mode: Int
  public var trigger: String

  public init(file: String, weight: Double = 1, mode: Int = 0, trigger: String = "") {
    self.file = file
    self.weight = weight
    self.mode = mode
    self.trigger = trigger
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    file = try container.decode(String.self, forKey: .file)
    weight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
    mode = (try? container.decodeIfPresent(Int.self, forKey: .mode)) ?? 0
    trigger = (try? container.decodeIfPresent(String.self, forKey: .trigger)) ?? ""
  }

  private enum CodingKeys: String, CodingKey { case file, weight, mode, trigger }
}

/// A value of `advanced` or `extra`: shown, not changed.
public enum DTHubValue: Decodable, Equatable, Sendable {
  case bool(Bool)
  case number(Double)
  case string(String)
  /// An array, an object or null.
  case other

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) {
      self = .bool(flag)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let text = try? container.decode(String.self) {
      self = .string(text)
    } else {
      self = .other
    }
  }
}

/// The Generation tab's parameters as the app sends them in `context`. Every field is optional and read with
/// tolerance: a missing field, or one of another type, is nil; nothing here ever throws away the rest of the context.
public struct DTHubParameters: Decodable, Equatable, Sendable {
  public var width, height, steps, cfgZeroInitSteps, sampler, batchSize, batchCount: Int?
  public var guidanceScale, shift: Double?
  public var cfgZeroStar, resolutionDependentShift, randomSeed: Bool?
  public var seed: UInt32?
  public var loras: [DTHubLoRA]?
  /// The advanced values, by name: to show, not to change.
  public var advanced: [String: DTHubValue]?
  public var extra: [String: DTHubValue]?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil }
    width = value(.width)
    height = value(.height)
    steps = value(.steps)
    cfgZeroInitSteps = value(.cfgZeroInitSteps)
    sampler = value(.sampler)
    batchSize = value(.batchSize)
    batchCount = value(.batchCount)
    guidanceScale = value(.guidanceScale)
    shift = value(.shift)
    cfgZeroStar = value(.cfgZeroStar)
    resolutionDependentShift = value(.resolutionDependentShift)
    randomSeed = value(.randomSeed)
    seed = value(.seed)
    loras = value(.loras)
    advanced = value(.advanced)
    extra = value(.extra)
  }

  private enum CodingKeys: String, CodingKey {
    case width, height, steps, cfgZeroInitSteps, sampler, batchSize, batchCount, guidanceScale, shift, cfgZeroStar
    case resolutionDependentShift, randomSeed, seed, loras, advanced, extra
  }
}

/// How a question to the language model is asked. Every field is optional: nil keeps the app's default.
public struct DTHubLLMOptions: Equatable, Sendable {
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var presencePenalty: Double?
  public var maxTokens: Int?
  /// Lets a reasoning model think before it answers.
  public var thinking: Bool?
  /// How long to wait for the answer, in seconds. Only this library uses it (the app never sees it): 300 when
  /// nil, at most 1800.
  public var timeout: Double?

  public static let defaultTimeout = 300.0
  public static let maxTimeout = 1800.0

  public init(
    temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil, presencePenalty: Double? = nil,
    maxTokens: Int? = nil, thinking: Bool? = nil, timeout: Double? = nil
  ) {
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.presencePenalty = presencePenalty
    self.maxTokens = maxTokens
    self.thinking = thinking
    self.timeout = timeout
  }

  var effectiveTimeout: Double { min(max(timeout ?? Self.defaultTimeout, 1), Self.maxTimeout) }

  /// The `options` object of the `llm` message: only what is set, and not the timeout.
  var json: [String: Any] {
    var object: [String: Any] = [:]
    if let temperature { object["temperature"] = temperature }
    if let topP { object["topP"] = topP }
    if let topK { object["topK"] = topK }
    if let presencePenalty { object["presencePenalty"] = presencePenalty }
    if let maxTokens { object["maxTokens"] = maxTokens }
    if let thinking { object["thinking"] = thinking }
    return object
  }
}

/// One earlier turn of a conversation, for `askLanguageModel(history:)`.
public struct DTHubLLMTurn: Equatable, Sendable {
  public enum Role: String, Sendable { case user, assistant }

  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    self.role = role
    self.text = text
  }
}

/// What the language model answered, or why not.
public enum DTHubLLMAnswer: Equatable, Sendable {
  case text(String)
  /// The app's reason (no model chosen, not enough memory, the model is not in the folder…) or "No answer."
  case failure(String)
}

/// The app side of the channel, given to the plug-in at start.
@MainActor
public final class DTHubHost {
  private let object: NSObject

  init(object: NSObject) { self.object = object }

  /// Sends a JSON message to the app and waits for its JSON answer.
  public func send(_ message: Data) async -> Data? {
    await send(message, timeout: 5)
  }

  /// A question for the language model can take long: it has its own, longer timeout.
  func send(_ message: Data, timeout: Double) async -> Data? {
    await withCheckedContinuation { continuation in
      let once = Once(continuation)
      let reply: @convention(block) (Data) -> Void = { once.finish($0) }
      _ = object.perform(NSSelectorFromString("dthubSend:reply:"), with: message, with: reply)
      Task {
        try? await Task.sleep(for: .seconds(timeout))
        once.finish(nil)
      }
    }
  }

  /// Sends a `contribute` message — `fields`, `loras`, `moodboard`, `startImage`, `pipeline`; every key is
  /// optional (see the README; `preset` names a saved preset applied first) — and returns the app's answer: `{"type":"ok","conflicts":n}` or an `error`.
  public func contribute(_ body: [String: Any]) async -> [String: Any]? {
    await sendJSON(body.merging(["type": "contribute"]) { _, new in new })
  }

  /// Sends a `loraWeights` message: the lowest, default and highest weight the user wants for a LoRA of the server (kept
  /// with the app's LoRA manager data). A nil clears that value. The answer is `{"type":"ok"}` or an `error`.
  public func setLoRAWeights(file: String, min: Double?, base: Double?, max: Double?) async -> [String: Any]? {
    var body: [String: Any] = ["type": "loraWeights", "file": file]
    if let min { body["min"] = min }
    if let base { body["base"] = base }
    if let max { body["max"] = max }
    return await sendJSON(body)
  }

  /// Sends a `presets` message: presets for the app's Preset menu, each `{"name", "fields", "loras"}` (the keys of
  /// `contribute`; the prompt and the negative prompt go in `fields`; a preset has no size), and optionally `model` (a file
  /// name) and `advanced` (an object of advanced values such as `refinerModel` and `refinerStart`). A
  /// name that is in the menu already is never touched. The answer is `{"type":"ok","added":n,"existing":m}`.
  public func registerPresets(_ presets: [[String: Any]]) async -> [String: Any]? {
    await sendJSON(["type": "presets", "presets": presets])
  }

  /// Asks the app's language model, which answers in its own time (it may have to load first). Nil when
  /// there is no answer: no model chosen, the plug-in not active, a timeout. `system` is the system prompt;
  /// `model` the name of a model of `DTHubContext.languageModels` to use instead of the one the user chose.
  public func askLanguageModel(
    _ prompt: String, images: [String] = [], system: String? = nil, model: String? = nil,
    options: DTHubLLMOptions = DTHubLLMOptions(), history: [DTHubLLMTurn] = []
  ) async -> String? {
    if case .text(let text) = await askLanguageModelAnswer(
      prompt, images: images, system: system, model: model, options: options, history: history)
    {
      return text
    }
    return nil
  }

  /// Like `askLanguageModel`, with the app's reason when there is no answer.
  public func askLanguageModelAnswer(
    _ prompt: String, images: [String] = [], system: String? = nil, model: String? = nil,
    options: DTHubLLMOptions = DTHubLLMOptions(), history: [DTHubLLMTurn] = []
  ) async -> DTHubLLMAnswer {
    let message = Self.llmMessage(
      prompt: prompt, images: images, system: system, model: model, options: options, history: history)
    guard let answer = await sendJSON(message, timeout: options.effectiveTimeout) else { return .failure("No answer.") }
    if answer["type"] as? String == "llm", let text = answer["text"] as? String { return .text(text) }
    return .failure(answer["text"] as? String ?? "No answer.")
  }

  /// The `llm` message: the keys that are not set are left out, so the app asks as it always did.
  nonisolated static func llmMessage(
    prompt: String, images: [String], system: String?, model: String?, options: DTHubLLMOptions,
    history: [DTHubLLMTurn] = []
  ) -> [String: Any] {
    var message: [String: Any] = ["type": "llm", "prompt": prompt, "images": images]
    if let system, !system.isEmpty { message["system"] = system }
    if let model, !model.isEmpty { message["model"] = model }
    let optionsJSON = options.json
    if !optionsJSON.isEmpty { message["options"] = optionsJSON }
    if !history.isEmpty { message["messages"] = history.map { ["role": $0.role.rawValue, "text": $0.text] } }
    return message
  }

  func sendJSON(_ body: [String: Any], timeout: Double = 5) async -> [String: Any]? {
    guard let data = try? JSONSerialization.data(withJSONObject: body), let reply = await send(data, timeout: timeout)
    else { return nil }
    return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
  }

  /// Asks the app to show a line to the user.
  public func notice(_ text: String, isError: Bool = false) {
    let body: [String: Any] = ["type": "notice", "text": text, "isError": isError]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    Task { _ = await send(data) }
  }
}

final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data?, Never>?

  init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

  func finish(_ data: Data?) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: data)
  }
}

/// A DT Hub plug-in.
@MainActor
public protocol DTHubPlugin: AnyObject {
  var manifest: DTHubManifest { get }
  /// The tab of the plug-in (usually an `NSHostingController` with a SwiftUI view).
  func makeViewController() -> NSViewController
  /// Called once, after the manifest and the view are made.
  func start(host: DTHubHost)
  /// A message from the app; the answer is JSON (nil = `{"type":"ok"}`). An unknown type should
  /// get `nil` or `{"type":"unsupported"}`.
  func handle(_ message: Data) async -> Data?
}

/// The principal class of a plug-in bundle. Subclass it, give the subclass an Objective-C name
/// (`@objc(MyPluginEntry)`), put that name in `NSPrincipalClass`, and override `makePlugin()`.
@MainActor
open class DTHubPluginEntry: NSObject {
  private var plugin: (any DTHubPlugin)?

  public required override init() { super.init() }

  open func makePlugin() -> any DTHubPlugin { fatalError("override makePlugin()") }

  private func made() -> any DTHubPlugin {
    if let plugin { return plugin }
    let plugin = makePlugin()
    self.plugin = plugin
    return plugin
  }

  @objc public func dthubManifest() -> Data {
    (try? JSONEncoder().encode(made().manifest)) ?? Data()
  }

  @objc public func dthubMakeViewController() -> NSViewController {
    made().makeViewController()
  }

  @objc public func dthubStart(_ host: NSObject) {
    made().start(host: DTHubHost(object: host))
  }

  @objc public func dthubHandle(_ message: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    let plugin = made()
    Task { @MainActor in
      reply(await plugin.handle(message) ?? DTHubMessage.bare("ok"))
    }
  }
}
