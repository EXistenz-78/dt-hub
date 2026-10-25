import Testing

@testable import HubCore

struct ResultFilingTests {
  @Test func theModelOfTheFilingIsTheGuidedOneThenTheHeaders() {
    #expect(ResultFiling.model(guided: "g.ckpt", header: "h.ckpt") == "g.ckpt")
    #expect(ResultFiling.model(guided: nil, header: "h.ckpt") == "h.ckpt")
    #expect(ResultFiling.model(guided: "", header: "h.ckpt") == "h.ckpt")
    #expect(ResultFiling.model(guided: nil, header: nil) == nil)
    #expect(ResultFiling.model(guided: nil, header: "") == nil)
  }
}
