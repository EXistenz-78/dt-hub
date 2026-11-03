import Foundation
import Testing

@testable import HubCore

struct LMStudioSettingsTests {
  @Test func validatedAcceptsOnlyLocalHttpWithAPort() {
    #expect(LMStudioAddress.validated("http://localhost:1235/v1") != nil)
    #expect(LMStudioAddress.validated("http://127.0.0.1:1235/v1") != nil)
    #expect(LMStudioAddress.validated("http://[::1]:1235/v1") != nil)
    #expect(LMStudioAddress.validated("http://192.168.1.5:1235/v1") == nil)
    #expect(LMStudioAddress.validated("https://localhost:1235/v1") == nil)
    #expect(LMStudioAddress.validated("http://localhost/v1") == nil)
    #expect(LMStudioAddress.validated("localhost:1235") == nil)
    #expect(LMStudioAddress.validated("") == nil)
  }

  @Test func validatedDropsATrailingSlashAndSpaces() {
    #expect(LMStudioAddress.validated("  http://localhost:1235/v1/ ")?.absoluteString == "http://localhost:1235/v1")
  }

  @Test func urlsAreBuiltFromTheBase() throws {
    let base = try #require(LMStudioAddress.validated(LMStudioAddress.defaultURL))
    #expect(LMStudioAddress.chatURL(base).absoluteString == "http://localhost:1235/v1/chat/completions")
    #expect(LMStudioAddress.modelsURL(base).absoluteString == "http://localhost:1235/v1/models")
    #expect(LMStudioAddress.nativeModelsURL(base).absoluteString == "http://localhost:1235/api/v0/models")
  }

  @Test func oldSettingsLoadAsFolder() throws {
    let decoded = try JSONDecoder().decode(LanguageModelSettings.self, from: Data(#"{"folder": "/x"}"#.utf8))
    #expect(decoded.backend == .folder)
    #expect(decoded.serverURL == LMStudioAddress.defaultURL)
    #expect(decoded.serverVisionModels.isEmpty)
  }

  @Test func theNewFieldsRoundTrip() throws {
    let settings = LanguageModelSettings(
      backend: .lmStudio, serverURL: "http://localhost:1234/v1", serverVisionModels: ["a"])
    let back = try JSONDecoder().decode(LanguageModelSettings.self, from: JSONEncoder().encode(settings))
    #expect(back == settings)
  }
}
