import CoreGraphics
import DTHubPluginKit
import Foundation

/// What the tab shows before the job starts: the size the picture will have, and how many tiles and passes it takes.
struct TUSummary: Equatable, Sendable {
  let width: Int
  let height: Int
  let columns: Int
  let rows: Int
  let passes: Int
  let verdict: TileLimits.Verdict
  /// True when the enlarged picture is cut a little to make its sides multiples of 64.
  let cropped: Bool

  static func make(sourceWidth: Int, sourceHeight: Int, factor: Int, overlap: TileOverlap) -> TUSummary {
    let scaled = TileGrid.scaledSize(width: sourceWidth, height: sourceHeight, factor: factor)
    let plan = TileGrid.plan(width: scaled.width, height: scaled.height, overlap: overlap)
    return TUSummary(
      width: scaled.width, height: scaled.height, columns: plan.columns, rows: plan.rows, passes: plan.count,
      verdict: TileLimits.verdict(width: scaled.width, height: scaled.height, passes: plan.count),
      cropped: scaled.width != sourceWidth * factor || scaled.height != sourceHeight * factor)
  }
}

/// The tab: the picture, the three choices, the summary, and the enlargement from the preparation to the saved file.
@MainActor
final class TUState: ObservableObject {
  @Published var factor: Int { didSet { choiceChanged() } }
  @Published var overlap: TileOverlap { didSet { choiceChanged() } }
  @Published var loraWeight: Double { didSet { choiceChanged() } }
  @Published private(set) var image: CGImage?
  @Published private(set) var imageName = ""
  @Published private(set) var notice: String?
  @Published private(set) var isPrepared = false
  @Published private(set) var resultURL: URL?
  /// True after Prepare was pressed on a big job: the next press confirms it.
  @Published private(set) var awaitingConfirmation = false
  @Published var active = false
  /// The model family the header has (`context.family`).
  @Published var family: String?
  /// The folder the app lends for picture files; nil until the first `context`.
  var tempFolder: String?
  /// The trigger word of each LoRA of the server, by file (`context.loraCatalog`).
  var loraTriggers: [String: String] = [:]
  /// Where the enlarged picture is saved.
  var desktopFolder: URL = TUDesktopSaver.desktopFolder

  private var store: TUStore
  private let italian: Bool
  private var loadingChoice = false
  private var session: TUSession?

  init(store: TUStore, italian: Bool = L.systemIsItalian) {
    self.store = store
    self.italian = italian
    let choice = store.load()
    self.factor = choice.factor
    self.overlap = TileOverlap(rawValue: choice.overlap) ?? .standard
    self.loraWeight = choice.loraWeight
  }

  static func text(_ key: L.Key, italian: Bool) -> String { L.text(key, italian: italian) }
  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }
  func format(_ key: L.Key, _ args: CVarArg...) -> String {
    String(format: L.text(key, italian: italian), arguments: args)
  }

  // MARK: What the tab says

  var preset: TUPreset? { TUPresetTable.preset(forFamily: family) }

  var summary: TUSummary? {
    guard let image else { return nil }
    return TUSummary.make(sourceWidth: image.width, sourceHeight: image.height, factor: factor, overlap: overlap)
  }

  var canPrepare: Bool { preset != nil && image != nil && summary?.verdict != .refuse }
  var needsConfirmation: Bool { summary?.verdict == .warn }

  /// A message of an action, else the warning about the model or the size.
  var status: String {
    if let notice { return notice }
    if image != nil, preset == nil { return text(.unsupportedModel) }
    switch summary?.verdict {
    case .refuse?: return text(.tooBig)
    case .warn?: return text(.bigJob)
    default: return ""
    }
  }

  // MARK: The picture and the choices

  func setImage(_ loaded: CGImage, name: String) {
    image = loaded
    imageName = name
    notice = nil
    isPrepared = false
    awaitingConfirmation = false
    session = nil
  }

  func setImage(data: Data, name: String) {
    guard let loaded = TUImage.load(data: data) else {
      notice = text(.unreadableImage)
      return
    }
    setImage(loaded, name: name)
  }

  func setImage(file: URL) {
    guard let loaded = TUImage.load(file) else {
      notice = text(.unreadableImage)
      return
    }
    setImage(loaded, name: file.lastPathComponent)
  }

  func dropHadNoPicture() { notice = text(.unreadableImage) }

  private func choiceChanged() {
    isPrepared = false
    awaitingConfirmation = false
    notice = nil
    guard !loadingChoice else { return }
    store.save(TUChoice(factor: factor, overlap: overlap.rawValue, loraWeight: loraWeight))
  }

  func switchProject(folder: URL) {
    store.folder = folder
    let choice = store.load()
    loadingChoice = true
    factor = choice.factor
    overlap = TileOverlap(rawValue: choice.overlap) ?? .standard
    loraWeight = choice.loraWeight
    loadingChoice = false
    image = nil
    imageName = ""
    notice = nil
    isPrepared = false
    resultURL = nil
    awaitingConfirmation = false
    session = nil
  }

  func apply(context data: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: data) else { return }
    tempFolder = context.tempFolder
    family = context.family
    loraTriggers = Dictionary(
      (context.loraCatalog ?? []).filter { !$0.trigger.isEmpty }.map { ($0.file, $0.trigger) }, uniquingKeysWith: { first, _ in first })
  }

  // MARK: Preparing and the session

  /// A session for the picture and the choices, or nil without a picture, a preset or a folder.
  func makeSession() -> TUSession? {
    guard let image, let preset else { return nil }
    let folder = URL(fileURLWithPath: tempFolder ?? NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("tiled-upscale", isDirectory: true)
    return TUSession(
      source: image, factor: factor, overlap: overlap, loraWeight: loraWeight,
      trigger: loraTriggers[preset.loraFile] ?? "", preset: preset, tempFolder: folder)
  }

  /// Registers the preset and proposes the guided pipeline to the app; the user then presses RUN. `contribute` and
  /// `registerPreset` talk to the app (a test gives its own).
  func prepare(
    confirmed: Bool, contribute: ([String: Any]) async -> [String: Any]?,
    registerPreset: ([String: Any]) async -> [String: Any]?
  ) async {
    guard canPrepare, let preset, let summary else { return }
    if needsConfirmation && !confirmed {
      awaitingConfirmation = true
      notice = text(.bigJob)
      return
    }
    guard let session = makeSession() else { return }
    let trigger = loraTriggers[preset.loraFile] ?? ""
    let fields = preset.fields(prompt: TUPrompt.text(trigger: trigger))
    let loras = preset.loras(weight: loraWeight)
    _ = await registerPreset(["name": preset.name, "fields": fields, "loras": loras])
    let estimate: [String: Any] = [
      "preset": preset.name, "fields": fields, "loras": loras,
      "size": [
        "width": min(TileConstants.tile, summary.width), "height": min(TileConstants.tile, summary.height),
      ],
    ]
    let pipeline: [String: Any] = ["name": "Tiled Upscale", "guided": true, "passes": summary.passes, "estimate": estimate]
    guard let answer = await contribute(["pipeline": pipeline]), answer["type"] as? String != "error" else {
      notice = text(.notAnswered)
      return
    }
    self.session = session
    resultURL = nil
    notice = text(.prepared)
    awaitingConfirmation = false
    isPrepared = true
  }

  /// The app asks for the next pass (`session.next`). The picture work runs off the main actor.
  func sessionNext(_ message: Data) async -> Data {
    guard let session, let request = TUMessages.parseNext(message) else { return TUMessages.done }
    return await Task.detached(priority: .userInitiated) { session.next(request) }.value
  }

  /// The pipeline is over (`session.end`): a finished one is saved on the Desktop.
  func sessionEnded(reason: String) async {
    guard let session else { return }
    let composed = await Task.detached(priority: .userInitiated) { session.end(reason) }.value
    let problem = session.problem
    self.session = nil
    isPrepared = false
    switch reason {
    case "finished":
      if let problem {
        notice = format(.failed, problem)
      } else if let composed, let png = TUImage.pngData(composed) {
        do {
          let url = try TUDesktopSaver.save(png, in: desktopFolder)
          resultURL = url
          notice = format(.savedOnDesktop, url.lastPathComponent)
          if let tempFolder {
            try? png.write(to: URL(fileURLWithPath: tempFolder).appendingPathComponent("tiled-upscale-result.png"))
          }
        } catch {
          notice = format(.saveFailed, error.localizedDescription)
        }
      }
    case "stopped": notice = text(.stopped)
    case "closed": notice = text(.closed)
    default: notice = format(.failed, problem ?? reason)
    }
  }

  /// The picture saved, as the start image of the Control tab.
  func useAsStart(contribute: ([String: Any]) async -> [String: Any]?) async {
    guard let tempFolder else {
      notice = text(.noFolder)
      return
    }
    let path = URL(fileURLWithPath: tempFolder).appendingPathComponent("tiled-upscale-result.png").path
    guard FileManager.default.fileExists(atPath: path) else { return }
    let name = resultURL?.lastPathComponent ?? "Tiled Upscale"
    if await contribute(["startImage": ["path": path, "name": name]]) == nil { notice = text(.notAnswered) }
  }
}
