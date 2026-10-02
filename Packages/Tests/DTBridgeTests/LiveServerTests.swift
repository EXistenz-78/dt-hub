import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import DTBridge

/// Needs a real Draw Things gRPC server with "Model browsing" on. Run with:
/// `DTHUB_LIVE_DT=localhost:7859 swift test --filter LiveServerTests`
struct LiveServerTests {
  static let address = ProcessInfo.processInfo.environment["DTHUB_LIVE_DT"]

  @Test(.enabled(if: address != nil))
  func fetchesTheInstalledModels() async throws {
    let parts = try #require(Self.address?.split(separator: ":"))
    let backend = DrawThingsBackend(
      host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
    let catalog = try await backend.fetchCatalog()
    await backend.shutdown()
    #expect(!catalog.models.isEmpty)
    #expect(catalog.models.allSatisfy { !$0.name.isEmpty })
  }

  @Test(.enabled(if: address != nil))
  func reportsAnUnreachableServer() async {
    let backend = DrawThingsBackend(host: "localhost", port: 1, useTLS: true, sharedSecret: nil)
    await #expect(throws: BackendError.self) { try await backend.fetchCatalog() }
    await backend.shutdown()
  }

  @Test(.enabled(if: address != nil))
  func generatesOneImage() async throws {
    let parts = try #require(Self.address?.split(separator: ":"))
    let backend = DrawThingsBackend(
      host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
    let model = try #require(
      try await backend.fetchCatalog().models.first { $0.family == "flux2_9b" }?.file,
      "needs a FLUX.2 [klein] model on the server")
    let job = GenerationJob(
      prompt: "a red bicycle leaning on a stone wall", model: model,
      parameters: GenerationParameters(width: 512, height: 512, steps: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
    var sawProgress = false
    var images: [CGImage] = []
    for try await update in backend.generate(job) {
      switch update {
      case .progress: sawProgress = true
      case .preview: break
      case .finished(let final): images = final
      }
    }
    await backend.shutdown()
    #expect(sawProgress)
    #expect(images.count == 1)
    #expect(images.first?.width == 512)
  }

  /// FLUX.2 [klein] is an Edit model: the start image (left half black, right half white) is a
  /// reference at strength 100 %, and the result keeps the layout: the right side is brighter.
  @Test(.enabled(if: address != nil))
  func anEditModelKeepsTheLayoutOfTheStartImage() async throws {
    let backend = try await liveBackend()
    let model = try #require(
      try await backend.fetchCatalog().models.first { $0.family == "flux2_9b" }?.file,
      "needs a FLUX.2 [klein] model on the server")
    var job = GenerationJob(
      prompt: "the same picture", model: model,
      parameters: GenerationParameters(width: 512, height: 512, steps: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
    job.imageStrength = 1.0
    let guided = try await run(backend, job, GenerationInputs(image: splitImage(size: 512)))
    await backend.shutdown()
    let difference = rightMinusLeft(guided)
    print("LIVE edit model: right minus left luminance \(difference)")
    #expect(guided.width == 512)
    #expect(difference > 0.15)
  }

  /// A normal model (Juggernaut Reborn, SD 1.5) does image-to-image: at strength 50 % a solid
  /// green start image pulls the result toward green compared with the same RUN without it.
  @Test(.enabled(if: address != nil))
  func aNormalModelFollowsTheStartImageAtMidStrength() async throws {
    let backend = try await liveBackend()
    let model = try #require(
      try await backend.fetchCatalog().models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file,
      "needs Juggernaut Reborn on the server")
    var job = GenerationJob(
      prompt: "a red apple", model: model,
      parameters: GenerationParameters(
        width: 512, height: 512, steps: 12, guidanceScale: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
    let plain = try await run(backend, job, .none)
    job.imageStrength = 0.5
    let guided = try await run(backend, job, GenerationInputs(image: solid(red: 0, green: 255, blue: 0, size: 512)))
    await backend.shutdown()
    print("LIVE normal model: green share plain \(greenShare(plain)) guided \(greenShare(guided))")
    #expect(greenShare(guided) > greenShare(plain) + 0.05)
  }

  /// FLUX.2 [klein] reads Moodboard pictures as references: with no start image, a reference
  /// (left half black, right half white) shapes the result. (Its weight does not matter: any value
  /// above 0 gives the same result, measured in Draw Things and here.)
  @Test(.enabled(if: address != nil))
  func anEditModelReadsAMoodboardPicture() async throws {
    let backend = try await liveBackend()
    let model = try #require(
      try await backend.fetchCatalog().models.first { $0.family == "flux2_9b" }?.file,
      "needs a FLUX.2 [klein] model on the server")
    let job = GenerationJob(
      prompt: "the same picture", model: model,
      parameters: GenerationParameters(width: 512, height: 512, steps: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, splitImage(size: 512), nil)
    CGImageDestinationFinalize(destination)
    let full = try await run(backend, job, GenerationInputs(hints: [GenerationHint(imageData: data as Data)]))
    await backend.shutdown()
    print("LIVE moodboard: right minus left luminance \(rightMinusLeft(full))")
    #expect(full.width == 512)
    #expect(rightMinusLeft(full) > 0.15)
  }

  /// Z Image Turbo has no Edit modifier: does it read a Moodboard picture at all? (Measured, and
  /// the answer decides which families the Moodboard card is active for.)
  @Test(.enabled(if: address != nil))
  func aModernModelWithoutAnEditModifierAndTheMoodboard() async throws {
    let backend = try await liveBackend()
    let model = try #require(
      try await backend.fetchCatalog().models.first { $0.file.hasPrefix("z_image_turbo") }?.file,
      "needs Z Image Turbo on the server")
    let job = GenerationJob(
      prompt: "a photograph of a wall", model: model,
      parameters: GenerationParameters(width: 512, height: 512, steps: 8, sampler: .ddimTrailing, seed: 7, randomSeed: false))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, splitImage(size: 512), nil)
    CGImageDestinationFinalize(destination)
    let plain = try await run(backend, job, .none)
    let guided = try await run(backend, job, GenerationInputs(hints: [GenerationHint(imageData: data as Data)]))
    await backend.shutdown()
    print("LIVE z-image moodboard: right minus left plain \(rightMinusLeft(plain)) guided \(rightMinusLeft(guided))")
  }

  /// Inpainting, measured on SD 1.5 (Juggernaut Reborn) and FLUX.2 klein: a solid blue picture whose
  /// right half is masked is asked to become red poppies. The left half stays as it was and the
  /// right half is regenerated, at strength 100 % and without the inpaint control (which changed
  /// nothing on these models: measured with it on and off). At strength 70 % the masked half
  /// stayed blue, so the tab's automatic strength with a mask is 100 %.
  @Test(.enabled(if: address != nil))
  func aMaskKeepsTheOutsideAndRegeneratesTheInside() async throws {
    let backend = try await liveBackend()
    let models = try await backend.fetchCatalog().models
    let cases: [(label: String, file: String, steps: Int, guidance: Double)] = [
      ("sd15", models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file ?? "", 12, 4),
      ("klein", models.first { $0.family == "flux2_9b" }?.file ?? "", 4, 1),
    ]
    let source = try #require(solid(red: 0, green: 0, blue: 255, size: 512))
    let sourceLeft = blueShare(try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512))))
    let mask = halfMask(size: 512)
    var ran = 0
    for item in cases where !item.file.isEmpty {
      var job = GenerationJob(
        prompt: "a field of bright red poppies", model: item.file,
        parameters: GenerationParameters(
          width: 512, height: 512, steps: item.steps, guidanceScale: item.guidance, sampler: .ddimTrailing, seed: 7,
          randomSeed: false))
      job.imageStrength = 1.0
      job.maskSettings = MaskSettings()
      let out = try await run(backend, job, GenerationInputs(image: source, mask: mask))
      let left = try #require(out.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512)))
      let right = try #require(out.cropping(to: CGRect(x: 256, y: 0, width: 256, height: 512)))
      print("LIVE inpaint \(item.label): left blue \(blueShare(left)) (source \(sourceLeft)) right red \(redShare(right))")
      #expect(abs(blueShare(left) - sourceLeft) < 0.03)
      #expect(redShare(right) > 0.3)
      ran += 1
    }
    await backend.shutdown()
    #expect(ran > 0, "needs Juggernaut Reborn or a FLUX.2 klein model on the server")
  }

  /// 512×512, the right half transparent (to regenerate), the left half opaque (to keep).
  private func halfMask(size: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
    return context.makeImage()!
  }

  private func averageColor(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
  }

  private func redShare(_ image: CGImage) -> Double {
    let c = averageColor(image)
    return c.r / max(c.r + c.g + c.b, 0.001)
  }

  private func blueShare(_ image: CGImage) -> Double {
    let c = averageColor(image)
    return c.b / max(c.r + c.g + c.b, 0.001)
  }

  private func liveBackend() async throws -> DrawThingsBackend {
    let parts = try #require(Self.address?.split(separator: ":"))
    return DrawThingsBackend(host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
  }

  private func run(_ backend: DrawThingsBackend, _ job: GenerationJob, _ inputs: GenerationInputs) async throws -> CGImage {
    var final: [CGImage] = []
    for try await update in backend.generate(job, inputs: inputs) {
      if case .finished(let images) = update { final = images }
    }
    return try #require(final.first)
  }

  private func splitImage(size: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
    return context.makeImage()!
  }

  /// Average luminance of the right half minus the left half, 0…1.
  private func rightMinusLeft(_ image: CGImage) -> Double {
    func luminance(of rect: CGRect) -> Double {
      guard let part = image.cropping(to: rect) else { return 0 }
      var bytes = [UInt8](repeating: 0, count: 4)
      let context = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.interpolationQuality = .medium
      context.draw(part, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return (0.299 * Double(bytes[0]) + 0.587 * Double(bytes[1]) + 0.114 * Double(bytes[2])) / 255
    }
    let half = image.width / 2
    return luminance(of: CGRect(x: half, y: 0, width: half, height: image.height))
      - luminance(of: CGRect(x: 0, y: 0, width: half, height: image.height))
  }

  private func solid(red: Double, green: Double, blue: Double, size: Int) -> CGImage? {
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    context?.setFillColor(CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context?.makeImage()
  }

  /// Green's share of the average colour, 0…1.
  private func greenShare(_ image: CGImage) -> Double {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let total = Double(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2]))
    return total == 0 ? 0 : Double(bytes[1]) / total
  }
}
