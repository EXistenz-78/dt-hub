import CoreGraphics
import CoreML
import CoreVideo

/// Depth Anything V2 (Small, F16) as Apple converted it: input `image`, output `depth`, a grey picture.
struct CoreMLDepthModel: DPDepthModel, @unchecked Sendable {
  private let model: MLModel
  /// The one size the model takes (518×392 for Depth Anything V2 Small as Apple converted it: its card says
  /// "shorter side 518", but the model refuses anything else than this size).
  let inputSize: (width: Int, height: Int)

  init(compiledModel: URL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    model = try MLModel(contentsOf: compiledModel, configuration: configuration)
    let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint
    inputSize = (constraint?.pixelsWide ?? 518, constraint?.pixelsHigh ?? 392)
  }

  func predict(_ image: CGImage) throws -> CGImage {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
      [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
    guard let buffer else { throw DPDepthError.cannotResize }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    CVPixelBufferUnlockBaseAddress(buffer, [])

    let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
    let result = try model.prediction(from: features)
    guard let depth = result.featureValue(for: "depth")?.imageBufferValue else { throw DPDepthError.noDepthOutput }
    return try Self.grey(depth)
  }

  /// A grey pixel buffer (8-bit, or half floats stretched to 8 bits) as a picture.
  static func grey(_ buffer: CVPixelBuffer) throws -> CGImage {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw DPDepthError.noDepthOutput }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var bytes = [UInt8](repeating: 0, count: width * height)
    switch format {
    case kCVPixelFormatType_OneComponent8:
      for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width { bytes[y * width + x] = row[x] }
      }
    case kCVPixelFormatType_OneComponent16Half:
      var values = [Float](repeating: 0, count: width * height)
      for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float16.self)
        for x in 0..<width { values[y * width + x] = Float(row[x]) }
      }
      let low = values.min() ?? 0, high = values.max() ?? 1
      let range = max(high - low, .leastNormalMagnitude)
      for i in values.indices { bytes[i] = UInt8(max(0, min(255, ((values[i] - low) / range * 255).rounded()))) }
    default:
      throw DPDepthError.unsupportedOutput(format)
    }
    guard
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
    else { throw DPDepthError.noDepthOutput }
    return image
  }
}
