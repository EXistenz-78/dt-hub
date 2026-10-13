import Foundation

/// Which base models of Civitai go with which model family of Draw Things, to leave out of a search the LoRAs made
/// for another model (spec §6.1). When in doubt a result is kept: a family or a base model this table does not know
/// fits everything.
enum LAFamily {
  /// True unless the base model and the family are both known and are not the same.
  static func fits(baseModel: String?, family: String?) -> Bool {
    guard let ours = group(ofFamily: family), let theirs = group(ofBaseModel: baseModel) else { return true }
    return ours == theirs
  }

  /// The group of a family key of Draw Things ("flux2_9b", "krea_2", "v1"…); nil when unknown.
  static func group(ofFamily key: String?) -> String? {
    guard let key, !key.isEmpty else { return nil }
    let name = LAName.key(key)
    if name.contains("flux29b") { return "flux2-klein-9b" }
    if name.contains("flux24b") { return "flux2-klein-4b" }
    if name == "flux2" { return "flux2-dev" }
    if name.hasPrefix("flux1") { return "flux1" }
    if name.contains("krea") { return "krea2" }
    if name.contains("qwen") { return "qwen" }
    if name.contains("zimage") { return "zimage" }
    if name.contains("sdxl") || name.contains("ssd1b") { return "sdxl" }
    if name.hasPrefix("sd3") { return "sd3" }
    if name == "v2" { return "sd2" }
    if name == "v1" { return "sd1" }
    return shared(name) ?? (["wan", "hunyuan", "ltx", "svd"].contains { name.contains($0) } ? "video" : nil)
  }

  /// The group of a base model as Civitai names it ("Krea 2", "Flux.2 Klein 9B-base", "SD 1.5"…); nil when unknown.
  static func group(ofBaseModel base: String?) -> String? {
    guard let base, !base.isEmpty else { return nil }
    let name = LAName.key(base)
    if name.contains("flux2klein9b") { return "flux2-klein-9b" }
    if name.contains("flux2klein4b") { return "flux2-klein-4b" }
    if name.hasPrefix("flux2") { return "flux2-dev" }
    if name.hasPrefix("flux1") { return "flux1" }
    if name.contains("krea2") { return "krea2" }
    if name.contains("qwen") { return "qwen" }
    if name.contains("zimage") { return "zimage" }
    if ["sdxl", "pony", "illustrious", "noobai"].contains(where: { name.contains($0) }) { return "sdxl" }
    if name.hasPrefix("sd3") { return "sd3" }
    if name.hasPrefix("sd2") { return "sd2" }
    if name.hasPrefix("sd1") { return "sd1" }
    return shared(name) ?? (["wanvideo", "hunyuanvideo", "ltxv", "svd"].contains { name.contains($0) } ? "video" : nil)
  }

  /// The words authors put in a title for the family ("Krea 2", "Z-Image"): added to a search, they bring up the
  /// LoRAs for that model first. Nil for a family without a common wording.
  static func label(ofFamily key: String?) -> String? {
    switch group(ofFamily: key) {
    case "krea2": "Krea 2"
    case "zimage": "Z-Image"
    case "flux2-klein-9b": "Klein 9B"
    case "flux2-klein-4b": "Klein 4B"
    case "flux2-dev": "Flux.2"
    case "flux1": "Flux"
    case "qwen": "Qwen"
    case "sdxl": "SDXL"
    case "sd1": "SD 1.5"
    case "ideogram": "Ideogram"
    default: nil
    }
  }

  /// A title without the words that only say which model it is for, whether the author's ("[KREA 2] Detail Slider")
  /// or the user's own tag ("K2 Detail Slider"): what is left is the LoRA's name on both sides. Whole words only.
  static func withoutFamilyWords(_ title: String, family key: String?) -> String {
    guard let group = group(ofFamily: key), let sequences = words[group] else { return title }
    var tokens = title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    var index = 0
    while index < tokens.count {
      let rest = tokens[index...].map { $0.lowercased() }
      if let hit = sequences.first(where: { rest.starts(with: $0) }) {
        tokens.removeSubrange(index..<(index + hit.count))
      } else {
        index += 1
      }
    }
    return tokens.joined(separator: " ")
  }

  /// The ways a family is written, as words in lower case, the longest first.
  private static let flux2: [[String]] = [
    ["flux", "2", "klein", "9b"], ["flux", "2", "klein", "4b"], ["flux", "2", "klein"], ["flux2", "klein", "9b"],
    ["flux2", "klein", "4b"], ["flux2", "klein"], ["klein", "9b"], ["klein", "4b"], ["flux", "2", "dev"], ["flux", "2"],
    ["klein"], ["flux2"], ["f2"],
  ]
  private static let words: [String: [[String]]] = [
    "krea2": [["krea", "2"], ["krea2"], ["krea"], ["k2"]],
    "zimage": [["z", "image", "turbo"], ["z", "image", "base"], ["z", "image"], ["zimage"], ["zit"], ["zib"], ["zi"]],
    "flux2-klein-9b": flux2, "flux2-klein-4b": flux2, "flux2-dev": flux2,
    "flux1": [["flux", "1", "dev"], ["flux", "1", "d"], ["flux", "1"], ["flux1"], ["flux"]],
    "qwen": [["qwen", "image", "2", "1"], ["qwen", "image", "edit"], ["qwen", "image"], ["qwen", "2", "1"], ["qwen"], ["q21"]],
    "sdxl": [["sdxl"], ["pony"], ["illustrious"]],
    "sd1": [["sd", "1", "5"], ["sd15"]],
    "ideogram": [["ideogram", "4"], ["ideogram4"], ["ideogram"], ["ideo4"], ["i4"]],
  ]

  /// The names the two sides write alike.
  private static func shared(_ name: String) -> String? {
    ["hidream", "pixart", "ideogram", "anima", "chroma", "ernie"].first { name.contains($0) }
  }
}
