import DTHubPluginKit
import Foundation

/// What the tab shows and does: the marks, the texts of the cards, Undo and Redo, and the sending of the drawing and the prompt.
@MainActor
final class InpaintingState: ObservableObject {
  /// The question to the enhancer: text, picture paths, system prompt, model name.
  typealias Ask = @MainActor (String, [String], String, String) async -> DTHubLLMAnswer
  /// `host.contribute`.
  typealias Contribute = @MainActor ([String: Any]) async -> [String: Any]?

  static let undoLimit = 100
  static let fusedMaxSide = 1536

  private var store: InpaintingStore
  private let italian: Bool
  private var undoStack: [[Mark]] = []
  private var redoStack: [[Mark]] = []

  @Published var session = InpaintingSession() { didSet { store.save(session) } }
  @Published var context: DTHubContext?
  @Published var active = false
  @Published var status = ""
  @Published var statusIsError = false
  @Published var isSending = false
  /// The mark being drawn, for the canvas.
  @Published var live: Mark?

  init(store: InpaintingStore = InpaintingStore(folder: nil), italian: Bool = L.systemIsItalian) {
    self.store = store
    self.italian = italian
    session = store.load() ?? InpaintingSession()
  }

  // MARK: What the app says

  /// The context: when the start image is another (or none any more) the marks and Undo go; the texts stay.
  func apply(context data: Data) {
    guard let decoded = try? JSONDecoder().decode(DTHubContext.self, from: data) else { return }
    context = decoded
    if decoded.startImage != session.startImage {
      undoStack = []
      redoStack = []
      session.marks = []
      session.startImage = decoded.startImage
    }
  }

  /// A project was opened: its state (or an empty one); Undo starts again.
  func switchProject(folder: URL) {
    store = InpaintingStore(folder: folder)
    undoStack = []
    redoStack = []
    live = nil
    session = store.load() ?? InpaintingSession()
  }

  // MARK: Marks

  var startImagePath: String? { context?.startImage }
  var canUndo: Bool { !undoStack.isEmpty }
  var canRedo: Bool { !redoStack.isEmpty }

  private func remember() {
    undoStack.append(session.marks)
    if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
    redoStack = []
  }

  func add(_ mark: Mark) {
    guard session.marks.count < Mark.maxMarks else { return }
    remember()
    session.marks.append(mark.clamped())
  }

  func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(session.marks)
    session.marks = previous
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(session.marks)
    session.marks = next
  }

  func clearAll() {
    guard !session.marks.isEmpty else { return }
    remember()
    session.marks = []
  }

  func setText(_ text: String, for key: CardKey) { session.texts[key.rawValue] = text }

  // MARK: Cards and prompt

  var cards: [(key: CardKey, count: Int)] {
    Cards.keys(of: session.marks).map { ($0, Cards.count(of: $0, in: session.marks)) }
  }

  var composedPrompt: String { Cards.prompt(marks: session.marks, texts: session.texts) }

  var enhancer: DTHubLanguageModel? { PromptEnhancer.model(in: context?.languageModels ?? []) }

  var canSend: Bool { active && !isSending && startImagePath != nil && !session.marks.isEmpty }

  // MARK: Sending

  private func setStatus(_ text: String, error: Bool = false) {
    status = text
    statusIsError = error
  }

  /// Draws the PNG, writes the prompt (directly or through the enhancer) and sends both to the app.
  func send(using ask: Ask, contribute: Contribute) async {
    guard canSend, let context, let startPath = startImagePath else { return }
    isSending = true
    defer { isSending = false }
    setStatus(L.text(.sending, italian: italian))

    guard let imageSize = Rasterizer.imageSize(at: startPath) else {
      setStatus(L.text(.noImage, italian: italian), error: true)
      return
    }
    let scale = min(1, Double(Rasterizer.paintMaxSide) / Double(max(imageSize.width, imageSize.height)))
    let paintSize = CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    guard let paintImage = Rasterizer.paint(session.marks, size: paintSize, imageWidth: Double(imageSize.width)) else {
      setStatus(L.text(.notAnswered, italian: italian), error: true)
      return
    }
    let folder = URL(fileURLWithPath: context.tempFolder, isDirectory: true)
      .appendingPathComponent("qwen-inpainting-\(UUID().uuidString)", isDirectory: true)
    let paintURL = folder.appendingPathComponent("paint.png")
    do {
      try Rasterizer.writePNG(paintImage, to: paintURL)
    } catch {
      setStatus(error.localizedDescription, error: true)
      return
    }

    var prompt = composedPrompt
    var peNote: String?
    if session.usePE, let model = enhancer, !prompt.isEmpty {
      setStatus(L.text(.enhancing, italian: italian))
      var reason = L.text(.peNoReason, italian: italian)
      if let start = Rasterizer.orientedImage(at: startPath, maxSide: Self.fusedMaxSide),
        let fused = Rasterizer.fused(start: start, paint: paintImage, maxSide: Self.fusedMaxSide)
      {
        let fusedURL = folder.appendingPathComponent("fused.png")
        if (try? Rasterizer.writePNG(fused, to: fusedURL)) != nil {
          let answer = await ask(
            PromptEnhancer.request(composed: prompt), [fusedURL.path], PromptEnhancer.systemPrompt(for: model), model.name)
          switch answer {
          case .text(let text):
            if let better = PromptEnhancer.cleaned(text) {
              prompt = better
              reason = ""
            }
          case .failure(let why): reason = why
          }
        }
      }
      if !reason.isEmpty { peNote = L.format(.peFallback, reason, italian: italian) }
    }

    var body: [String: Any] = ["paint": ["path": paintURL.path, "name": "Qwen 2.1 Inpainting"] as [String: Any]]
    if !prompt.isEmpty { body["fields"] = ["prompt": prompt] }
    let answer = await contribute(body)
    describe(answer, peNote: peNote)
  }

  private func describe(_ answer: [String: Any]?, peNote: String?) {
    guard let answer else {
      setStatus(L.text(.notAnswered, italian: italian), error: true)
      return
    }
    if answer["type"] as? String == "error" {
      setStatus(answer["text"] as? String ?? L.text(.notAnswered, italian: italian), error: true)
      return
    }
    var text: String
    if let conflicts = answer["conflicts"] as? Int, conflicts > 0 {
      text = L.format(.sentConflicts, conflicts, italian: italian)
    } else {
      text = L.text(.sent, italian: italian)
    }
    var isError = false
    if let problems = answer["problems"] as? [String], !problems.isEmpty {
      text += " " + problems.joined(separator: " ")
      isError = true
    }
    if let peNote { text += " " + peNote }
    setStatus(text, error: isError)
  }
}
