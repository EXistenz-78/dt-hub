import CoreGraphics
import Foundation
import Metal

/// The same maths as `PSCPURenderer` on the GPU: one full-screen pass per layer, blended as premultiplied alpha over a green clear.
final class PSMetalRenderer: PSRendering, @unchecked Sendable {
  private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float4 forward; float4 right; float4 up; float4 params; };  // params: tanX, tanY, opacity, uOffset
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut panoVertex(uint id [[vertex_id]]) {
      float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
      VOut out;
      out.position = float4(p[id], 0, 1);
      out.uv = float2(p[id].x * 0.5 + 0.5, 0.5 - p[id].y * 0.5);
      return out;
    }

    fragment float4 panoFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> tex [[texture(0)]]) {
      float lon = (in.uv.x + u.params.w - 0.5) * 2.0 * M_PI_F;
      float lat = (0.5 - in.uv.y) * M_PI_F;
      float3 d = float3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat));
      float dz = dot(d, u.forward.xyz);
      if (dz <= 1e-5) { discard_fragment(); }
      float s = dot(d, u.right.xyz) / dz / u.params.x * 0.5 + 0.5;
      float t = 0.5 - dot(d, u.up.xyz) / dz / u.params.y * 0.5;
      if (s < 0.0 || s > 1.0 || t < 0.0 || t > 1.0) { discard_fragment(); }
      constexpr sampler smp(filter::linear, address::clamp_to_edge, coord::normalized);
      return tex.sample(smp, float2(s, t)) * u.params.z;
    }
    """

  private struct Uniforms {
    var forward: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var params: SIMD4<Float>
  }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
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
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "panoVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "panoFragment")
    let attachment = descriptor.colorAttachments[0]!
    attachment.pixelFormat = .rgba8Unorm
    attachment.isBlendingEnabled = true
    attachment.sourceRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    do { pipeline = try device.makeRenderPipelineState(descriptor: descriptor) } catch { throw PSRenderError.metal("\(error)") }
  }

  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double) throws -> CGImage {
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
    encoder.setRenderPipelineState(pipeline)
    for layer in layers {
      var uniforms = Uniforms(
        forward: Self.vector(layer.basis.forward), right: Self.vector(layer.basis.right), up: Self.vector(layer.basis.up),
        params: SIMD4(Float(layer.basis.tanX), Float(layer.basis.tanY), Float(layer.opacity), Float(uOffset)))
      encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
      encoder.setFragmentTexture(try texture(for: layer.image), index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    encoder.endEncoding()
    // Only the pictures just drawn keep their texture: a sticker that was removed, or one of another project, frees its memory.
    let used = Set(layers.map { ObjectIdentifier($0.image) })
    textures = textures.filter { used.contains($0.key) }
    buffer.commit()
    buffer.waitUntilCompleted()
    guard buffer.status == .completed else { throw PSRenderError.metal("the GPU did not finish: \(buffer.status.rawValue)") }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    guard let image = PSPixels.image(bytes: bytes, width: width, height: height) else { throw PSRenderError.image }
    return image
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
