import Foundation
import Testing

@testable import HubKit

struct MemoryMeterPresentationTests {
  let gb: UInt64 = 1_073_741_824
  let english = Locale(identifier: "en_US")
  let italian = Locale(identifier: "it_IT")

  func snapshot(
    total: UInt64 = 64, available: UInt64 = 30, app: UInt64 = 2, server: UInt64? = 20,
    pressure: MemoryPressureLevel = .normal, swap: UInt64 = 0
  ) -> MemorySnapshot {
    MemorySnapshot(
      totalBytes: total * gb, availableBytes: available * gb, appBytes: app * gb,
      serverBytes: server.map { $0 * gb }, swapUsedBytes: swap * gb, pressure: pressure)
  }

  @Test func theSegmentsAddUpToTheTotalAndTheRestIsWhatIsLeft() {
    let s = snapshot()  // 64 total, 30 free, 2 app, 20 server -> rest = 64 - 30 - 2 - 20 = 12
    #expect(s.restBytes == 12 * gb)
    #expect(s.usedBytes == 34 * gb)
  }

  @Test func theRestNeverGoesNegative() {
    let s = snapshot(available: 10, app: 30, server: 40)
    #expect(s.restBytes == 0)
  }

  @Test func withoutAServerThereIsNoServerSegment() {
    let result = MemoryMeterPresentation(snapshot: snapshot(server: nil), locale: english)
    #expect(result.segments.map(\.kind) == [.app, .rest, .free])
  }

  @Test func theSegmentsAreOrderedServerAppRestFreeAndTheirFractionsFillTheBar() {
    let result = MemoryMeterPresentation(snapshot: snapshot(), locale: english)
    #expect(result.segments.map(\.kind) == [.server, .app, .rest, .free])
    let sum = result.segments.map(\.fraction).reduce(0, +)
    #expect(abs(sum - 1) < 0.0001)
  }

  @Test func theCompactTextIsTheFreeMemoryInGigabytesAndFollowsTheLocale() {
    #expect(MemoryMeterPresentation(snapshot: snapshot(available: 18), locale: english).compact == "18 GB")
    #expect(MemoryMeterPresentation(snapshot: snapshot(available: 18), locale: italian).compact == "18 GB")
    let half = MemorySnapshot(
      totalBytes: 64 * gb, availableBytes: 18 * gb + gb / 2, appBytes: 0, serverBytes: nil, swapUsedBytes: 0, pressure: .normal)
    #expect(MemoryMeterPresentation(snapshot: half, locale: italian).compact == "18,5 GB")
    #expect(MemoryMeterPresentation(snapshot: half, locale: english).compact == "18.5 GB")
  }

  @Test func theStateFollowsThePressure() {
    #expect(MemoryMeterPresentation(snapshot: snapshot(pressure: .normal), locale: english).state == .ok)
    #expect(MemoryMeterPresentation(snapshot: snapshot(pressure: .warning), locale: english).state == .near)
    #expect(MemoryMeterPresentation(snapshot: snapshot(pressure: .critical), locale: english).state == .critical)
  }

  @Test func littleFreeMemoryIsNearEvenWithNormalPressure() {
    // Under 10 % of the total (64 GB -> 6.4 GB).
    #expect(MemoryMeterPresentation(snapshot: snapshot(available: 6), locale: english).state == .near)
    #expect(MemoryMeterPresentation(snapshot: snapshot(available: 7), locale: english).state == .ok)
  }

  @Test func swapInUseIsNearAtLeast() {
    #expect(MemoryMeterPresentation(snapshot: snapshot(swap: 2), locale: english).state == .near)
    #expect(MemoryMeterPresentation(snapshot: snapshot(pressure: .critical, swap: 2), locale: english).state == .critical)
  }

  @Test func twoSnapshotsThatLookTheSameAreEqualWhenRounded() {
    let a = snapshot()
    var b = a
    b.availableBytes += 10_000_000  // 10 MB: below the 0.1 GB the meter shows
    #expect(a.rounded() == b.rounded())
    b.availableBytes += gb
    #expect(a.rounded() != b.rounded())
  }

  @Test func aSnapshotWithNoTotalGivesAnEmptyBar() {
    let empty = MemorySnapshot(totalBytes: 0, availableBytes: 0, appBytes: 0, serverBytes: nil, swapUsedBytes: 0, pressure: .normal)
    let result = MemoryMeterPresentation(snapshot: empty, locale: english)
    #expect(result.segments.isEmpty)
  }
}
