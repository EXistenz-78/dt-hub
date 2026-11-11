import Foundation

/// The address of LM Studio's server. Only this Mac is accepted: nothing of the user's leaves the computer.
public enum LMStudioAddress {
  public static let defaultURL = "http://localhost:1235/v1"
  private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

  /// The base URL (`http://localhost:1235/v1`) when `text` is `http` on this Mac with a port; nil otherwise.
  /// Spaces and a trailing slash are dropped; an address with no path (`http://127.0.0.1:11435`) gets `/v1`, which is
  /// where the OpenAI API lives (an address with another path is left as the user wrote it).
  public static func validated(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard var components = URLComponents(string: trimmed), components.scheme == "http",
      let host = components.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
      localHosts.contains(host), components.port != nil
    else { return nil }
    if components.path.isEmpty { components.path = "/v1" }
    return components.url
  }

  /// `…/chat/completions` of the OpenAI API.
  public static func chatURL(_ base: URL) -> URL { base.appendingPathComponent("chat/completions") }

  /// `…/models` of the OpenAI API.
  public static func modelsURL(_ base: URL) -> URL { base.appendingPathComponent("models") }

  /// LM Studio's own list (`/api/v0/models`), which also says the type of each model.
  public static func nativeModelsURL(_ base: URL) -> URL {
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
    components.path = "/api/v0/models"
    return components.url ?? base
  }
}
