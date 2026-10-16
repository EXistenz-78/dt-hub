import CoreGraphics
import DTHubPluginKit
import Foundation

/// The tab: the picture, the maps, the model, and what the buttons may do. The work runs off the main actor; a result
/// that comes back after the picture (or the project) changed is thrown away.
@MainActor
final class DPState: ObservableObject {
  enum ModelState: Equatable, Sendable {
    case missing, downloading(Double), ready, damaged
  }

  /// The two checkboxes of the tab.
  @Published var wantsDepth: Bool {
    didSet { if !loadingChoice { store.save(DPSelection(depth: wantsDepth, pose: wantsPose)) } }
  }
  @Published var wantsPose: Bool {
    didSet { if !loadingChoice { store.save(DPSelection(depth: wantsDepth, pose: wantsPose)) } }
  }
  @Published private(set) var image: CGImage?
  @Published private(set) var imageName = ""
  @Published private(set) var depthImage: CGImage?
  @Published private(set) var poseImage: CGImage?
  @Published private(set) var status = ""
  @Published private(set) var modelState: ModelState = .missing
  @Published private(set) var isWorking = false
  /// Whether the plug-in is on for the job (header menu).
  @Published var active = false
  /// The folder the app lends for picture files; nil until the first `context`.
  var tempFolder: String?

  private var store: DPStore
  private let models: DPModelStore
  private let detector: any DPPoseDetecting
  private let makeDepth: @Sendable (URL) throws -> DepthEstimator
  private let italian: Bool
  private var loadingChoice = false
  private var generation = 0
  private var installTask: Task<Void, any Error>?

  init(
    store: DPStore, models: DPModelStore, detector: any DPPoseDetecting,
    makeDepth: @escaping @Sendable (URL) throws -> DepthEstimator, italian: Bool = L.systemIsItalian
  ) {
    self.store = store
    self.models = models
    self.detector = detector
    self.makeDepth = makeDepth
    self.italian = italian
    let selection = store.load()
    self.wantsDepth = selection.depth
    self.wantsPose = selection.pose
  }

  /// Sets both checkboxes at once (one save).
  func select(depth: Bool, pose: Bool) {
    loadingChoice = true
    wantsDepth = depth
    wantsPose = pose
    loadingChoice = false
    store.save(DPSelection(depth: depth, pose: pose))
  }

  /// A word of the tab in the language of the state.
  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }

  // MARK: What the buttons may do

  /// «Downloading… 42%» in the language of the state.
  func downloadingText(_ fraction: Double) -> String {
    L.format(.downloading, Int((fraction * 100).rounded()), italian: italian)
  }

  var depthAvailable: Bool { modelState == .ready }
  var showsDownloadButton: Bool { modelState == .missing || modelState == .damaged }
  var canCreate: Bool {
    image != nil && !isWorking && (wantsDepth || wantsPose) && !(wantsDepth && !wantsPose && !depthAvailable)
  }
  /// A copy on the Desktop needs a map, not the plug-in being on for the job.
  var canSave: Bool { !isWorking && (chosenMaps.depth != nil || chosenMaps.pose != nil) }
  var canSend: Bool { active && !isWorking && (chosenMaps.depth != nil || chosenMaps.pose != nil) }

  /// The maps the checkboxes ask for, among the ones made.
  private var chosenMaps: (depth: CGImage?, pose: CGImage?) {
    (wantsDepth ? depthImage : nil, wantsPose ? poseImage : nil)
  }

  // MARK: The picture

  func setImage(data: Data, name: String) {
    guard let loaded = DPImage.load(data: data) else {
      status = text(.unreadableImage)
      return
    }
    replaceImage(loaded, name: name)
  }

  func setImage(file: URL) {
    guard let loaded = DPImage.load(file: file) else {
      status = text(.unreadableImage)
      return
    }
    replaceImage(loaded, name: file.lastPathComponent)
  }

  /// Something was dropped that is not a picture (an address, text).
  func dropHadNoPicture() { status = text(.unreadableImage) }

  private func replaceImage(_ loaded: CGImage, name: String) {
    generation += 1
    isWorking = false
    image = loaded
    imageName = name
    depthImage = nil
    poseImage = nil
    status = ""
  }

  // MARK: Creating the maps

  func create() async {
    guard let image, !isWorking else { return }
    let token = generation
    var wantDepth = wantsDepth
    let wantPose = wantsPose
    guard wantDepth || wantPose else { return }
    var notes: [String] = []
    if wantDepth && !depthAvailable {
      if !wantPose {
        status = text(.depthMissing)
        return
      }
      wantDepth = false
      notes.append(text(.poseOnlyBecauseNoModel))
    }
    isWorking = true
    status = text(.creating)

    let (models, makeDepth, detector) = (models, makeDepth, detector)
    var depth: CGImage?
    var pose: CGImage?
    var damaged = false
    if wantDepth {
      do {
        depth = try await Task.detached(priority: .userInitiated) {
          try makeDepth(models.compiledURL).depthMap(for: image)
        }.value
      } catch {
        damaged = true
      }
    }
    if wantPose {
      do {
        let people = try await detector.people(in: image)
        pose = DPPoseRenderer.render(people, width: image.width, height: image.height)
        if pose == nil { notes.append(text(.noPerson)) }
      } catch {
        notes.append(text(.unreadableImage))
      }
    }
    guard token == generation else { return }
    isWorking = false
    depthImage = depth
    poseImage = pose
    if damaged {
      modelState = .damaged
      notes.append(text(.modelDamaged))
    }
    status = notes.isEmpty ? text(.created) : notes.joined(separator: " ")
  }

  // MARK: Sending

  /// Writes the chosen maps in the picture folder and contributes them to the Moodboard.
  func send(contribute: @MainActor ([String: Any]) async -> [String: Any]?) async {
    let (depth, pose) = chosenMaps
    guard depth != nil || pose != nil else {
      status = text(.noMapsToSend)
      return
    }
    guard let tempFolder else {
      status = text(.noFolder)
      return
    }
    var depthPath: String?
    var posePath: String?
    do {
      try FileManager.default.createDirectory(atPath: tempFolder, withIntermediateDirectories: true)
      if let depth, let png = DPPoseRenderer.pngData(depth) {
        depthPath = (tempFolder as NSString).appendingPathComponent(DPMessages.depthFile)
        try png.write(to: URL(fileURLWithPath: depthPath!))
      }
      if let pose, let png = DPPoseRenderer.pngData(pose) {
        posePath = (tempFolder as NSString).appendingPathComponent(DPMessages.poseFile)
        try png.write(to: URL(fileURLWithPath: posePath!))
      }
    } catch {
      status = text(.writeFailed)
      return
    }
    let answer = await contribute(["moodboard": DPMessages.moodboard(depthPath: depthPath, posePath: posePath)])
    status = describe(answer)
  }

  /// Saves the chosen maps on the Desktop as "Depth NNN.png" and "Pose NNN.png".
  func saveToDesktop(in folder: URL = DPDesktopSaver.desktopFolder) {
    let (depth, pose) = chosenMaps
    guard depth != nil || pose != nil else {
      status = text(.noMapsToSend)
      return
    }
    var saved: [String] = []
    do {
      if let depth, let png = DPPoseRenderer.pngData(depth) {
        saved.append(try DPDesktopSaver.save(png, prefix: "Depth ", in: folder).lastPathComponent)
      }
      if let pose, let png = DPPoseRenderer.pngData(pose) {
        saved.append(try DPDesktopSaver.save(png, prefix: "Pose ", in: folder).lastPathComponent)
      }
    } catch {
      status = text(.saveFailed)
      return
    }
    status = L.format(.savedDesktop, saved.joined(separator: ", "), italian: italian)
  }

  private func describe(_ answer: [String: Any]?) -> String {
    guard let answer else { return text(.notAnswered) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? text(.notAnswered) }
    if let problems = answer["problems"] as? [String], !problems.isEmpty {
      return L.format(.sentWithProblems, problems.joined(separator: "; "), italian: italian)
    }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : text(.sent)
  }

  // MARK: The model

  /// At launch: forgets what an install cut short left behind; a package someone put in the model folder by hand
  /// (no compiled model yet) is checked and compiled; then looks at the disk.
  func prepare() async {
    let models = models
    await Task.detached {
      models.cleanUpLeftovers()
      if !models.isPresent(), models.hasPackageOnDisk() { try? await models.installLocalPackage(from: models.folder) }
    }.value
    await refreshModelState()
  }

  /// Looks at the disk again (off the main actor: opening the model takes a moment).
  func refreshModelState() async {
    if case .downloading = modelState { return }
    let models = models
    let found = await Task.detached { () -> ModelState in
      if models.isPresent() { return .ready }
      return FileManager.default.fileExists(atPath: models.compiledURL.path) ? .damaged : .missing
    }.value
    if case .downloading = modelState { return }
    modelState = found
  }

  func downloadModel() async {
    if case .downloading = modelState { return }
    modelState = .downloading(0)
    status = ""
    let models = models
    let owner = WeakState(self)
    let task = Task<Void, any Error> {
      try await models.install { progress in
        Task { @MainActor in owner.value?.downloadProgress(progress) }
      }
    }
    installTask = task
    do {
      try await task.value
      installTask = nil
      modelState = .missing
      await refreshModelState()
    } catch {
      installTask = nil
      modelState = .missing
      if let error = error as? DPModelError, error == .cancelled { return }
      status = L.format(.downloadFailed, Self.reason(for: error), italian: italian)
      await refreshModelState()
    }
  }

  func cancelDownload() { installTask?.cancel() }

  private func downloadProgress(_ value: Double) {
    guard installTask != nil, case .downloading = modelState else { return }
    modelState = .downloading(value)
  }

  private static func reason(for error: any Error) -> String {
    switch error as? DPModelError {
    case .network(let message): message
    case .wrongSize, .wrongChecksum: "the file is incomplete or damaged"
    case .notAllowed: "address not allowed"
    case .compileFailed: "the model could not be prepared"
    case .busy: "a download is already running"
    case .cancelled: "cancelled"
    case nil: error.localizedDescription
    }
  }

  // MARK: The app talks

  /// The first `project` message and the ones after: the mode is the project's; the picture and the maps are not kept.
  func switchProject(folder: URL, adoptLegacy: Bool) {
    store.folder = folder
    if adoptLegacy { store.adoptLegacy() }
    let selection = store.load()
    loadingChoice = true
    wantsDepth = selection.depth
    wantsPose = selection.pose
    loadingChoice = false
    generation += 1
    isWorking = false
    image = nil
    imageName = ""
    depthImage = nil
    poseImage = nil
    status = ""
  }

  func apply(context data: Data) {
    if let context = try? JSONDecoder().decode(DTHubContext.self, from: data) { tempFolder = context.tempFolder }
  }
}

/// A reference to the state a progress callback of another thread may hold without keeping it alive.
private final class WeakState: @unchecked Sendable {
  weak var value: DPState?
  init(_ value: DPState) { self.value = value }
}
