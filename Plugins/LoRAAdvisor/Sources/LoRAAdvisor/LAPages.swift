import Foundation

/// What the plug-in takes from a LoRA's page: its text, made plain, and the address of its first picture.
struct LAPage: Equatable {
  var text: String
  var imageURL: URL?
}

/// Civitai's public API (no key): a model by its number, and the search by name.
enum LACivitai {
  static func modelURL(_ id: Int) -> URL { URL(string: "https://civitai.com/api/v1/models/\(id)")! }

  /// `nsfw=true` is needed: without it the search leaves the adult LoRAs out.
  static func searchURL(_ query: String) -> URL {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let text = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    return URL(string: "https://civitai.com/api/v1/models?query=\(text)&types=LORA&limit=10&nsfw=true")!
  }

  /// The page of a model: the version the link names, or the first one. A version that is not public needs an account.
  static func page(json: Data, version: Int?) throws(LAFetchError) -> LAPage {
    guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
      let versions = root["modelVersions"] as? [[String: Any]], let first = versions.first
    else { throw .unreadable }
    let named = version.flatMap { wanted in versions.first { ($0["id"] as? Int) == wanted } }
    let chosen = named ?? first
    if let availability = chosen["availability"] as? String, availability != "Public" { throw .needsAccess }
    var lines = [LAText.plain(fromHTML: root["description"] as? String ?? "")]
    // In a bundle each version is another LoRA: its own name and notes say which.
    if named != nil {
      if let name = chosen["name"] as? String, !name.isEmpty { lines.append("Version: " + name) }
      let about = LAText.plain(fromHTML: chosen["description"] as? String ?? "", limit: 1500)
      if !about.isEmpty { lines.append(about) }
    }
    if let base = chosen["baseModel"] as? String, !base.isEmpty { lines.append("Base model: " + base) }
    if let words = chosen["trainedWords"] as? [String], !words.isEmpty {
      lines.append("Trigger words: " + words.joined(separator: ", "))
    }
    let image = (chosen["images"] as? [[String: Any]] ?? []).lazy
      .filter { ($0["type"] as? String) != "video" }
      .compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
      .first(where: LAHosts.isAllowed)
    return LAPage(text: lines.filter { !$0.isEmpty }.joined(separator: "\n"), imageURL: image)
  }

  /// The number of the first model the search found whose name is the LoRA's (`LAName.matches`); nil when none is.
  static func match(json: Data, name: String) -> Int? {
    guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
      let items = root["items"] as? [[String: Any]]
    else { return nil }
    return items.first { LAName.matches(lora: name, result: $0["name"] as? String ?? "") }?["id"] as? Int
  }
}

/// Hugging Face: the repository's list of files and its model card.
enum LAHuggingFace {
  static func apiURL(repo: String) -> URL { URL(string: "https://huggingface.co/api/models/" + encoded(repo))! }
  static func readmeURL(repo: String) -> URL { URL(string: "https://huggingface.co/\(encoded(repo))/raw/main/README.md")! }

  /// The text is the card without its YAML block. The picture is the card's first example (`widget`), then the first
  /// picture the card shows, then the first picture file of the repository; many repositories have none.
  static func page(api: Data, readme: String, repo: String) -> LAPage {
    let root = (try? JSONSerialization.jsonObject(with: api)) as? [String: Any] ?? [:]
    let widgets = ((root["cardData"] as? [String: Any])?["widget"] as? [[String: Any]] ?? [])
      .compactMap { ($0["output"] as? [String: Any])?["url"] as? String }
    let files = (root["siblings"] as? [[String: Any]] ?? []).compactMap { $0["rfilename"] as? String }
      .filter { ["png", "jpg", "jpeg", "webp"].contains(($0 as NSString).pathExtension.lowercased()) }
    let image = (widgets + cited(in: readme) + files).lazy.compactMap { address($0, repo: repo) }.first
    return LAPage(text: LAText.plain(fromHTML: LAText.withoutFrontMatter(readme)), imageURL: image)
  }

  /// The pictures a card shows, in the order they appear: `![…](…)` and `<img src="…">`.
  private static func cited(in readme: String) -> [String] {
    guard let pattern = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)\\s]+)|<img[^>]+src=[\"']([^\"']+)[\"']", options: .caseInsensitive)
    else { return [] }
    return pattern.matches(in: readme, range: NSRange(readme.startIndex..., in: readme)).compactMap { match in
      [1, 2].lazy.compactMap { Range(match.range(at: $0), in: readme) }.first.map { String(readme[$0]) }
    }
  }

  /// A picture's address: an allowed one as it is, a path of the repository under `resolve/main`. Vector badges and
  /// other hosts are left out.
  private static func address(_ text: String, repo: String) -> URL? {
    guard (text as NSString).pathExtension.lowercased() != "svg" else { return nil }
    if text.contains("://") {
      return URL(string: text).flatMap { LAHosts.isAllowed($0) ? $0 : nil }
    }
    var path = text
    while path.hasPrefix("./") { path.removeFirst(2) }
    while path.hasPrefix("/") { path.removeFirst() }
    guard !path.isEmpty, !path.hasPrefix("..") else { return nil }
    return URL(string: "https://huggingface.co/\(encoded(repo))/resolve/main/" + encoded(path))
  }

  private static func encoded(_ path: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~/")
    return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
  }
}
