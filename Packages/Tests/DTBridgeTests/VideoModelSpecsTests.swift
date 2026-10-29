import Foundation
import Testing

@testable import DTBridge

struct VideoModelSpecsTests {
  @Test func bundledSpecsCoverTheEnabledH3Files() throws {
    let file = "fasth3_omni_i4x.ckpt"
    let data = try #require(VideoModelSpecs.data(for: file))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["version"] as? String == "minimax_h3")
    #expect(object["modifier"] as? String == "ref2va")
    #expect(object["frames_per_second"] as? Int == 24)
    #expect(object["text_encoder"] as? String == "qwen_3_vl_32b_50_i8x.ckpt")
    #expect(object["file"] as? String == file)
    for other in [
      "minimax_h3_fl2va_i4x.ckpt", "minimax_h3_ref2va_i4x.ckpt", "fasth3_omni_q8p.ckpt", "fasth3_omni_i8x.ckpt",
    ] {
      #expect(VideoModelSpecs.data(for: other) != nil, "\(other)")
    }
  }

  @Test func unknownFileHasNoSpec() {
    #expect(VideoModelSpecs.data(for: "flux_2_klein_9b_q6p.ckpt") == nil)
  }
}
