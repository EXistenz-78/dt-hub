/// The base generation parameters of the Generation tab (spec §6, level 1), for T2I.
public struct GenerationParameters: Equatable, Codable, Sendable {
  /// Pixels; Draw Things works in multiples of 64.
  public var width: Int
  public var height: Int
  public var steps: Int
  /// Text guidance (CFG).
  public var guidanceScale: Double
  /// CFG-Zero*: guidance starts after `cfgZeroInitSteps` steps.
  public var cfgZeroStar: Bool
  public var cfgZeroInitSteps: Int
  public var sampler: Sampler
  public var shift: Double
  /// When on, Draw Things computes the shift from the resolution and `shift` is ignored.
  public var resolutionDependentShift: Bool
  /// Used as is when `randomSeed` is off; otherwise a new one is drawn at each RUN.
  public var seed: UInt32
  public var randomSeed: Bool
  /// Images per batch, and batches per RUN.
  public var batchSize: Int
  public var batchCount: Int
  /// The LoRAs of the LoRA card, in order; one entry per file.
  public var loras: [LoRASelection]
  /// The Advanced cards (spec §6, level 2).
  public var advanced: AdvancedParameters
  /// Draw Things settings DT Hub has no card for, from the JSON editor (spec §6, level 3):
  /// kept as they are, sent with every RUN, saved with the session and in the PNG.
  public var extra: [String: JSONValue]

  public init(
    width: Int = 1024, height: Int = 1024, steps: Int = 8, guidanceScale: Double = 1,
    cfgZeroStar: Bool = false, cfgZeroInitSteps: Int = 0,
    sampler: Sampler = .uniPCTrailing, shift: Double = 3, resolutionDependentShift: Bool = true,
    seed: UInt32 = 0, randomSeed: Bool = true, batchSize: Int = 1, batchCount: Int = 1,
    loras: [LoRASelection] = [], advanced: AdvancedParameters = .default,
    extra: [String: JSONValue] = [:]
  ) {
    self.width = width
    self.height = height
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.cfgZeroStar = cfgZeroStar
    self.cfgZeroInitSteps = cfgZeroInitSteps
    self.sampler = sampler
    self.shift = shift
    self.resolutionDependentShift = resolutionDependentShift
    self.seed = seed
    self.randomSeed = randomSeed
    self.batchSize = batchSize
    self.batchCount = batchCount
    self.loras = loras
    self.advanced = advanced
    self.extra = extra
  }

  /// Reads saved parameters leniently: a missing or unreadable field takes its default, so
  /// files written by older or newer versions (session, PNG metadata) still load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let fallback = Self.default
    width = value(.width, fallback.width)
    height = value(.height, fallback.height)
    steps = value(.steps, fallback.steps)
    guidanceScale = value(.guidanceScale, fallback.guidanceScale)
    cfgZeroStar = value(.cfgZeroStar, fallback.cfgZeroStar)
    cfgZeroInitSteps = value(.cfgZeroInitSteps, fallback.cfgZeroInitSteps)
    sampler = value(.sampler, fallback.sampler)
    shift = value(.shift, fallback.shift)
    resolutionDependentShift = value(.resolutionDependentShift, fallback.resolutionDependentShift)
    seed = value(.seed, fallback.seed)
    randomSeed = value(.randomSeed, fallback.randomSeed)
    batchSize = value(.batchSize, fallback.batchSize)
    batchCount = value(.batchCount, fallback.batchCount)
    loras = value(.loras, fallback.loras)
    advanced = value(.advanced, fallback.advanced)
    extra = value(.extra, fallback.extra)
  }

  public static let `default` = GenerationParameters()

  /// Adds a LoRA (full weight unless its metadata suggests one); a file already in the
  /// list is left as it is.
  public mutating func addLoRA(_ file: String, weight: Double = 1, trigger: String = "") {
    guard !loras.contains(where: { $0.file == file }) else { return }
    loras.append(LoRASelection(file: file, weight: weight, trigger: trigger))
  }

  public mutating func removeLoRA(_ file: String) {
    loras.removeAll { $0.file == file }
  }

  /// Replaces the LoRA with the same file, wherever it is now; nothing when it was removed.
  /// The LoRA card's rows write through this, not through an array index: a row that ends
  /// its edit after a removal must not write into another LoRA or past the end.
  public mutating func updateLoRA(_ selection: LoRASelection) {
    guard let index = loras.firstIndex(where: { $0.file == selection.file }) else { return }
    loras[index] = selection
  }

  /// Allowed ranges, used by the cards and by `clamped()`.
  public static let sizeRange = 64...2048
  public static let stepsRange = 1...150
  public static let guidanceRange = 0.0...50.0
  public static let shiftRange = 0.0...10.0
  public static let batchSizeRange = 1...4
  public static let batchCountRange = 1...100

  /// Portrait ↔ landscape. One mutation: `swap(&p.width, &p.height)` on an observed property
  /// is two overlapping accesses to the same struct and crashes at run time.
  public mutating func swapDimensions() {
    (width, height) = (height, width)
  }

  /// Applies an aspect ratio keeping the long side and the orientation (portrait stays portrait).
  public mutating func apply(_ ratio: AspectRatio) {
    let long = max(width, height)
    let short = Self.snap(Double(long) * Double(ratio.height) / Double(ratio.width))
    if height > width {
      (width, height) = (short, Self.snap(Double(long)))
    } else {
      (width, height) = (Self.snap(Double(long)), short)
    }
  }

  /// Sets the width; with a ratio (width ÷ height) the height follows to keep it.
  public mutating func setWidth(_ newWidth: Int, keepingRatio ratio: Double?) {
    width = newWidth
    if let ratio, ratio > 0 { height = Self.snap(Double(newWidth) / ratio) }
  }

  /// Sets the height; with a ratio (width ÷ height) the width follows to keep it.
  public mutating func setHeight(_ newHeight: Int, keepingRatio ratio: Double?) {
    height = newHeight
    if let ratio, ratio > 0 { width = Self.snap(Double(newHeight) * ratio) }
  }

  /// The same parameters forced into the allowed ranges; sizes rounded to the nearest multiple
  /// of 64, as the size fields do when editing ends.
  public func clamped() -> GenerationParameters {
    var copy = self
    copy.width = Self.snap(Double(width))
    copy.height = Self.snap(Double(height))
    copy.steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
    copy.guidanceScale = min(max(guidanceScale, Self.guidanceRange.lowerBound), Self.guidanceRange.upperBound)
    copy.cfgZeroInitSteps = min(max(cfgZeroInitSteps, 0), copy.steps)
    copy.shift = min(max(shift, Self.shiftRange.lowerBound), Self.shiftRange.upperBound)
    copy.batchSize = min(max(batchSize, Self.batchSizeRange.lowerBound), Self.batchSizeRange.upperBound)
    copy.batchCount = min(max(batchCount, Self.batchCountRange.lowerBound), Self.batchCountRange.upperBound)
    for index in copy.loras.indices {
      let range = LoRASelection.weightRange
      copy.loras[index].weight = min(max(copy.loras[index].weight, range.lowerBound), range.upperBound)
    }
    copy.advanced = advanced.clamped()
    return copy
  }

  /// Nearest multiple of 64 inside `sizeRange`.
  public static func snap(_ size: Double) -> Int {
    let rounded = Int((size / 64).rounded()) * 64
    return min(max(rounded, sizeRange.lowerBound), sizeRange.upperBound)
  }
}
