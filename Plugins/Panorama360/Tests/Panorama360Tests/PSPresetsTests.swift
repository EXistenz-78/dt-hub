import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Presets")
struct PSPresetsTests {
  func fields(_ entry: [String: Any]) -> [String: Any] { entry["fields"] as? [String: Any] ?? [:] }

  @Test func theNamesAreTheAgreedOnes() {
    #expect(PSPresets.normalName == "PAN · 360 ERP")
    #expect(PSPresets.fastName == "PAN · 360 ERP Fast")
    #expect(PSPresets.messages().compactMap { $0["name"] as? String } == ["PAN · 360 ERP", "PAN · 360 ERP Fast"])
  }

  @Test func normalPresetMatchesTheUsersFile() throws {
    let normal = PSPresets.messages()[0]
    #expect(normal["model"] as? String == "flux_2_klein_base_9b_i8x.ckpt")
    let f = fields(normal)
    #expect(f["steps"] as? Int == 16)
    #expect(f["guidanceScale"] as? Double == 4)
    #expect(f["sampler"] as? Int == 16)
    #expect(f["shift"] as? Double == 3)
    #expect(f["resolutionDependentShift"] as? Bool == true)
    #expect(f["prompt"] == nil && f["width"] == nil && f["height"] == nil)
    let lora = try #require((normal["loras"] as? [[String: Any]])?.first)
    #expect(lora["file"] as? String == "f2_360_erp_outpaint_lora_v1_lora_f16.ckpt")
    #expect(lora["weight"] as? Double == 1)
    #expect(
      lora["trigger"] as? String
        == "fill the green spaces according to the image. outpaint as a seamless 360 equirectangular panorama (2:1). keep the horizon level. match left and right edges.")
    #expect(normal["advanced"] == nil || (normal["advanced"] as? [String: Any])?["refinerModel"] == nil)
  }

  @Test func fastPresetAddsTheRefinerAndNothingElse() throws {
    let normal = PSPresets.messages()[0], fast = PSPresets.messages()[1]
    let advanced = try #require(fast["advanced"] as? [String: Any])
    #expect(advanced["refinerModel"] as? String == "flux_2_klein_9b_kv_i8x.ckpt")
    #expect(advanced["refinerStart"] as? Double == 0.25)
    #expect(fast["model"] as? String == normal["model"] as? String)
    #expect(NSDictionary(dictionary: fields(fast)).isEqual(to: fields(normal)))
    #expect(fast["loras"] as? [[String: Any]] != nil)
  }

  @Test func registeringSendsBothPresetsAndReportsTheAnswer() async {
    var sent: [[String: Any]] = []
    let answer = await PSPresets.register { presets in
      sent = presets
      return ["type": "ok", "added": 2]
    }
    #expect(sent.count == 2 && answer?["added"] as? Int == 2)
  }
}
