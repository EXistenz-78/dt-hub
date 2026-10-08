import Foundation
import Testing

@testable import CharacterSheet

@Suite("CSMessages")
struct CSMessagesTests {
  /// The body as the app will read it: through JSON.
  private func roundTrip(_ body: [String: Any]) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: body)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func moodboardBody() throws {
    let body = try roundTrip(CSMessages.moodboard(imagePath: "/t/my ref.png"))
    #expect(Set(body.keys) == ["moodboard"])
    let pictures = try #require(body["moodboard"] as? [[String: Any]])
    #expect(pictures.count == 1)
    #expect(pictures[0]["path"] as? String == "/t/my ref.png")
    #expect(pictures[0]["name"] as? String == "Character reference")
  }

  @Test func sizeBody() throws {
    let body = try roundTrip(CSMessages.size())
    #expect(Set(body.keys) == ["fields"])
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(Set(fields.keys) == ["width", "height"])
    #expect(fields["width"] as? Int == 2048)
    #expect(fields["height"] as? Int == 1536)
  }

  @Test func promptBody() throws {
    let text = "1. \"Title\"\n\n2. Café – 日本語"
    let body = try roundTrip(CSMessages.prompt(text))
    #expect(Set(body.keys) == ["fields"])
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(Set(fields.keys) == ["prompt"])
    #expect(fields["prompt"] as? String == text)
  }

  @Test func sizeIsFourToThreeAndMultipleOf64() {
    #expect(CSMessages.width * 3 == CSMessages.height * 4)
    #expect(CSMessages.width % 64 == 0)
    #expect(CSMessages.height % 64 == 0)
  }

  @Test func allBodiesSerialize() {
    #expect(JSONSerialization.isValidJSONObject(CSMessages.moodboard(imagePath: "/a")))
    #expect(JSONSerialization.isValidJSONObject(CSMessages.size()))
    #expect(JSONSerialization.isValidJSONObject(CSMessages.prompt("x")))
  }
}
