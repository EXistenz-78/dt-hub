// Copied from Plugins/Panorama360 (2026-10-28).
import Metal

/// Proof that a shader compiled from a Swift string runs inside the plug-in: one triangle into a 4 × 4 texture, one pixel
/// read back. Never throws: any failure is `false` (the renderer then falls back to the CPU one).
enum PSMetalProbe {
  private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    vertex float4 probeVertex(uint id [[vertex_id]]) {
      float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
      return float4(p[id], 0, 1);
    }
    fragment float4 probeFragment() { return float4(0, 1, 0, 1); }
    """

  static func canCompileAndRun() -> Bool {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: source, options: nil),
      let vertex = library.makeFunction(name: "probeVertex"), let fragment = library.makeFunction(name: "probeFragment")
    else { return false }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return false }
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
    textureDescriptor.usage = [.renderTarget, .shaderRead]
    textureDescriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: textureDescriptor), let buffer = queue.makeCommandBuffer() else { return false }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
    pass.colorAttachments[0].storeAction = .store
    guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
    encoder.setRenderPipelineState(pipeline)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    var pixel = [UInt8](repeating: 0, count: 4)
    texture.getBytes(&pixel, bytesPerRow: 16, from: MTLRegionMake2D(1, 1, 1, 1), mipmapLevel: 0)
    return pixel == [0, 255, 0, 255]
  }
}
