import Foundation

/// A page the plug-in can read (spec §6.2).
enum LALink: Equatable {
  case civitai(model: Int, version: Int?)
  /// "author/repo".
  case huggingFace(repo: String)

  /// The link the user pasted, when it is a model page of Civitai (civitai.com or civitai.red) or a repository of
  /// Hugging Face; nil for anything else.
  static func parse(_ text: String) -> LALink? {
    guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, var host = parts.host?.lowercased()
    else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    let path = parts.path.split(separator: "/").map(String.init)
    switch host {
    case "civitai.com", "civitai.red":
      guard path.count >= 2, path[0] == "models", let model = Int(path[1]), model > 0 else { return nil }
      let version = parts.queryItems?.first { $0.name == "modelVersionId" }?.value.flatMap(Int.init)
      return .civitai(model: model, version: version)
    case "huggingface.co":
      guard path.count >= 2, !reserved.contains(path[0].lowercased()) else { return nil }
      return .huggingFace(repo: path[0] + "/" + path[1])
    default:
      return nil
    }
  }

  /// The link as it is kept: always on civitai.com, without the slug.
  var canonical: String {
    switch self {
    case .civitai(let model, let version):
      "https://civitai.com/models/\(model)" + (version.map { "?modelVersionId=\($0)" } ?? "")
    case .huggingFace(let repo): "https://huggingface.co/\(repo)"
    }
  }

  /// First path segments of huggingface.co that are not an author.
  private static let reserved: Set<String> = [
    "models", "datasets", "spaces", "docs", "api", "settings", "login", "join", "pricing", "blog", "tasks", "collections",
    "organizations", "posts", "papers", "learn", "chat",
  ]
}

/// The addresses the plug-in contacts (spec §6.5): Civitai and Hugging Face with their own servers, over https only.
enum LAHosts {
  static let bases = ["civitai.com", "huggingface.co", "hf.co"]

  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased()
    else { return false }
    return bases.contains { host == $0 || host.hasSuffix("." + $0) }
  }
}
