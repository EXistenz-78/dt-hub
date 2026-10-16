import CoreGraphics
import CoreML
import CoreVideo

enum DPPoseError: Error, Equatable {
  case wrongInputSize
  case cannotBuildInput
  case noOutput
}

/// DWPose-L as a Core ML model: input `image` (RGB 288×384, 0–255), outputs `simcc_x` and `simcc_y`.
struct CoreMLPoseNetwork: DPPoseNetwork, @unchecked Sendable {
  private let model: MLModel

  init(compiledModel: URL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    model = try MLModel(contentsOf: compiledModel, configuration: configuration)
  }

  func simcc(for crop: CGImage) throws -> (x: [Float], y: [Float]) {
    guard crop.width == DPCrop.width, crop.height == DPCrop.height else { throw DPPoseError.wrongInputSize }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault, crop.width, crop.height, kCVPixelFormatType_32BGRA,
      [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
    guard let buffer else { throw DPPoseError.cannotBuildInput }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: crop.width, height: crop.height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    context?.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    CVPixelBufferUnlockBaseAddress(buffer, [])

    let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
    let result = try model.prediction(from: features)
    guard let x = result.featureValue(for: "simcc_x")?.multiArrayValue,
      let y = result.featureValue(for: "simcc_y")?.multiArrayValue
    else { throw DPPoseError.noOutput }
    return (Self.floats(x), Self.floats(y))
  }

  /// The values of a (1, keypoints, bins) array as one flat list, whatever its type and strides.
  static func floats(_ array: MLMultiArray) -> [Float] {
    let shape = array.shape.map(\.intValue), strides = array.strides.map(\.intValue)
    guard shape.count == 3 else { return [] }
    let keypoints = shape[1], bins = shape[2]
    var result = [Float](repeating: 0, count: keypoints * bins)
    func fill<T>(_ type: T.Type, _ convert: (T) -> Float) {
      let pointer = array.dataPointer.assumingMemoryBound(to: T.self)
      for keypoint in 0..<keypoints {
        for bin in 0..<bins { result[keypoint * bins + bin] = convert(pointer[keypoint * strides[1] + bin * strides[2]]) }
      }
    }
    switch array.dataType {
    case .float16: fill(Float16.self) { Float($0) }
    case .float32: fill(Float.self) { $0 }
    case .double: fill(Double.self) { Float($0) }
    default: return []
    }
    return result
  }
}
