import Foundation
import HubKit
import ImageIO
import UniformTypeIdentifiers

/// A language model service that is also a server of models (LM Studio on this Mac).
public protocol ServerLanguageModelService: LanguageModelService {
  /// The address and the models the user said read pictures; set before `models()` and `load`.
  func configure(address: URL, visionModels: Set<String>) async
  /// The language models the server offers now.
  func models() async throws -> [LanguageModelDescriptor]
}

/// The language model through an OpenAI-compatible server on this Mac (LM Studio): the model is loaded by the server
/// at the first question, so `load` only remembers which model to ask and `unload` forgets it.
public actor OpenAICompatibleService: ServerLanguageModelService {
  private let list: ServerModelList
  private let send: @Sendable (URLRequest) async throws -> (Data, Int)
  private var base: URL?
  private var visionModels: Set<String> = []
  private var known: [String] = []
  private var current: String?

  public static let requestTimeout: TimeInterval = 300
  /// The long side of a picture sent to the server, in pixels.
  public static let maxPicturePixel = 1536

  public init(
    list: ServerModelList = .live,
    send: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = OpenAICompatibleService.liveSend
  ) {
    self.list = list
    self.send = send
  }

  public static let liveSend: @Sendable (URLRequest) async throws -> (Data, Int) = { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  public func configure(address: URL, visionModels: Set<String>) {
    base = address
    self.visionModels = visionModels
  }

  public func models() async throws -> [LanguageModelDescriptor] {
    guard let base else { throw LanguageModelError.loadFailed("No server address is set.") }
    let found = try await list.models(base: base, visionModels: visionModels)
    known = found.map(\.name)
    return found
  }

  public func load(_ model: LanguageModelDescriptor) async throws {
    if !known.isEmpty, !known.contains(model.name) { throw LanguageModelError.modelNotFound(model.name) }
    current = model.name
  }

  public func unload() async { current = nil }

  public func respond(
    to prompt: String, images: [URL], options: LanguageModelOptions, history: [LanguageModelTurn]
  ) async throws -> String {
    guard let current, let base else { throw LanguageModelError.loadFailed("No model is loaded.") }
    var pictures: [String] = []
    for image in images {
      guard let dataURL = Self.imageDataURL(for: image, maxPixel: Self.maxPicturePixel) else {
        throw LanguageModelError.generationFailed("The picture \(image.lastPathComponent) could not be read.")
      }
      pictures.append(dataURL)
    }
    var request = URLRequest(url: LMStudioAddress.chatURL(base))
    request.httpMethod = "POST"
    request.timeoutInterval = Self.requestTimeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Self.body(
      model: current, prompt: prompt, imageDataURLs: pictures, options: options, history: history)
    let data: Data
    let status: Int
    do {
      (data, status) = try await send(request)
    } catch {
      // Stop pressed, or RUN taking the memory: the request was cancelled, the server is fine.
      if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
        throw CancellationError()
      }
      let place = "\(base.host ?? "localhost"):\(base.port ?? 0)"
      throw LanguageModelError.loadFailed("LM Studio does not answer on \(place). Is it running, with its server started?")
    }
    guard (200..<300).contains(status) else {
      throw LanguageModelError.generationFailed(Self.errorText(data, status: status))
    }
    return try Self.answer(from: data)
  }

  // MARK: The messages

  /// Extra tokens given to a model that may think: its reasoning counts against `max_tokens`, and a server that does
  /// not separate it would leave the answer empty.
  static let thinkingAllowance = 8192

  /// The JSON body of a chat completion. `top_k` is sent only when set. `thinking == false` asks the server not to
  /// think (the OpenAI API has no such field, so the usual spellings are all sent; servers ignore the ones they do
  /// not know). Otherwise the model may think, and `max_tokens` grows by `thinkingAllowance` so the thinking does
  /// not eat the answer.
  static func body(
    model: String, prompt: String, imageDataURLs: [String], options: LanguageModelOptions, history: [LanguageModelTurn]
  ) throws -> Data {
    var messages: [[String: Any]] = []
    if let system = options.system, !system.isEmpty { messages.append(["role": "system", "content": system]) }
    for turn in history { messages.append(["role": turn.role.rawValue, "content": turn.text]) }
    if imageDataURLs.isEmpty {
      messages.append(["role": "user", "content": prompt])
    } else {
      var parts: [[String: Any]] = [["type": "text", "text": prompt]]
      for url in imageDataURLs { parts.append(["type": "image_url", "image_url": ["url": url]]) }
      messages.append(["role": "user", "content": parts])
    }
    let answerTokens = options.maxTokens ?? 1024
    var body: [String: Any] = [
      "model": model, "messages": messages, "stream": false,
      "temperature": options.temperature ?? 0.6, "max_tokens": answerTokens + (options.thinking == false ? 0 : thinkingAllowance),
    ]
    if options.thinking == false {
      body["enable_thinking"] = false
      body["reasoning_effort"] = "none"
      body["chat_template_kwargs"] = ["enable_thinking": false]
    }
    if let topP = options.topP { body["top_p"] = topP }
    if let topK = options.topK { body["top_k"] = topK }
    if let penalty = options.presencePenalty { body["presence_penalty"] = penalty }
    return try JSONSerialization.data(withJSONObject: body)
  }

  /// The text of the first choice, without a leading `<think>…</think>` block.
  static func answer(from data: Data) throws(LanguageModelError) -> String {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let content =
      ((object?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
    guard let content else {
      throw .generationFailed("The server's answer has no text: " + String(String(decoding: data, as: UTF8.self).prefix(200)))
    }
    var text = content
    if let range = text.range(of: #"^\s*<think>[\s\S]*?</think>"#, options: [.regularExpression]) {
      text.removeSubrange(range)
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw .generationFailed("The server's answer is empty (a reasoning model may have used all its tokens thinking).")
    }
    return text
  }

  static func errorText(_ data: Data, status: Int) -> String {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if let message = (object?["error"] as? [String: Any])?["message"] as? String { return message }
    return "The server answered \(status): " + String(String(decoding: data, as: UTF8.self).prefix(200))
  }

  // MARK: Pictures

  /// A picture as a JPEG data URL with its long side at most `maxPixel`; nil when it cannot be read.
  static func imageDataURL(for url: URL, maxPixel: Int) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
  }
}
