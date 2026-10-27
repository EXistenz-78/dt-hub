import Foundation
import Testing

@testable import HubKit

struct PluginQueueMessagesTests {
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func snapshot() throws -> QueueSnapshot { try #require(QueueSnapshot(jsonObject: ["image": "source.png", "factor": 4])) }

  @Test func captureRequestCarriesFolder() throws {
    let message = try object(PluginQueue.captureRequest(folder: URL(fileURLWithPath: "/tmp/e/plugin", isDirectory: true)))
    #expect(message["type"] as? String == "queue.capture")
    #expect(message["folder"] as? String == "/tmp/e/plugin")
  }

  @Test func prepareRequestCarriesStateModelAndFamily() throws {
    let message = try object(
      PluginQueue.prepareRequest(
        folder: URL(fileURLWithPath: "/tmp/e/plugin", isDirectory: true), state: try snapshot(), model: "flux.ckpt", family: "flux1"))
    #expect(message["type"] as? String == "queue.prepare")
    #expect(message["folder"] as? String == "/tmp/e/plugin")
    #expect(message["model"] as? String == "flux.ckpt")
    #expect(message["family"] as? String == "flux1")
    #expect((message["state"] as? [String: Any])?["image"] as? String == "source.png")
  }

  @Test func prepareRequestWithoutFamilyLeavesTheKeyOut() throws {
    let message = try object(
      PluginQueue.prepareRequest(folder: URL(fileURLWithPath: "/tmp/x", isDirectory: true), state: try snapshot(), model: "m", family: nil))
    #expect(message["family"] == nil)
  }

  @Test func parseCaptureOk() throws {
    let answer = Data(#"{"type":"ok","state":{"image":"source.png"}}"#.utf8)
    let result = PluginQueue.parseCapture(answer)
    #expect(try result.get().jsonObject["image"] as? String == "source.png")
  }

  @Test func parseCaptureNilIsNotLoaded() {
    #expect(PluginQueue.parseCapture(nil) == .failure(.notLoaded))
  }

  @Test func parseCaptureUnsupported() {
    #expect(PluginQueue.parseCapture(PluginMessageType.bare("unsupported")) == .failure(.unsupported))
  }

  @Test func parseCaptureErrorKeepsText() {
    #expect(PluginQueue.parseCapture(PluginMessageType.failure("niente da catturare")) == .failure(.refused("niente da catturare")))
  }

  @Test func parseCaptureOkWithoutStateIsRefused() {
    #expect(PluginQueue.parseCapture(PluginMessageType.bare("ok")) == .failure(.refused("")))
  }

  @Test func parsePrepareOkIsNil() {
    #expect(PluginQueue.parsePrepare(PluginMessageType.bare("ok")) == nil)
  }

  @Test func parsePrepareNilIsNotLoaded() {
    #expect(PluginQueue.parsePrepare(nil) == .notLoaded)
  }

  @Test func parsePrepareErrorKeepsText() {
    #expect(PluginQueue.parsePrepare(PluginMessageType.failure("manca il file")) == .refused("manca il file"))
  }

  @Test func parsePrepareUnsupported() {
    #expect(PluginQueue.parsePrepare(PluginMessageType.bare("unsupported")) == .unsupported)
  }
}
