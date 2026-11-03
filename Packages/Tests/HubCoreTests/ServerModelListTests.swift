import Foundation
import HubKit
import Testing

@testable import HubCore

struct ServerModelListTests {
  let base = URL(string: "http://localhost:1235/v1")!

  struct Offline: Error {}

  /// A server that answers each path with the given body; a path that is not there throws.
  func list(_ answers: [String: String]) -> ServerModelList {
    ServerModelList { url in
      guard let body = answers[url.path] else { throw Offline() }
      return Data(body.utf8)
    }
  }

  let native = #"""
    {"data":[{"id":"a","type":"llm"},{"id":"v","type":"vlm"},{"id":"e","type":"embeddings"}]}
    """#

  @Test func nativeListKeepsLlmAndVlmAndDropsEmbeddings() async throws {
    let models = try await list(["/api/v0/models": native]).models(base: base, visionModels: [])
    #expect(models.map(\.name) == ["a", "v"])
    #expect(models[1].supportsImages)
    #expect(!models[0].supportsImages)
    #expect(models[0].sizeBytes == 0)
    #expect(models[0].path == "lmstudio://a")
  }

  @Test func visionTogglesMarkAModelAsReadingImages() async throws {
    let models = try await list(["/api/v0/models": native]).models(base: base, visionModels: ["a"])
    #expect(models[0].supportsImages)
  }

  @Test func fallsBackToTheOpenAIListWhenTheNativeOneFails() async throws {
    let openAI = #"""
      {"data":[{"id":"a"},{"id":"text-embedding-nomic-embed-text-v1.5"}]}
      """#
    let models = try await list(["/v1/models": openAI]).models(base: base, visionModels: [])
    #expect(models.map(\.name) == ["a"])
  }

  @Test func bothFailingThrowsLoadFailedWithAPlainSentence() async {
    do {
      _ = try await list([:]).models(base: base, visionModels: [])
      Issue.record("it should have thrown")
    } catch let error as LanguageModelError {
      guard case .loadFailed(let text) = error else {
        Issue.record("wrong error \(error)")
        return
      }
      #expect(text.contains("localhost:1235"))
    } catch {
      Issue.record("wrong error \(error)")
    }
  }

  @Test func isSortedByName() async throws {
    let body = #"{"data":[{"id":"b","type":"llm"},{"id":"a","type":"llm"}]}"#
    let models = try await list(["/api/v0/models": body]).models(base: base, visionModels: [])
    #expect(models.map(\.name) == ["a", "b"])
  }
}
