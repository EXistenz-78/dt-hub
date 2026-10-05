import Testing

@testable import DTHubPluginKit

@Suite("DTHubPluginKit")
struct DTHubPluginKitTests {
  @Test func theContractVersionIsStillOne() {
    #expect(DTHubContract.current == 1)
  }

  @Test func aBareMessageIsAnObjectWithItsType() {
    #expect(DTHubMessage.type(of: DTHubMessage.bare("ok")) == "ok")
  }
}
