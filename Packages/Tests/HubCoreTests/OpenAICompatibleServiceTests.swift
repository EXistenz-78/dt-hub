import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

struct OpenAICompatibleServiceTests {
  func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func messages(_ body: [String: Any]) throws -> [[String: Any]] {
    try #require(body["messages"] as? [[String: Any]])
  }

  @Test func bodyPutsSystemHistoryAndTheQuestionInOrder() throws {
    let data = try OpenAICompatibleService.body(
      model: "m", prompt: "now", imageDataURLs: [], options: LanguageModelOptions(system: "be brief"),
      history: [LanguageModelTurn(role: .user, text: "h1"), LanguageModelTurn(role: .assistant, text: "h2")])
    let body = try json(data)
    let list = try messages(body)
    #expect(list.map { $0["role"] as? String } == ["system", "user", "assistant", "user"])
    #expect(list.map { $0["content"] as? String } == ["be brief", "h1", "h2", "now"])
    #expect(body["model"] as? String == "m")
    #expect(body["stream"] as? Bool == false)
    #expect(body["temperature"] as? Double == 0.6)
    #expect(body["max_tokens"] as? Int == 1024 + OpenAICompatibleService.thinkingAllowance)
  }

  @Test func bodyMapsTheOptions() throws {
    let options = LanguageModelOptions(
      temperature: 0.2, topP: 0.9, topK: 40, presencePenalty: 0.5, maxTokens: 50, thinking: true)
    let body = try json(
      OpenAICompatibleService.body(model: "m", prompt: "q", imageDataURLs: [], options: options, history: []))
    #expect(body["temperature"] as? Double == 0.2)
    #expect(body["top_p"] as? Double == 0.9)
    #expect(body["presence_penalty"] as? Double == 0.5)
    #expect(body["max_tokens"] as? Int == 50 + OpenAICompatibleService.thinkingAllowance)
    #expect(body["top_k"] as? Int == 40)
    #expect(body["thinking"] == nil)
    #expect(body["enable_thinking"] == nil)
  }

  @Test func imagesGoInTheLastUserMessageAsDataURLs() throws {
    let body = try json(
      OpenAICompatibleService.body(
        model: "m", prompt: "look", imageDataURLs: ["data:image/jpeg;base64,AAA"], options: LanguageModelOptions(),
        history: []))
    let content = try #require(try messages(body).last?["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "text")
    #expect(content.first?["text"] as? String == "look")
    let image = try #require(content.last?["image_url"] as? [String: Any])
    #expect(content.last?["type"] as? String == "image_url")
    #expect(image["url"] as? String == "data:image/jpeg;base64,AAA")
  }

  func reply(_ text: String) -> Data {
    let escaped = String(data: (try? JSONEncoder().encode(text)) ?? Data(), encoding: .utf8) ?? "\"\""
    return Data(#"{"choices":[{"message":{"role":"assistant","content":\#(escaped)}}]}"#.utf8)
  }

  @Test func answerReadsTheFirstChoiceAndStripsAThinkBlock() throws {
    #expect(try OpenAICompatibleService.answer(from: reply("<think>x\ny</think>\n pong ")) == "pong")
    #expect(try OpenAICompatibleService.answer(from: reply("pong")) == "pong")
  }

  @Test func answerWithoutChoicesOrEmptyThrowsGenerationFailed() {
    for body in ["<html>nope</html>", "{}", #"{"choices":[{"message":{"content":"  "}}]}"#] {
      do {
        _ = try OpenAICompatibleService.answer(from: Data(body.utf8))
        Issue.record("it should have thrown for \(body)")
      } catch let error as LanguageModelError {
        guard case .generationFailed(let text) = error else {
          Issue.record("wrong error \(error)")
          continue
        }
        if body.hasPrefix("<html") { #expect(text.contains("<html>nope")) }
      } catch {
        Issue.record("wrong error \(error)")
      }
    }
  }

  @Test func imageDataURLShrinksALargePicture() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID()).png")
    let context = try #require(
      CGContext(
        data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    let dataURL = try #require(OpenAICompatibleService.imageDataURL(for: url, maxPixel: 1536))
    #expect(dataURL.hasPrefix("data:image/jpeg;base64,"))
    let bytes = try #require(Data(base64Encoded: String(dataURL.dropFirst("data:image/jpeg;base64,".count))))
    let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) <= 1536)
  }

  // MARK: The service

  let base = URL(string: "http://localhost:1235/v1")!

  func service(
    models: [String] = ["a"], send: @escaping @Sendable (URLRequest) async throws -> (Data, Int)
  ) async -> OpenAICompatibleService {
    let list = ServerModelList { _ in
      let items = models.map { #"{"id":"\#($0)","type":"llm"}"# }.joined(separator: ",")
      return Data(#"{"data":[\#(items)]}"#.utf8)
    }
    let service = OpenAICompatibleService(list: list, send: send)
    await service.configure(address: base, visionModels: [])
    return service
  }

  final class Seen: @unchecked Sendable {
    var request: URLRequest?
  }

  @Test func respondSendsToTheChatURL() async throws {
    let seen = Seen()
    let service = await service { request in
      seen.request = request
      return (Data(#"{"choices":[{"message":{"content":"pong"}}]}"#.utf8), 200)
    }
    _ = try await service.models()
    try await service.load(ServerModelList.descriptor(id: "a", vision: false))
    let answer = try await service.respond(to: "ping", images: [])
    #expect(answer == "pong")
    #expect(seen.request?.httpMethod == "POST")
    #expect(seen.request?.url?.absoluteString == "http://localhost:1235/v1/chat/completions")
    #expect(seen.request?.timeoutInterval == 300)
  }

  @Test func httpErrorsShowTheServersMessage() async throws {
    let service = await service { _ in
      (Data(#"{"error":{"message":"No models loaded. boom"}}"#.utf8), 400)
    }
    try await service.load(ServerModelList.descriptor(id: "a", vision: false))
    do {
      _ = try await service.respond(to: "ping", images: [])
      Issue.record("it should have thrown")
    } catch let error as LanguageModelError {
      guard case .generationFailed(let text) = error else {
        Issue.record("wrong error \(error)")
        return
      }
      #expect(text.contains("boom"))
    }
  }

  @Test func aServerThatIsOffIsLoadFailedWithTheAddress() async throws {
    let service = await service { _ in throw URLError(.cannotConnectToHost) }
    try await service.load(ServerModelList.descriptor(id: "a", vision: false))
    do {
      _ = try await service.respond(to: "ping", images: [])
      Issue.record("it should have thrown")
    } catch let error as LanguageModelError {
      guard case .loadFailed(let text) = error else {
        Issue.record("wrong error \(error)")
        return
      }
      #expect(text.contains("localhost:1235"))
    }
  }

  @Test func aCancelledRequestIsNotReportedAsAServerThatIsOff() async throws {
    let service = await service { _ in throw URLError(.cancelled) }
    try await service.load(ServerModelList.descriptor(id: "a", vision: false))
    await #expect(throws: CancellationError.self) { try await service.respond(to: "ping", images: []) }
  }

  @Test func respondWithoutALoadedModelFails() async {
    let service = await service { _ in (Data(), 200) }
    await #expect(throws: LanguageModelError.self) { try await service.respond(to: "ping", images: []) }
  }

  @Test func loadOfAnUnknownModelIsModelNotFound() async throws {
    let service = await service { _ in (Data(), 200) }
    _ = try await service.models()
    await #expect(throws: LanguageModelError.modelNotFound("ghost")) {
      try await service.load(ServerModelList.descriptor(id: "ghost", vision: false))
    }
  }
}
