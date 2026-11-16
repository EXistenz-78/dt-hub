import Foundation
import Testing

@testable import HubKit

@Suite struct LocalEditSessionTests {
  private let image = ReferenceImage(
    id: UUID(), name: "start", pixelWidth: 2048, pixelHeight: 1536, source: .result, fileName: "start.png")

  @Test func anOldControlFileHasNoSession() throws {
    let data = Data(#"{"framing":{"zoom":0,"offsetX":0,"offsetY":0,"rotation":0},"moodboard":[]}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: data).localEdit == nil)
  }

  @Test func theSessionRoundTrips() throws {
    var session = LocalEditSession(
      id: UUID(), rect: PixelRect(x: 64, y: 128, width: 1024, height: 512), original: image,
      framing: Framing(zoom: 10, offsetX: 0.5, offsetY: -0.5, rotation: 15),
      mask: MaskReference(fileName: "mask.png", coverage: 0.25), paint: PaintReference(fileName: "paint.png"),
      strength: 0.8, marginFill: .gray, generationWidth: 1024, generationHeight: 512, generationHighRes: true,
      openedAt: Date(timeIntervalSince1970: 1_800_000_000))
    session.matchColors = false
    var inputs = ControlInputs(image: image)
    inputs.localEdit = session
    let data = try JSONEncoder().encode(inputs)
    let decoded = try JSONDecoder().decode(ControlInputs.self, from: data)
    #expect(decoded == inputs)
    #expect(decoded.localEdit?.matchColors == false)
    #expect(decoded.localEdit?.rect.cgRect == CGRect(x: 64, y: 128, width: 1024, height: 512))
  }

  @Test func aSessionWithoutAnImageIsDropped() throws {
    let session = LocalEditSession(
      id: UUID(), rect: PixelRect(x: 0, y: 0, width: 512, height: 512), original: image, framing: Framing(),
      mask: nil, paint: nil, strength: nil, marginFill: nil, generationWidth: 512, generationHeight: 512,
      generationHighRes: false, openedAt: Date(timeIntervalSince1970: 0))
    var inputs = ControlInputs(image: image)
    inputs.localEdit = session
    var json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(inputs)) as? [String: Any])
    json["image"] = nil
    #expect(json["localEdit"] != nil)
    let data = try JSONSerialization.data(withJSONObject: json)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: data).localEdit == nil)
  }
}
