import Foundation
import Testing

@testable import SeamlessPattern

@Suite("SPSender")
struct SPSenderTests {
  @Test func prepareBothIsTheExactJSON() throws {
    let data = SPSender.prepare(mode: .both)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(
      text
        == #"{"pipeline":{"name":"Seamless","steps":[{"seamless":"both","title":"Seamless"}]},"type":"contribute"}"#)
  }

  @Test func prepareCarriesTheModeAndNothingElse() throws {
    for mode in SPMode.allCases {
      let json = try #require(JSONSerialization.jsonObject(with: SPSender.prepare(mode: mode)) as? [String: Any])
      #expect(json["type"] as? String == "contribute")
      let pipeline = try #require(json["pipeline"] as? [String: Any])
      let step = try #require((pipeline["steps"] as? [[String: Any]])?.first)
      #expect(Set(step.keys) == ["title", "seamless"])
      #expect(step["seamless"] as? String == mode.rawValue)
      #expect(Set(json.keys) == ["type", "pipeline"])
    }
  }

  @Test func stopWithdrawsOnlyThePipeline() throws {
    let text = try #require(String(data: SPSender.stop(), encoding: .utf8))
    #expect(text == #"{"pipeline":null,"type":"contribute"}"#)
  }

  @Test func theBodyIsWhatTheHostAddsTheTypeTo() throws {
    let body = try #require(SPSender.body(SPSender.prepare(mode: .upDown)))
    #expect(body["type"] == nil)
    #expect(body["pipeline"] != nil)
    let stop = try #require(SPSender.body(SPSender.stop()))
    #expect(stop["pipeline"] is NSNull)
  }
}
