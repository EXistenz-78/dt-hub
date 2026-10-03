import Foundation
import Testing

@testable import HubKit

struct ContributionReviewTests {
  @Test func aLoRAWeightFromAPluginIsLimitedLikeTheCardLimitsIt() throws {
    let message = Data(#"{"loras":[{"file":"a.ckpt","weight":50},{"file":"b.ckpt","weight":-9}],"pipeline":{"steps":[{"loras":[{"file":"c.ckpt","weight":99}]}]}}"#.utf8)
    let contribution = try #require(PluginContribution(message: message))
    #expect(contribution.loras.map(\.weight) == [LoRASelection.weightRange.upperBound, LoRASelection.weightRange.lowerBound])
    #expect(contribution.pipeline?.steps.first?.loras?.first?.weight == LoRASelection.weightRange.upperBound)
  }
}
