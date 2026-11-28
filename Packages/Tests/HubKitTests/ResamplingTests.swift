import Foundation
import Testing

@testable import HubKit

struct ResamplingTests {
  @Test func factoryIsCatmullRomForSeedVR2() {
    #expect(Resampling.factory(forFamily: "seedvr2_7b") == .catmullRom)
    #expect(Resampling.factory(forFamily: "seedvr2_3b") == .catmullRom)
  }

  @Test func factoryIsCoreGraphicsElsewhere() {
    #expect(Resampling.factory(forFamily: "flux2_9b") == .coreGraphics)
    #expect(Resampling.factory(forFamily: nil) == .coreGraphics)
  }

  @Test func explicitWinsOverSavedAndFactory() {
    #expect(Resampling.effective(explicit: .nearest, family: "seedvr2_7b", saved: ["seedvr2_7b": .bSpline]) == .nearest)
  }

  @Test func savedWinsOverFactory() {
    #expect(Resampling.effective(explicit: nil, family: "seedvr2_7b", saved: ["seedvr2_7b": .bSpline]) == .bSpline)
    #expect(Resampling.effective(explicit: nil, family: "seedvr2_7b", saved: [:]) == .catmullRom)
  }

  @Test func missingFieldDecodesAsAutomatic() throws {
    let advanced = try JSONDecoder().decode(AdvancedParameters.self, from: Data(#"{"colorCalibration":true}"#.utf8))
    #expect(advanced.resampling == nil)
    #expect(advanced.colorCalibration == true)
  }

  @Test func unknownValueDecodesAsAutomatic() throws {
    let advanced = try JSONDecoder().decode(AdvancedParameters.self, from: Data(#"{"resampling":"sinc"}"#.utf8))
    #expect(advanced.resampling == nil)
  }

  @Test func roundTripKeepsTheChoice() throws {
    var advanced = AdvancedParameters()
    advanced.resampling = .bSpline
    let back = try JSONDecoder().decode(AdvancedParameters.self, from: JSONEncoder().encode(advanced))
    #expect(back.resampling == .bSpline)
    let automatic = String(decoding: try JSONEncoder().encode(AdvancedParameters()), as: UTF8.self)
    #expect(!automatic.contains("resampling"))
  }
}

struct ResamplingAgentTests {
  @Test func automaticIsNilBothWays() {
    #expect(Resampling.agentValue(nil) == "automatic")
    #expect(Resampling.choice(agentValue: "automatic") == .some(nil))
  }

  @Test func namesRoundTrip() {
    for method in Resampling.allCases {
      #expect(Resampling.choice(agentValue: Resampling.agentValue(method)) == .some(method))
    }
  }

  @Test func unknownNameIsRejected() {
    #expect(Resampling.choice(agentValue: "sinc") == nil)
    #expect(Resampling.agentNames == ["automatic", "coreGraphics", "catmullRom", "mitchell", "bSpline", "bilinear", "lanczos", "nearest"])
  }
}
