/// The Draw Things samplers by the number the app sends in `parameters.sampler`.
enum SamplerNames {
  static let names = [
    "DPM++ 2M Karras", "Euler Ancestral", "DDIM", "PLMS", "DPM++ SDE Karras", "UniPC", "LCM", "Euler A Substep",
    "DPM++ SDE Substep", "TCD", "Euler A Trailing", "DPM++ SDE Trailing", "DPM++ 2M AYS", "Euler A AYS", "DPM++ SDE AYS",
    "DPM++ 2M Trailing", "DDIM Trailing", "UniPC Trailing", "UniPC AYS", "TCD Trailing",
  ]

  static func name(_ number: Int) -> String { names.indices.contains(number) ? names[number] : "#\(number)" }
}
