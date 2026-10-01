import Darwin
import Foundation

/// The language model's folder, choice and memory behavior (spec §9, §11).
public struct LanguageModelSettings: Equatable, Codable, Sendable {
  /// Where the models are (spec §9: `/Volumes/LLM-VLM/MLX` unless the user chooses another).
  public var folder: String
  /// The folder of the model in use; empty until one is chosen.
  public var selectedModel: String
  /// Frees the language model from memory when RUN is pressed, so Draw Things has the room.
  public var freeAtRun: Bool
  /// Stops the managed Draw Things server before the language model loads, so it has the room
  /// (the image model is reloaded at the next RUN, which takes time). Only with the server DT
  /// Hub starts: DT has no call to unload a model from another server.
  public var freeImageModelForLanguageModel: Bool
  /// Minutes without use after which the language model is freed; 0 = never.
  public var idleMinutes: Int

  public static let defaultFolder = "/Volumes/LLM-VLM/MLX"
  /// Macs with at least this much memory keep both models loaded unless told otherwise.
  public static let comfortableMemory: UInt64 = 64 * 1_073_741_824

  public init(
    folder: String = defaultFolder, selectedModel: String = "", freeAtRun: Bool = true,
    freeImageModelForLanguageModel: Bool = true, idleMinutes: Int = 10
  ) {
    self.folder = folder
    self.selectedModel = selectedModel
    self.freeAtRun = freeAtRun
    self.freeImageModelForLanguageModel = freeImageModelForLanguageModel
    self.idleMinutes = idleMinutes
  }

  /// The memory options on by default only on Macs with less than 64 GB (decided with the
  /// user, 1 October 2026): from 64 GB up both models fit.
  public static func defaults(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> LanguageModelSettings {
    let tight = physicalMemory < comfortableMemory
    return LanguageModelSettings(freeAtRun: tight, freeImageModelForLanguageModel: tight)
  }

  public static let idleRange = 0...240

  /// The settings forced into their ranges.
  public func clamped() -> LanguageModelSettings {
    var copy = self
    copy.idleMinutes = min(max(idleMinutes, Self.idleRange.lowerBound), Self.idleRange.upperBound)
    return copy
  }

  /// Lenient: a missing field takes the default for this Mac.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.defaults()
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    folder = value(.folder, fallback.folder)
    selectedModel = value(.selectedModel, fallback.selectedModel)
    freeAtRun = value(.freeAtRun, fallback.freeAtRun)
    freeImageModelForLanguageModel = value(.freeImageModelForLanguageModel, fallback.freeImageModelForLanguageModel)
    idleMinutes = value(.idleMinutes, fallback.idleMinutes)
  }
}

/// Persists `LanguageModelSettings` in UserDefaults as JSON (spec §11).
public struct LanguageModelSettingsStore {
  private let defaults: UserDefaults
  static let key = "languageModel.settings"
  private let physicalMemory: UInt64

  public init(defaults: UserDefaults = .standard, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
    self.defaults = defaults
    self.physicalMemory = physicalMemory
  }

  /// The saved settings; the defaults for this Mac's memory when nothing was saved.
  public func load() -> LanguageModelSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(LanguageModelSettings.self, from: data)
    else { return .defaults(physicalMemory: physicalMemory) }
    return settings.clamped()
  }

  public func save(_ settings: LanguageModelSettings) {
    defaults.set(try? JSONEncoder().encode(settings.clamped()), forKey: Self.key)
  }
}

/// Memory the system could give to a program right now.
public struct MemoryProbe: Sendable {
  public var availableBytes: @Sendable () -> Int64

  public init(availableBytes: @escaping @Sendable () -> Int64) {
    self.availableBytes = availableBytes
  }

  /// Free, inactive, speculative and purgeable pages: what the system hands out without
  /// pushing anything to disk.
  public static let live = MemoryProbe {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &statistics) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return Int64.max }
    let pages = UInt64(statistics.free_count) + UInt64(statistics.inactive_count)
      + UInt64(statistics.speculative_count) + UInt64(statistics.purgeable_count)
    return Int64(pages) * Int64(sysconf(_SC_PAGESIZE))
  }
}
