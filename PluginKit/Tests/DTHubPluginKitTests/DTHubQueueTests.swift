import Foundation
import Testing

@testable import DTHubPluginKit

struct DTHubQueueTests {
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func captureParsesFolder() throws {
    let data = Data(#"{"type":"queue.capture","folder":"/tmp/entry/plugin"}"#.utf8)
    let request = try #require(DTHubQueueCapture(data))
    #expect(request.folder.path == "/tmp/entry/plugin")
  }

  @Test func captureWithoutFolderIsNil() {
    #expect(DTHubQueueCapture(Data(#"{"type":"queue.capture"}"#.utf8)) == nil)
  }

  @Test func prepareParsesStateModelFamily() throws {
    let data = Data(
      #"{"type":"queue.prepare","folder":"/tmp/e/plugin","state":{"factor":4,"image":"source.png"},"model":"flux.ckpt","family":"flux1"}"#
        .utf8)
    let request = try #require(DTHubQueuePrepare(data))
    #expect(request.folder.path == "/tmp/e/plugin")
    #expect(request.state["factor"] as? Int == 4)
    #expect(request.state["image"] as? String == "source.png")
    #expect(request.model == "flux.ckpt")
    #expect(request.family == "flux1")
  }

  @Test func prepareWithoutFamilyHasNilFamily() throws {
    let data = Data(#"{"type":"queue.prepare","folder":"/tmp/e","state":{},"model":"m"}"#.utf8)
    #expect(try #require(DTHubQueuePrepare(data)).family == nil)
  }

  @Test func prepareWithoutStateIsNil() {
    #expect(DTHubQueuePrepare(Data(#"{"type":"queue.prepare","folder":"/tmp/e"}"#.utf8)) == nil)
  }

  @Test func okCarriesState() throws {
    let message = try object(DTHubMessage.ok(state: ["image": "source.png"]))
    #expect(message["type"] as? String == "ok")
    #expect((message["state"] as? [String: Any])?["image"] as? String == "source.png")
  }

  @Test func okWithoutStateIsBare() throws {
    let message = try object(DTHubMessage.ok())
    #expect(message["type"] as? String == "ok")
    #expect(message["state"] == nil)
  }

  @Test func failureCarriesText() throws {
    let message = try object(DTHubMessage.failure("niente da fare"))
    #expect(message["type"] as? String == "error")
    #expect(message["text"] as? String == "niente da fare")
  }
}
