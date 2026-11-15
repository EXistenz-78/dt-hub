import HubKit
import Observation

/// Samples the memory while a run goes on and publishes it for the meter under the progress bar. It only runs while
/// asked to (`run`), publishes a reading only when it differs at the precision the meter shows, and reads off the
/// main actor.
@MainActor
@Observable
public final class MemoryMonitor {
  public static let defaultInterval: Duration = .seconds(1)

  public private(set) var snapshot: MemorySnapshot?
  /// How many times the reading was really published (a test looks at it; the views do not).
  @ObservationIgnored public private(set) var publications = 0

  @ObservationIgnored private let sampler: MemorySampler
  @ObservationIgnored private let serverPid: @MainActor () -> Int32?
  @ObservationIgnored private var found: Int32?

  /// `serverPid`: the pid of the server DT Hub started, nil when there is none (then the sampler finds it).
  public init(sampler: MemorySampler = .live, serverPid: @escaping @MainActor () -> Int32?) {
    self.sampler = sampler
    self.serverPid = serverPid
  }

  /// One reading.
  public func refresh() async {
    let sampler = sampler
    var pid = serverPid() ?? found
    if pid == nil {
      pid = await Task.detached { sampler.findServer() }.value
      found = pid
    }
    let target = pid
    let reading = await Task.detached { sampler.sample(target) }.value
    guard let reading else { return }
    // A server that is gone is looked for again at the next reading.
    if reading.serverBytes == nil { found = nil }
    guard snapshot?.rounded() != reading.rounded() else { return }
    snapshot = reading
    publications += 1
  }

  /// Samples every `interval` until the calling task is cancelled.
  public func run(
    every interval: Duration = defaultInterval,
    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) async {
    while !Task.isCancelled {
      await refresh()
      do { try await sleep(interval) } catch { return }
    }
  }
}
