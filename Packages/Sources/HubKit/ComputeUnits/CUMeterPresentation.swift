import Foundation

/// The estimate of one request of a RUN, set against the limit; nil when it could not be told.
public struct CUPassReading: Equatable, Sendable {
  public var title: String
  public var reading: CUReading?

  public init(title: String, reading: CUReading?) {
    self.title = title
    self.reading = reading
  }
}

/// What the header's CU meter shows (spec §5): the heaviest request of the RUN, as "32,4k / 40k", with its share of
/// the limit and its state.
public struct CUMeterPresentation: Equatable, Sendable {
  public let compact: String
  /// The share of the limit, capped at 1.25 so the bar stays inside its place; nil without an estimate.
  public let fraction: Double?
  public let state: CUState?
  public let heaviest: CUPassReading?

  public init(passes: [CUPassReading], locale: Locale) {
    var best: CUPassReading?
    for pass in passes {
      guard let reading = pass.reading else { continue }
      if let current = best?.reading, current.cu >= reading.cu { continue }
      best = pass
    }
    heaviest = best
    guard let reading = best?.reading else {
      compact = "—"
      fraction = nil
      state = nil
      return
    }
    compact = "\(Self.thousands(reading.cu, locale: locale)) / \(Self.thousands(reading.limit, locale: locale))"
    fraction = min(Double(reading.cu) / Double(max(1, reading.limit)), 1.25)
    state = reading.state
  }

  /// 32 400 → "32,4k" (locale `it`), 40 000 → "40k": one decimal, none when it is zero.
  static func thousands(_ value: Int, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.roundingMode = .halfUp
    return (formatter.string(from: NSNumber(value: Double(value) / 1000)) ?? "\(value / 1000)") + "k"
  }
}
