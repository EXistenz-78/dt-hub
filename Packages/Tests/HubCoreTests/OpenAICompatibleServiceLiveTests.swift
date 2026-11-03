import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

/// Needs LM Studio running with its server and a chat model loaded; run outside the sandbox:
/// `DTHUB_LIVE_SERVER=http://localhost:1235/v1 swift test --filter OpenAICompatibleServiceLiveTests`
struct OpenAICompatibleServiceLiveTests {
  static let address = ProcessInfo.processInfo.environment["DTHUB_LIVE_SERVER"]

  @Test(.enabled(if: address != nil))
  func listsTheModelsAndAnswersAQuestion() async throws {
    let text = try #require(Self.address)
    let base = try #require(LMStudioAddress.validated(text))
    let service = OpenAICompatibleService()
    await service.configure(address: base, visionModels: [])
    let models = try await service.models()
    print("LIVE models: \(models.map(\.name))")
    let first = try #require(models.first)
    try await service.load(first)
    let answer = try await service.respond(
      to: "Reply with exactly one word: pong", images: [], options: LanguageModelOptions(temperature: 0))
    print("LIVE answer: \(answer)")
    #expect(answer.lowercased().contains("pong"))
  }

  /// A 64×64 picture that is entirely red.
  func redImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("red-\(UUID()).png")
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test(.enabled(if: address != nil))
  func readsAPictureWithAVisionModel() async throws {
    let text = try #require(Self.address)
    let base = try #require(LMStudioAddress.validated(text))
    let service = OpenAICompatibleService()
    await service.configure(address: base, visionModels: [])
    let vision = try #require(try await service.models().first { $0.supportsImages }, "no vision model on the server")
    try await service.load(vision)
    let answer = try await service.respond(
      to: "What color is this picture? Reply with one word.", images: [try redImage()],
      options: LanguageModelOptions(temperature: 0, maxTokens: 800))
    print("LIVE picture answer: \(answer)")
    #expect(answer.lowercased().contains("red"))
  }
}
