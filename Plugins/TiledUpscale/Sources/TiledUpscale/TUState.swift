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
  /// What the model will make in all, in megapixels: the area of every tile, the overlaps counted each time. A rough measure of the
  /// time (it grows faster than this with the size of a tile): the number to compare between two tile sizes.
  let generatedMegapixels: Double
  /// True when the enlarged picture is cut a little to make its sides multiples of 64.
  let cropped: Bool

  static func make(
    sourceWidth: Int, sourceHeight: Int, factor: Int, overlap: TileOverlap, tile: Int = TileConstants.tile
  ) -> TUSummary {
    let scaled = TileGrid.scaledSize(width: sourceWidth, height: sourceHeight, factor: factor)
    let plan = TileGrid.plan(width: scaled.width, height: scaled.height, overlap: overlap, tile: tile)
    return TUSummary(
      width: scaled.width, height: scaled.height, columns: plan.columns, rows: plan.rows, passes: plan.count,
      verdict: TileLimits.verdict(width: scaled.width, height: scaled.height, passes: plan.count),
      generatedMegapixels: Double(plan.tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }) / 1_000_000,
      cropped: scaled.width != sourceWidth * factor || scaled.height != sourceHeight * factor)
  }
}

/// The tab: the picture, the three choices, the summary, and the enlargement from the preparation to the saved file.
@MainActor
final class TUState: ObservableObject {
  /// The enlargements the tab offers.
  static let factors = TUSettings.factors

  @Published var factor: Int {
    didSet {
      if !loadingChoice { autoSizeTile() }
      choiceChanged(changesPicture: true)
    }
  }
  @Published var overlap: TileOverlap {
    didSet {
      if !loadingChoice {
        // The free part of the advanced values goes back to the one of this overlap; the other values stay.
        var next = settings
        next.free = TUSettings.defaultFree(for: overlap)
        settings = next
        autoSizeTile()
      }
      settings = settings.clamped(overlap: overlap)
      choiceChanged(changesPicture: true)
    }
  }
  /// The mask and the join: the free part, Draw Things' blur and outset, the fade of the join.
  @Published private(set) var settings: TUSettings
  /// The LoRA strength by preset name; see `loraWeight`.
  @Published private(set) var loraWeights: [String: Double]
  /// The LoRA strength of the preset of the model in the header: the one the user chose, else the preset's own default. Each
  /// preset keeps its own (Qwen's LoRA works at 2.5, FLUX's at 1).
  var loraWeight: Double {
    get { loraWeights[preset?.name ?? ""] ?? preset?.defaultLoRAWeight ?? 1 }
    set {
      let range = TUPresetTable.loraWeightRange
      var next = loraWeights
      next[preset?.name ?? ""] = min(max(newValue, range.lowerBound), range.upperBound)
      loraWeights = next
      choiceChanged(changesPicture: false)
    }
  }
  /// The user's instructions, added to the prompt of every tile. Changing them does not touch a prepared or running session: the
  /// next tile just reads the new text.
  @Published var extraPrompt: String {
    didSet {
      session?.extraPrompt = promptExtra
      persist()
    }
  }
  /// Instructions for the tile that is made again, after the general ones.
  @Published var tileExtra = ""
  /// The tile picked in the preview to be made again, nil when none.
  @Published private(set) var selectedTile: Int?
  /// True when a run finished and the picture is kept, so a tile can be made again.
  @Published private(set) var canRegenerate = false
  /// The tile the prepared pipeline makes again, nil for a whole enlargement.
  @Published private(set) var regeneratingTile: Int?
  @Published private(set) var image: CGImage?
  @Published private(set) var imageName = ""
  @Published private(set) var notice: String?
  @Published private(set) var isPrepared = false
  /// True when the enlarged picture was handed to the app as a result and is waiting there for the user.
  @Published private(set) var resultReady = false
  /// The enlarged picture, small, for the preview; nil without a picture.
  @Published private(set) var previewBase: CGImage?
  /// The tiles that are back, small, over a transparent picture; nil before the first one.
  @Published private(set) var previewProgress: CGImage?
  @Published private(set) var tilesDone = 0
  /// True after Prepare was pressed on a big job: the next press confirms it.
  @Published private(set) var awaitingConfirmation = false
  @Published var active = false
  /// The model family the header has (`context.family`) and the file of its model (`context.model`).
  @Published var family: String?
  @Published var model: String?
  /// The folder the app lends for picture files; nil until the first `context`.
  var tempFolder: String?
  /// The trigger word of each LoRA of the server, by file (`context.loraCatalog`).
  var loraTriggers: [String: String] = [:]
  /// Sends a `contribute` message to the app (the plug-in gives it at start; a test gives its own).
  var contribute: (([String: Any]) async -> [String: Any]?)?

  var maskFree: Int {
    get { settings.free }
    set { change { $0.free = newValue } }
  }
  var maskBlur: Double {
    get { settings.blur }
    set { change { $0.blur = newValue } }
  }
  var maskOutset: Int {
    get { settings.outset }
    set { change { $0.outset = newValue } }
  }
  var tileSize: Int {
    get { settings.tile }
    set { change { $0.tile = newValue } }
  }
  var toneStrength: Int {
    get { settings.toneStrength }
    set { change { $0.toneStrength = newValue } }
  }
  var toneRadius: Int {
    get { settings.toneRadius }
    set { change { $0.toneRadius = newValue } }
  }
  var junctionFade: Int {
    get { settings.fade }
    set { change { $0.fade = newValue } }
  }
  /// What the fade can be now: what the free part leaves of the overlap.
  var fadeRange: ClosedRange<Int> { 0...max(0, overlap.rawValue - settings.free) }

  /// The tile for the picture as it is now: the smallest that needs at most three along its shorter side (`TUSettings.autoTile`).
  /// It runs when the picture, the enlargement or the overlap change; the slider can then be moved by hand.
  private func autoSizeTile() {
    guard let image else { return }
    let scaled = TileGrid.scaledSize(width: image.width, height: image.height, factor: factor)
    var next = settings
    next.tile = TUSettings.autoTile(shortestSide: min(scaled.width, scaled.height), overlap: overlap)
    settings = next.clamped(overlap: overlap)
  }

  /// The values of the advanced section back to the defaults of the overlap (the tile size is not one of them).
  func resetAdvanced() {
    var next = TUSettings.defaults(for: overlap)
    next.tile = settings.tile
    settings = next.clamped(overlap: overlap)
    dropSession()
    choiceChanged(changesPicture: false)
  }

  private func change(_ edit: (inout TUSettings) -> Void) {
    var next = settings
    edit(&next)
    settings = next.clamped(overlap: overlap)
    dropSession()
    choiceChanged(changesPicture: false)
  }

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
    self.loraWeights = choice.loraWeights
    self.settings = choice.settings
    self.extraPrompt = choice.extraPrompt
  }

  static func text(_ key: L.Key, italian: Bool) -> String { L.text(key, italian: italian) }
  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }
  func format(_ key: L.Key, _ args: CVarArg...) -> String {
    String(format: L.text(key, italian: italian), arguments: args)
  }

  // MARK: What the tab says

  var preset: TUPreset? { TUPresetTable.preset(forFamily: family, model: model) }

  var summary: TUSummary? {
    guard let image else { return nil }
    return TUSummary.make(
      sourceWidth: image.width, sourceHeight: image.height, factor: factor, overlap: overlap, tile: settings.tile)
  }

  /// The tiles of the picture as it is now, for the grid of the preview.
  var plan: TilePlan? {
    guard let summary else { return nil }
    return TileGrid.plan(width: summary.width, height: summary.height, overlap: overlap, free: settings.free, tile: settings.tile)
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
    dropSession()
    autoSizeTile()
    resetPreview()
  }

  /// A new base for the preview (the picture or the enlargement changed) and no tiles back.
  private func resetPreview() {
    tilesDone = 0
    previewProgress = nil
    guard let image else {
      previewBase = nil
      return
    }
    let scaled = TileGrid.scaledSize(width: image.width, height: image.height, factor: factor)
    previewBase = TUPreview.base(of: image, factor: factor, size: scaled)
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

  /// A choice changed: what was prepared is out of date. The preview is drawn again only when the picture it shows
  /// changes (the enlargement, the overlap), not for the strength of the LoRA.
  private func choiceChanged(changesPicture: Bool) {
    isPrepared = false
    awaitingConfirmation = false
    notice = nil
    if changesPicture { resetPreview() }
    if changesPicture { dropSession() }
    persist()
  }

  private func persist() {
    guard !loadingChoice else { return }
    store.save(
      TUChoice(
        factor: factor, overlap: overlap.rawValue, loraWeight: loraWeights[""] ?? 1, settings: settings, loraWeights: loraWeights,
        extraPrompt: extraPrompt))
  }

  /// The general and the tile's instructions, as one text.
  private var promptExtra: String {
    let general = extraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard regeneratingTile != nil else { return general }
    let own = tileExtra.trimmingCharacters(in: .whitespacesAndNewlines)
    return [general, own].filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// The finished picture and the choice of a tile are given up (the picture, the grid or the settings changed under them).
  private func dropSession() {
    session = nil
    canRegenerate = false
    selectedTile = nil
    regeneratingTile = nil
    tileExtra = ""
  }

  func switchProject(folder: URL) {
    store.folder = folder
    let choice = store.load()
    loadingChoice = true
    factor = choice.factor
    overlap = TileOverlap(rawValue: choice.overlap) ?? .standard
    loraWeights = choice.loraWeights
    settings = choice.settings
    extraPrompt = choice.extraPrompt
    loadingChoice = false
    image = nil
    imageName = ""
    notice = nil
    isPrepared = false
    resultReady = false
    awaitingConfirmation = false
    dropSession()
    resetPreview()
  }

  func apply(context data: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: data) else { return }
    tempFolder = context.tempFolder
    family = context.family
    model = context.model
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
      source: image, factor: factor, overlap: overlap, settings: settings, loraWeight: loraWeight,
      trigger: loraTriggers[preset.loraFile] ?? "", extraPrompt: extraPrompt, preset: preset, tempFolder: folder)
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
    let fields = preset.fields(prompt: session.prompt)
    let loras = preset.loras(weight: loraWeight)
    _ = await registerPreset(["name": preset.name, "fields": fields, "loras": loras])
    let estimate: [String: Any] = [
      "preset": preset.name, "fields": fields, "loras": loras,
      "size": [
        "width": min(settings.tile, summary.width), "height": min(settings.tile, summary.height),
      ],
    ]
    let pipeline: [String: Any] = ["name": "Tiled Upscale", "guided": true, "passes": summary.passes, "estimate": estimate]
    guard let answer = await contribute(["pipeline": pipeline]), answer["type"] as? String != "error" else {
      notice = text(.notAnswered)
      return
    }
    dropSession()
    self.session = session
    tilesDone = 0
    previewProgress = nil
    resultReady = false
    notice = text(.prepared)
    awaitingConfirmation = false
    isPrepared = true
  }

  /// The app asks for the next pass (`session.next`). The picture work runs off the main actor.
  func sessionNext(_ message: Data) async -> Data {
    guard let session, let request = TUMessages.parseNext(message) else { return TUMessages.done }
    session.extraPrompt = promptExtra
    let answer = await Task.detached(priority: .userInitiated) { session.next(request) }.value
    // A result that came back is on the preview now.
    if session.completedTiles != tilesDone {
      tilesDone = session.completedTiles
      previewProgress = session.previewImage()
    }
    return answer
  }

  /// The pipeline is over (`session.end`): a finished one is saved on the Desktop. `previous` is the last tile's result, which the
  /// app sends here because it does not ask again after the last pass.
  func sessionEnded(reason: String, previous: TUNextRequest.Previous? = nil) async {
    guard let session else { return }
    session.extraPrompt = promptExtra
    let composed = await Task.detached(priority: .userInitiated) { session.end(reason, previous: previous) }.value
    let problem = session.problem
    // The last tile is back now: the preview shows it too.
    tilesDone = session.completedTiles
    previewProgress = session.previewImage()
    regeneratingTile = nil
    isPrepared = false
    // A picture that is whole is kept for making a tile again; any other end drops it.
    canRegenerate = session.isComplete
    if !session.isComplete {
      self.session = nil
      selectedTile = nil
    }
    switch reason {
    case "finished":
      if let problem {
        notice = format(.failed, problem)
      } else if let composed, let png = TUImage.pngData(composed) {
        await handOver(png)
      }
    case "stopped": notice = text(.stopped)
    case "closed": notice = text(.closed)
    default: notice = format(.failed, problem ?? reason)
    }
  }

  // MARK: Making a tile again

  /// Picks the tile under a point of the preview (a fraction of its width and height); a tap on the picked tile lets it go.
  func selectTile(atX fx: Double, y fy: Double) {
    guard canRegenerate, let plan = session?.plan else { return }
    let x = fx * Double(plan.width)
    let y = fy * Double(plan.height)
    // Tiles overlap: the one whose centre is nearest is the one the point is "in".
    let hit = plan.tiles.filter {
      x >= Double($0.rect.x) && x < Double($0.rect.x + $0.rect.width) && y >= Double($0.rect.y) && y < Double($0.rect.y + $0.rect.height)
    }
    .min { distance($0, x, y) < distance($1, x, y) }
    selectedTile = hit?.index == selectedTile ? nil : hit?.index
  }

  private func distance(_ tile: Tile, _ x: Double, _ y: Double) -> Double {
    let dx = Double(tile.rect.x) + Double(tile.rect.width) / 2 - x
    let dy = Double(tile.rect.y) + Double(tile.rect.height) / 2 - y
    return dx * dx + dy * dy
  }

  /// The name of the picked tile ("2B"), nil when none.
  var selectedTileName: String? {
    guard let selectedTile, let tile = session?.plan.tiles[safe: selectedTile] else { return nil }
    return TUSession.name(of: tile)
  }

  /// Proposes a one-pass guided pipeline that makes the picked tile again, from the original; the user then presses RUN.
  func prepareRegeneration(
    contribute: ([String: Any]) async -> [String: Any]?, registerPreset: ([String: Any]) async -> [String: Any]?
  ) async {
    guard canRegenerate, let session, let index = selectedTile, let tile = session.plan.tiles[safe: index] else { return }
    let preset = session.preset
    let weight = loraWeights[preset.name] ?? preset.defaultLoRAWeight
    regeneratingTile = index
    guard session.beginRegeneration(of: index, loraWeight: weight, extraPrompt: promptExtra) else {
      regeneratingTile = nil
      return
    }
    let fields = preset.fields(prompt: session.prompt)
    let loras = preset.loras(weight: weight)
    _ = await registerPreset(["name": preset.name, "fields": fields, "loras": loras])
    let estimate: [String: Any] = [
      "preset": preset.name, "fields": fields, "loras": loras,
      "size": ["width": tile.rect.width, "height": tile.rect.height],
    ]
    let pipeline: [String: Any] = ["name": "Tiled Upscale", "guided": true, "passes": 1, "estimate": estimate]
    guard let answer = await contribute(["pipeline": pipeline]), answer["type"] as? String != "error" else {
      session.cancelRegeneration()
      regeneratingTile = nil
      notice = text(.notAnswered)
      return
    }
    resultReady = false
    isPrepared = true
    notice = format(.regenerationPrepared, TUSession.name(of: tile))
  }

  /// The composed picture goes to the app as a result: written in the plug-in's folder and described by its enlargement,
  /// tiles and LoRA strength. The app keeps it in the project's folder and in the Results strip.
  private func handOver(_ png: Data) async {
    guard let tempFolder, let summary else {
      notice = text(.noFolder)
      return
    }
    let url = URL(fileURLWithPath: tempFolder).appendingPathComponent("tiled-upscale-result.png")
    do {
      try png.write(to: url)
    } catch {
      notice = format(.resultNotAdded, error.localizedDescription)
      return
    }
    let description = format(
      .resultDescription, factor, summary.columns, summary.rows, loraWeight, settings.tile, settings.free,
      Int(settings.blur.rounded()), settings.outset, settings.fade, settings.toneStrength, settings.toneRadius)
    let message: [String: Any] = ["result": ["path": url.path, "name": "Tiled Upscale", "description": description]]
    guard let answer = await contribute?(message) else {
      notice = text(.notAnswered)
      return
    }
    if let problems = answer["problems"] as? [String], let first = problems.first {
      notice = format(.resultNotAdded, first)
    } else {
      resultReady = true
      notice = text(.addedToResults)
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
    let name = "Tiled Upscale"
    if await contribute(["startImage": ["path": path, "name": name]]) == nil { notice = text(.notAnswered) }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
