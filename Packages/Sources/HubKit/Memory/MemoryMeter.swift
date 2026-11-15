import Foundation

/// How hard the system is pressed for memory (what Activity Monitor draws as green, yellow, red).
public enum MemoryPressureLevel: Int, Equatable, Sendable, Codable {
  case normal, warning, critical
}

/// One reading of the memory of the Mac: unified memory is shared by the app, the image server and the rest.
public struct MemorySnapshot: Equatable, Sendable {
  public var totalBytes: UInt64
  /// Free, inactive, speculative and purgeable: what the system hands out without writing anything to disk.
  public var availableBytes: UInt64
  /// The footprint of DT Hub itself (language models run inside it).
  public var appBytes: UInt64
  /// The footprint of the image server (gRPCServerCLI or Draw Things); nil when it could not be found.
  public var serverBytes: UInt64?
  public var swapUsedBytes: UInt64
  public var pressure: MemoryPressureLevel

  public init(
    totalBytes: UInt64, availableBytes: UInt64, appBytes: UInt64, serverBytes: UInt64?, swapUsedBytes: UInt64,
    pressure: MemoryPressureLevel
  ) {
    self.totalBytes = totalBytes
    self.availableBytes = availableBytes
    self.appBytes = appBytes
    self.serverBytes = serverBytes
    self.swapUsedBytes = swapUsedBytes
    self.pressure = pressure
  }

  public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }

  /// Everything used that is neither the app nor the server: the rest of the system.
  public var restBytes: UInt64 {
    let known = appBytes + (serverBytes ?? 0)
    return usedBytes > known ? usedBytes - known : 0
  }

  /// The snapshot as the meter shows it (tenths of a GB), so a reading that looks the same is not published again.
  public func rounded() -> MemorySnapshot {
    func step(_ value: UInt64) -> UInt64 { (value + Self.tenth / 2) / Self.tenth * Self.tenth }
    return MemorySnapshot(
      totalBytes: step(totalBytes), availableBytes: step(availableBytes), appBytes: step(appBytes),
      serverBytes: serverBytes.map(step), swapUsedBytes: step(swapUsedBytes), pressure: pressure)
  }

  static let tenth: UInt64 = 107_374_182
}

public enum MemoryState: Equatable, Sendable {
  case ok, near, critical
}

public enum MemorySegmentKind: Equatable, Sendable {
  case server, app, rest, free
}

public struct MemorySegment: Equatable, Sendable {
  public var kind: MemorySegmentKind
  public var bytes: UInt64
  /// The share of the total memory, 0...1.
  public var fraction: Double
}

/// What the memory meter under the progress bar shows: a bar of segments and the free memory ("18 GB"; the view adds
/// the word, which is localized there).
public struct MemoryMeterPresentation: Equatable, Sendable {
  public let segments: [MemorySegment]
  public let compact: String
  public let state: MemoryState

  /// Under this share of free memory the meter is amber even with a normal pressure.
  static let nearShare = 0.10

  public init(snapshot: MemorySnapshot, locale: Locale) {
    let total = Double(snapshot.totalBytes)
    var parts: [(MemorySegmentKind, UInt64)] = []
    if let server = snapshot.serverBytes { parts.append((.server, server)) }
    parts += [(.app, snapshot.appBytes), (.rest, snapshot.restBytes), (.free, snapshot.availableBytes)]
    segments = total > 0 ? parts.map { MemorySegment(kind: $0.0, bytes: $0.1, fraction: Double($0.1) / total) } : []
    compact = Self.gigabytes(snapshot.availableBytes, locale: locale)

    var state: MemoryState
    switch snapshot.pressure {
    case .critical: state = .critical
    case .warning: state = .near
    case .normal: state = .ok
    }
    if state == .ok, snapshot.swapUsedBytes > 0 { state = .near }
    if state == .ok, total > 0, Double(snapshot.availableBytes) / total < Self.nearShare { state = .near }
    self.state = state
  }

  /// 19 818 086 400 → "18,5 GB": one decimal, none when it is zero.
  public static func gigabytes(_ bytes: UInt64, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return (formatter.string(from: NSNumber(value: Double(bytes) / 1_073_741_824)) ?? "0") + " GB"
  }
}
