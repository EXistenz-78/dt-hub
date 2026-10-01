import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LLMBridge

/// Needs a real model: run with
/// `TEST_RUNNER_DTHUB_LIVE_LLM=/path/to/model-folder xcodebuild test -scheme DTHubPackages-Package -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:LLMBridgeTests`
/// (the Metal library is built by Xcode; `swift test` skips these).
struct LiveLanguageModelTests {
  static let modelPath = ProcessInfo.processInfo.environment["DTHUB_LIVE_LLM"]

  func descriptor() throws -> LanguageModelDescriptor {
    let path = try #require(Self.modelPath)
    return LanguageModelDescriptor(path: path, name: URL(fileURLWithPath: path).lastPathComponent, sizeBytes: 0, supportsImages: true)
  }

  /// A 224×224 image that is entirely red.
  func redImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("red-\(UUID()).png")
    let context = try #require(
      CGContext(
        data: nil, width: 224, height: 224, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test(.enabled(if: modelPath != nil))
  func answersAQuestionAndFreesItsMemory() async throws {
    let service = MLXLanguageModelService()
    try await service.load(try descriptor())
    let answer = try await service.respond(to: "Reply with exactly one word: pong", images: [])
    print("LIVE text answer: \(answer)")
    #expect(answer.lowercased().contains("pong"))
    await service.unload()
    await #expect(throws: LanguageModelError.self) { try await service.respond(to: "hi", images: []) }
  }

  @Test(.enabled(if: modelPath != nil))
  func describesAnImage() async throws {
    let service = MLXLanguageModelService()
    try await service.load(try descriptor())
    let answer = try await service.respond(to: "What colour is this image? Answer with one word.", images: [try redImage()])
    print("LIVE vision answer: \(answer)")
    #expect(answer.lowercased().contains("red"))
    await service.unload()
  }
}

/// Needs the network: only two small files (a few KB) of the recommended small model are
/// fetched. Run with `TEST_RUNNER_DTHUB_LIVE_HF=1 xcodebuild test …`.
struct LiveDownloadTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_HF"] != nil))
  func downloadsIntoItsFolderAndLeavesNoStagingBehind() async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("LiveDownloadTests-\(UUID())")
    let destination = parent.appendingPathComponent("mlx-community/Qwen3-VL-2B-Instruct-4bit")
    try await HubLanguageModelDownloader(matching: ["config.json", "tokenizer_config.json"])
      .download(repository: "mlx-community/Qwen3-VL-2B-Instruct-4bit", to: destination, progress: { _ in })
    let files = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
    print("LIVE download files: \(files)")
    #expect(files.contains("config.json"))
    #expect(files.contains("tokenizer_config.json"))
    // The hidden staging folder is gone.
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
    #expect(!leftovers.contains { $0.hasPrefix(".dthub-download-") })
    try? FileManager.default.removeItem(at: parent)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_HF"] != nil))
  func aFailedDownloadLeavesNothingInTheFolder() async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("LiveDownloadTests-\(UUID())")
    let destination = parent.appendingPathComponent("nobody/no-such-model")
    await #expect(throws: LanguageModelError.self) {
      try await HubLanguageModelDownloader().download(
        repository: "nobody/no-such-model-xyz-123", to: destination, progress: { _ in })
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
    #expect(!entries.contains { $0.hasPrefix(".dthub-download-") })
    try? FileManager.default.removeItem(at: parent)
  }
}
