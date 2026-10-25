import CoreGraphics
import Foundation
import Metal

/// The same maths as `PSCPURenderer` on the GPU: one full-screen pass per layer, blended as premultiplied alpha over a green clear (or over a
/// panorama drawn first).
final class PSMetalRenderer: PSRendering, @unchecked Sendable {
  private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // params: tanX, tanY, opacity, uOffset; extra: feather
    struct Uniforms { float4 forward; float4 right; float4 up; float4 params; float4 extra; };
    // The camera of a view: forward, right, up and (tanX, tanY).
    struct Camera { float4 forward; float4 right; float4 up; float4 params; };
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut panoVertex(uint id [[vertex_id]]) {
      float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
      VOut out;
      out.position = float4(p[id], 0, 1);
      out.uv = float2(p[id].x * 0.5 + 0.5, 0.5 - p[id].y * 0.5);
      return out;
    }

    float3 erpDirection(float2 uv, float uOffset) {
      float lon = (uv.x + uOffset - 0.5) * 2.0 * M_PI_F;
      float lat = (0.5 - uv.y) * M_PI_F;
      return float3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat));
    }

    float3 viewDirection(float2 uv, constant Camera &cam) {
      float sx = (2.0 * uv.x - 1.0) * cam.params.x;
      float sy = (1.0 - 2.0 * uv.y) * cam.params.y;
      return normalize(cam.forward.xyz + sx * cam.right.xyz + sy * cam.up.xyz);
    }

    float4 layerColor(float3 d, constant Uniforms &u, texture2d<float> tex) {
      float dz = dot(d, u.forward.xyz);
      if (dz <= 1e-5) { discard_fragment(); }
      float s = dot(d, u.right.xyz) / dz / u.params.x * 0.5 + 0.5;
      float t = 0.5 - dot(d, u.up.xyz) / dz / u.params.y * 0.5;
      if (s < 0.0 || s > 1.0 || t < 0.0 || t > 1.0) { discard_fragment(); }
      float strength = u.params.z;
      if (u.extra.x > 0.0) { strength *= smoothstep(0.0, u.extra.x, min(min(s, 1.0 - s), min(t, 1.0 - t))); }
      constexpr sampler smp(filter::linear, address::clamp_to_edge, coord::normalized);
      return tex.sample(smp, float2(s, t)) * strength;
    }

    fragment float4 panoFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> tex [[texture(0)]]) {
      return layerColor(erpDirection(in.uv, u.params.w), u, tex);
    }

    fragment float4 viewLayerFragment(
      VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], constant Camera &cam [[buffer(1)]], texture2d<float> tex [[texture(0)]]) {
      return layerColor(viewDirection(in.uv, cam), u, tex);
    }

    float4 panoramaColor(float3 d, texture2d<float> tex) {
      float lon = atan2(d.x, d.z);
      float lat = asin(clamp(d.y, -1.0, 1.0));
      constexpr sampler smp(filter::linear, s_address::repeat, t_address::clamp_to_edge, coord::normalized);
      return float4(tex.sample(smp, float2(lon / (2.0 * M_PI_F) + 0.5, 0.5 - lat / M_PI_F)).rgb, 1.0);
    }

    fragment float4 backgroundFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> tex [[texture(0)]]) {
      return panoramaColor(erpDirection(in.uv, u.params.w), tex);
    }

    fragment float4 viewPanoramaFragment(VOut in [[stage_in]], constant Camera &cam [[buffer(1)]], texture2d<float> tex [[texture(0)]]) {
      return panoramaColor(viewDirection(in.uv, cam), tex);
    }
    """

  private struct Uniforms {
    var forward: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var params: SIMD4<Float>
    var extra: SIMD4<Float>
  }

  private struct CameraUniforms {
    var forward: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var params: SIMD4<Float>
  }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let layerPipeline: MTLRenderPipelineState
  private let viewLayerPipeline: MTLRenderPipelineState
  private let backgroundPipeline: MTLRenderPipelineState
  private let viewPanoramaPipeline: MTLRenderPipelineState
  private let lock = NSLock()
  /// The textures made from pictures already seen; the picture is kept with its texture so its identity cannot be reused.
  private var textures: [ObjectIdentifier: (image: CGImage, texture: MTLTexture)] = [:]

  /// How many textures are kept (for the tests).
  var cachedTextureCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return textures.count
  }

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw PSRenderError.metal("no Metal device")
    }
    self.device = device
    self.queue = queue
    let library: MTLLibrary
    do { library = try device.makeLibrary(source: Self.source, options: nil) } catch { throw PSRenderError.metal("\(error)") }
    func pipeline(_ fragment: String) throws -> MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "panoVertex")
      descriptor.fragmentFunction = library.makeFunction(name: fragment)
      let attachment = descriptor.colorAttachments[0]!
      attachment.pixelFormat = .rgba8Unorm
      attachment.isBlendingEnabled = true
      attachment.sourceRGBBlendFactor = .one
      attachment.sourceAlphaBlendFactor = .one
      attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
      attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      do { return try device.makeRenderPipelineState(descriptor: descriptor) } catch { throw PSRenderError.metal("\(error)") }
    }
    layerPipeline = try pipeline("panoFragment")
    viewLayerPipeline = try pipeline("viewLayerFragment")
    backgroundPipeline = try pipeline("backgroundFragment")
    viewPanoramaPipeline = try pipeline("viewPanoramaFragment")
  }

  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double, background: CGImage?) throws -> CGImage {
    try draw(width: width, height: height, keeping: layers.map(\.image) + (background.map { [$0] } ?? [])) { encoder in
      if let background {
        encoder.setRenderPipelineState(backgroundPipeline)
        var uniforms = Uniforms(
          forward: .zero, right: .zero, up: .zero, params: SIMD4(0, 0, 1, Float(uOffset)), extra: .zero)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(try texture(for: background), index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      }
      encoder.setRenderPipelineState(layerPipeline)
      for layer in layers {
        var uniforms = Self.uniforms(layer, uOffset: uOffset)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(try texture(for: layer.image), index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      }
    }
  }

  func renderView(_ source: PSViewSource, camera: PSCamera, width: Int, height: Int) throws -> CGImage {
    let b = camera.basis
    var cam = CameraUniforms(
      forward: Self.vector(b.forward), right: Self.vector(b.right), up: Self.vector(b.up),
      params: SIMD4(Float(b.tanX), Float(b.tanX * Double(height) / Double(width)), 0, 0))
    switch source {
    case .layers(let layers):
      return try draw(width: width, height: height, keeping: layers.map(\.image)) { encoder in
        encoder.setRenderPipelineState(viewLayerPipeline)
        encoder.setFragmentBytes(&cam, length: MemoryLayout<CameraUniforms>.stride, index: 1)
        for layer in layers {
          var uniforms = Self.uniforms(layer, uOffset: 0)
          encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
          encoder.setFragmentTexture(try texture(for: layer.image), index: 0)
          encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
      }
    case .panorama(let image):
      return try draw(width: width, height: height, keeping: [image]) { encoder in
        encoder.setRenderPipelineState(viewPanoramaPipeline)
        encoder.setFragmentBytes(&cam, length: MemoryLayout<CameraUniforms>.stride, index: 1)
        encoder.setFragmentTexture(try texture(for: image), index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      }
    }
  }

  /// One render pass over a green clear; `body` encodes the draws. Only the pictures in `keeping` keep their texture afterwards: a sticker that
  /// was removed, or one of another project, frees its memory.
  private func draw(width: Int, height: Int, keeping: [CGImage], body: (MTLRenderCommandEncoder) throws -> Void) throws -> CGImage {
    lock.lock()
    defer { lock.unlock() }
    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    targetDescriptor.usage = [.renderTarget]
    targetDescriptor.storageMode = .shared
    guard let target = device.makeTexture(descriptor: targetDescriptor), let buffer = queue.makeCommandBuffer() else {
      throw PSRenderError.metal("no target")
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
    pass.colorAttachments[0].storeAction = .store
    guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { throw PSRenderError.metal("no encoder") }
    try body(encoder)
    encoder.endEncoding()
    let used = Set(keeping.map { ObjectIdentifier($0) })
    textures = textures.filter { used.contains($0.key) }
    buffer.commit()
    buffer.waitUntilCompleted()
    guard buffer.status == .completed else { throw PSRenderError.metal("the GPU did not finish: \(buffer.status.rawValue)") }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    guard let image = PSPixels.image(bytes: bytes, width: width, height: height) else { throw PSRenderError.image }
    return image
  }

  private static func uniforms(_ layer: PSLayer, uOffset: Double) -> Uniforms {
    Uniforms(
      forward: vector(layer.basis.forward), right: vector(layer.basis.right), up: vector(layer.basis.up),
      params: SIMD4(Float(layer.basis.tanX), Float(layer.basis.tanY), Float(layer.opacity), Float(uOffset)),
      extra: SIMD4(Float(layer.feather), 0, 0, 0))
  }

  private static func vector(_ v: Vec3) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), 0) }

  private func texture(for image: CGImage) throws -> MTLTexture {
    if let cached = textures[ObjectIdentifier(image)] { return cached.texture }
    let pixels = PSPixels.rgba(of: image)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: pixels.width, height: pixels.height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor) else { throw PSRenderError.metal("no texture") }
    texture.replace(
      region: MTLRegionMake2D(0, 0, pixels.width, pixels.height), mipmapLevel: 0, withBytes: pixels.bytes,
      bytesPerRow: pixels.width * 4)
    textures[ObjectIdentifier(image)] = (image, texture)
    return texture
  }
}
