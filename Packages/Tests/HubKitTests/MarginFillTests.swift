import Foundation
import Testing

@testable import HubKit

struct MarginFillTests {
  @Test func withoutAnOutpaintLoRAMarginsAreExtendedEdgesWithAMask() {
    #expect(MarginFill.automatic(loras: []) == .edges)
    #expect(MarginFill.automatic(loras: [LoRASelection(file: "flux2_realistic_lora_f16.ckpt")]) == .edges)
    #expect(MarginFill.edges.sendsMask)
  }

  @Test func anOutpaintLoRAAsksForASolidColourAndNoMask() {
    let qwen = LoRASelection(
      file: "q21_outpaint_v2_lora_f16.ckpt", trigger: "outpaint the image: replace the solid gray areas with a seamless continuation")
    #expect(MarginFill.automatic(loras: [qwen]) == .gray)
    let flux = LoRASelection(file: "flux_outpaint_lora_lora_f16.ckpt", trigger: "fill the green spaces according to the image")
    #expect(MarginFill.automatic(loras: [flux]) == .green)
    // The name alone is enough, in any case, and so is the trigger.
    #expect(MarginFill.automatic(loras: [LoRASelection(file: "My_OUTPAINT.ckpt")]) == .gray)
    #expect(MarginFill.automatic(loras: [LoRASelection(file: "x.ckpt", trigger: "Outpaint the image")]) == .gray)
    #expect(!MarginFill.gray.sendsMask && !MarginFill.green.sendsMask)
  }

  @Test func theChoiceIsSavedAndALostOrUnknownOneMeansAutomatic() throws {
    var inputs = ControlInputs()
    #expect(inputs.marginFill == nil)
    inputs.marginFill = .green
    let back = try JSONDecoder().decode(ControlInputs.self, from: JSONEncoder().encode(inputs))
    #expect(back.marginFill == .green)
    let unknown = try JSONDecoder().decode(ControlInputs.self, from: Data(#"{"marginFill": "purple"}"#.utf8))
    #expect(unknown.marginFill == nil)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: Data("{}".utf8)).marginFill == nil)
  }
}
