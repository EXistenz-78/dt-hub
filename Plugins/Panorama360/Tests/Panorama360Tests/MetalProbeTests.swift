import Testing

@testable import Panorama360

@Suite("Metal probe")
struct MetalProbeTests {
  @Test func shaderCompiledFromAStringRunsAndReadsBack() {
    #expect(PSMetalProbe.canCompileAndRun())
  }
}
