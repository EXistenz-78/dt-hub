import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFPresetsTests {
  private func fields(_ preset: [String: Any]) -> [String: Any] { preset["fields"] as? [String: Any] ?? [:] }

  @Test func messagesAreThePanoThenTheSeamPreset() {
    let messages = PFPresets.messages()
    #expect(messages.count == 2)
    #expect(messages[0]["name"] as? String == "PANO F3")
    #expect(messages[1]["name"] as? String == "PANO F3 Seamfix")
    #expect(messages.allSatisfy { $0["model"] as? String == "flux_3_klein_q8p.ckpt" })
  }

  @Test func theFieldsAreThoseOfTheUsersPresets() {
    for preset in PFPresets.messages() {
      let f = fields(preset)
      #expect(f["steps"] as? Int == (preset["name"] as? String == "PANO F3" ? 24 : 16))
      #expect(f["guidanceScale"] as? Double == 1.0)
      #expect(f["sampler"] as? Int == 16)
      #expect(f["shift"] as? Double == 16.0)
      #expect(f["resolutionDependentShift"] as? Bool == false)
      #expect(f["highRes"] as? Bool == true)
    }
  }

  @Test func eachPresetCarriesItsLoRAWithTrigger() throws {
    let messages = PFPresets.messages()
    let pano = try #require((messages[0]["loras"] as? [[String: Any]])?.first)
    let seam = try #require((messages[1]["loras"] as? [[String: Any]])?.first)
    #expect(pano["file"] as? String == "f3_360_lora_f16.ckpt" && pano["trigger"] as? String == "create a 360 hdr")
    #expect(seam["file"] as? String == "f3_seamfix_lora_f16.ckpt" && seam["trigger"] as? String == "seamfix")
    for lora in [pano, seam] {
      #expect(lora["weight"] as? Double == 1.0 && lora["mode"] as? Int == 0)
    }
  }

  @Test func loraSeamSelectsTheEntry() {
    #expect(PFPresets.lora(seam: false)["file"] as? String == "f3_360_lora_f16.ckpt")
    #expect(PFPresets.lora(seam: true)["file"] as? String == "f3_seamfix_lora_f16.ckpt")
  }

  @Test func theTriggerWordIsNeverPartOfAPresetPrompt() {
    #expect(PFPresets.messages().allSatisfy { $0["prompt"] == nil })
  }

  @Test func registerSendsBothAndReturnsTheAnswer() async {
    var sent: [[String: Any]] = []
    let answer = await PFPresets.register { presets in
      sent = presets
      return ["type": "ok"]
    }
    #expect(sent.count == 2)
    #expect(answer?["type"] as? String == "ok")
  }
}
