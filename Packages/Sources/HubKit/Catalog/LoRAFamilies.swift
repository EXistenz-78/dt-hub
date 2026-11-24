/// Which model families run the LoRAs of another family. The rule stays "a LoRA runs only on the family it was
/// made for"; a family listed here also runs the LoRAs of the families it shares its network with. The table
/// names families, not files, so a LoRA added later for one of them works on the other at once.
public enum LoRAFamilies {
  /// Model family → the other LoRA families it runs. Ming-Image's DiT is Z-Image's graph with the same weight
  /// names; the server (Atelier fork) runs a Z-Image LoRA on Ming-Image as its own (`LoRAZoo.versionForModel(_:runningWith:)`).
  static let borrowed: [String: Set<String>] = [
    "ming_image": ["z_image"],
  ]

  /// Whether a LoRA made for `loraFamily` runs on a model of `modelFamily`.
  public static func runs(loraFamily: String, onModelFamily modelFamily: String) -> Bool {
    loraFamily == modelFamily || borrowed[modelFamily]?.contains(loraFamily) == true
  }

  /// The model families a LoRA made for `loraFamily` runs on: its own first, then the others by name.
  public static func modelFamilies(runningLoRAsOf loraFamily: String) -> [String] {
    [loraFamily] + borrowed.filter { $0.value.contains(loraFamily) }.keys.sorted()
  }
}
