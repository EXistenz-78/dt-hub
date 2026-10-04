import Testing

@testable import SphereLight

@Suite("SLRMessages")
struct SLRMessagesTests {
  private func steps(_ pipeline: [String: Any]) -> [[String: Any]] { pipeline["steps"] as? [[String: Any]] ?? [] }

  @Test func thePresetsCarryTheAcronymOfThePlugin() {
    let names = SLRMessages.presets().compactMap { $0["name"] as? String }
    #expect(names == ["SLR · Overcast", "SLR · Match the sun"])
  }

  @Test func bothPresetsHaveTheValuesOfTheScript() throws {
    for preset in SLRMessages.presets() {
      let fields = try #require(preset["fields"] as? [String: Any])
      #expect(fields["steps"] as? Int == 4)
      #expect(fields["guidanceScale"] as? Double == 1.0)
      #expect(fields["sampler"] as? Int == 16)
      #expect(fields["shift"] as? Int == 3)
      #expect(fields["cfgZeroStar"] as? Bool == false)
      // The shift of the script only counts with the "resolution dependent shift" switch off (a preset leaves it on otherwise).
      #expect(fields["resolutionDependentShift"] as? Bool == false)
      // No size and no model: those are the user's.
      #expect(fields["width"] == nil && fields["height"] == nil && preset["model"] == nil)
    }
  }

  @Test func onlyTheMatchPresetHasTheLoraAtZeroPointSix() throws {
    let presets = SLRMessages.presets()
    #expect(presets[0]["loras"] == nil)
    let loras = try #require(presets[1]["loras"] as? [[String: Any]])
    #expect(loras.count == 1)
    #expect(loras[0]["file"] as? String == "flux_2_sun_direction_lora_v1_lora_f16.ckpt")
    #expect(loras[0]["weight"] as? Double == 0.6)
  }

  @Test func thePromptsAreTheOnesOfTheScript() throws {
    let prompts = SLRMessages.presets().map { ($0["fields"] as? [String: Any])?["prompt"] as? String }
    #expect(prompts[0] == "make it an overcast day, remove the shadows")
    #expect(prompts[1] == "match light direction, colors and intensity from the reference image 2")
  }

  @Test func withOvercastThereAreTwoPassesAndTheSecondStartsFromTheFirst() {
    let pipeline = SLRMessages.pipeline(overcast: true, spherePath: "/tmp/s.png")
    let list = steps(pipeline)
    #expect(list.count == 2)
    #expect(list[0]["preset"] as? String == "SLR · Overcast")
    #expect(list[0]["moodboard"] == nil && list[0]["useOutputAsStart"] == nil)
    #expect(list[1]["preset"] as? String == "SLR · Match the sun")
    #expect(list[1]["useOutputAsStart"] as? Bool == true)
  }

  @Test func withoutOvercastOnlyTheMatchPassRunsOnTheCanvas() {
    let list = steps(SLRMessages.pipeline(overcast: false, spherePath: "/tmp/s.png"))
    #expect(list.count == 1)
    #expect(list[0]["preset"] as? String == "SLR · Match the sun")
    #expect(list[0]["useOutputAsStart"] as? Bool == false)
  }

  @Test func theSphereIsInTheMoodboardOfTheMatchPassOnly() throws {
    for overcast in [true, false] {
      let list = steps(SLRMessages.pipeline(overcast: overcast, spherePath: "/tmp/s.png"))
      let moodboard = try #require(list.last?["moodboard"] as? [[String: Any]])
      #expect(moodboard.count == 1)
      #expect(moodboard[0]["path"] as? String == "/tmp/s.png")
      #expect(moodboard[0]["name"] as? String == "Sphere light")
    }
  }

  @Test func everyWordIsInItalianAndEnglish() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func formattedWordsTakeTheirArguments() {
    #expect(L.format(.sentWithConflicts, 2, italian: false) == "Sent. 2 conflict(s) waiting in the app.")
    #expect(L.format(.savedDesktop, "Sphere Light 001.png", italian: true).contains("Sphere Light 001.png"))
  }
}
