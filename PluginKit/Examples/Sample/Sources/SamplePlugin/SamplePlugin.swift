import AppKit
import DTHubPluginKit
import SwiftUI

#if SAMPLE_B
  /// The second sample: other identifier and values, so that two plug-ins can contribute the same field.
  private enum Variant {
    static let id = "com.example.dthub.sample.b"
    static let name = "Sample B"
    /// The prefix of the names of its presets (2–4 letters): the Preset menu shows nothing else about where a preset comes from.
    static let acronym = "SMB"
    static let symbol = "star.fill"
    static let prompt = "a lighthouse in a storm, dramatic light"
    static let steps = 8
    static let guidance = 2.0
    static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  }
#else
  private enum Variant {
    static let id = "com.example.dthub.sample"
    static let name = "Sample"
    /// The prefix of the names of its presets (2–4 letters): the Preset menu shows nothing else about where a preset comes from.
    static let acronym = "SMP"
    static let symbol = "star"
    static let prompt = "match light direction, colors and intensity from the reference image 2"
    static let steps = 4
    static let guidance = 1.0
    static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  }
#endif

@MainActor
final class SampleState: ObservableObject {
  @Published var model = "—"
  @Published var active = false
  @Published var azimuth = 45.0
  @Published var overcast = false
  @Published var answer = ""
  @Published var status = ""
  /// The folder the app lends for exchanging pictures (from the `context` message).
  var tempFolder: String?
}

@MainActor
final class SamplePlugin: DTHubPlugin {
  let manifest = DTHubManifest(id: Variant.id, name: Variant.name, version: "1.3", symbol: Variant.symbol)
  private let state = SampleState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: SampleView(
        state: state, sendPlain: { [weak self] in await self?.sendPlain() },
        sendPipeline: { [weak self] in await self?.sendPipeline() },
        sendStartImage: { [weak self] in await self?.sendStartImage() },
        askModel: { [weak self] in await self?.askModel() }))
  }

  func start(host: DTHubHost) {
    self.host = host
    host.notice("\(Variant.name) plug-in started")
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.model = context.model ?? "—"
        state.tempFolder = context.tempFolder
      }
      return nil
    case "activate":
      state.active = true
      // The app only listens to a plug-in that is on: the presets are offered now.
      Task { await registerPresets() }
      return nil
    case "deactivate":
      state.active = false
      return nil
    case "press":
      // For tests and scripts: the same as pressing a button of the tab. The answer comes when the app has answered.
      let button = (try? JSONSerialization.jsonObject(with: message) as? [String: Any])?["button"] as? String
      switch button {
      case "plain": await sendPlain()
      case "pipeline": await sendPipeline()
      case "presets": await registerPresets()
      case "startImage": await sendStartImage()
      case "ask": await askModel()
      default: return DTHubMessage.bare("unsupported")
      }
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  // MARK: Contributions

  /// The sphere, written into the folder the app lent us.
  private func spherePath() -> String? {
    guard let folder = state.tempFolder, let data = SphereImage.png(azimuth: state.azimuth) else { return nil }
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let path = (folder as NSString).appendingPathComponent("\(Variant.id)-sphere.png")
    return (try? data.write(to: URL(fileURLWithPath: path))) == nil ? nil : path
  }

  /// The settings of the sun-direction passes of the Light Direction companion script.
  private func sunFields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": Variant.steps, "guidanceScale": Variant.guidance, "shift": 3, "sampler": 16,
      "batchSize": 1, "batchCount": 1, "cfgZeroStar": false,
    ]
  }

  private var sunLora: [String: Any] { ["file": Variant.lora, "weight": 0.6] }

  private var overcastPreset: String { "\(Variant.acronym) · Overcast" }
  private var matchPreset: String { "\(Variant.acronym) · Match the sun" }

  /// The two presets of the pipeline, in the app's Preset menu: the user sees them, changes them (the LoRA
  /// weight, the steps…) and saves them under the same name. The app never overwrites a name it has.
  func registerPresets() async {
    let answer = await host?.registerPresets([
      ["name": overcastPreset, "fields": sunFields(prompt: "make it an overcast day, remove the shadows")],
      ["name": matchPreset, "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora]],
    ])
    if let answer, answer["type"] as? String == "error" { state.status = answer["text"] as? String ?? "Error" }
  }

  /// A prompt, parameters, a LoRA and a picture for the Moodboard.
  func sendPlain() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    let answer = await host?.contribute([
      "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora],
      "moodboard": [["name": "Sphere light", "path": sphere]],
    ])
    report(answer)
  }

  /// The two passes of the script, as presets: flatten the shadows (optional), then match the sun with the
  /// sphere in the Moodboard and the first pass's picture as the start image.
  func sendPipeline() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    await registerPresets()
    var steps: [[String: Any]] = []
    if state.overcast { steps.append(["title": "Overcast", "preset": overcastPreset]) }
    steps.append([
      "title": "Match the sun", "preset": matchPreset, "moodboard": [["name": "Sphere light", "path": sphere]],
      "useOutputAsStart": state.overcast,
    ])
    report(await host?.contribute(["pipeline": ["name": "Sun direction", "steps": steps]]))
  }

  func sendStartImage() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    report(await host?.contribute(["startImage": ["name": "Sphere light", "path": sphere]]))
  }

  /// A question for the language model; the answer is shown, and sent as the prompt.
  func askModel() async {
    state.status = "Asking the language model…"
    // `system` and `options` are optional: a system prompt, and how the model should write.
    let answer = await host?.askLanguageModelAnswer(
      "Describe a quiet harbour at dawn.", system: "Answer with one short sentence, in English.",
      options: DTHubLLMOptions(temperature: 0.7, maxTokens: 120))
    guard case .text(let text)? = answer else {
      if case .failure(let reason)? = answer { return state.status = reason }
      return state.status = "No answer: is a language model chosen, and is this plug-in on?"
    }
    state.answer = text
    report(await host?.contribute(["fields": ["prompt": text]]))
  }

  private func report(_ answer: [String: Any]?) {
    guard let answer else { return state.status = "No answer from the app." }
    if answer["type"] as? String == "error" { return state.status = answer["text"] as? String ?? "Error" }
    let conflicts = answer["conflicts"] as? Int ?? 0
    state.status = conflicts > 0 ? "Sent. \(conflicts) conflict(s) waiting in the app." : "Sent."
  }
}

struct SampleView: View {
  @ObservedObject var state: SampleState
  let sendPlain: () async -> Void
  let sendPipeline: () async -> Void
  let sendStartImage: () async -> Void
  let askModel: () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(Variant.name) plug-in 1.3").font(.title2)
      Text("Model: \(state.model)")
      Text(state.active ? "active" : "not active").foregroundStyle(.secondary)
      Divider()
      HStack {
        Text("Light from")
        Slider(value: $state.azimuth, in: 0...360)
        Text("\(Int(state.azimuth))°").monospacedDigit().frame(width: 44, alignment: .trailing)
      }
      Toggle("Overcast shadows (adds a pass)", isOn: $state.overcast)
      HStack {
        Button("Send prompt, parameters and sphere") { Task { await sendPlain() } }
        Button("Send pipeline") { Task { await sendPipeline() } }
        Button("Send start image") { Task { await sendStartImage() } }
      }
      Divider()
      Button("Ask the language model") { Task { await askModel() } }
      if !state.answer.isEmpty { Text(state.answer).font(.callout).textSelection(.enabled) }
      if !state.status.isEmpty { Text(state.status).font(.caption).foregroundStyle(.secondary) }
      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#if SAMPLE_B
  @objc(SampleBEntry)
  public final class SampleBEntry: DTHubPluginEntry {
    public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
  }
#else
  @objc(SampleEntry)
  public final class SampleEntry: DTHubPluginEntry {
    public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
  }
#endif
