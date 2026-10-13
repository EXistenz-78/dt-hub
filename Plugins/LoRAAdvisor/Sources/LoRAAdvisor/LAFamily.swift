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

  /// The names the two sides write alike.
  private static func shared(_ name: String) -> String? {
    ["hidream", "pixart", "ideogram"].first { name.contains($0) }
  }
}
