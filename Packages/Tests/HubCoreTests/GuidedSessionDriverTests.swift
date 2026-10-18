import Foundation
import Testing

@testable import HubCore
@testable import HubKit

@MainActor
struct GuidedSessionDriverTests {
  /// Records what the driver asked of the plug-in and of the app.
  final class Log {
    var asked: [SessionNextRequest] = []
    var passes: [Int] = []
    var ended: [String] = []
    var progress: [String] = []
  }

  private static let validPass = Data(
    #"{"startImage":{"path":"/t/tile.png"},"size":{"width":512,"height":1024}}"#.utf8)

  private func request(_ data: Data) -> SessionNextRequest {
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    var previous: SessionPrevious?
    if let box = object["previous"] as? [String: Any] {
      previous = SessionPrevious(path: box["path"] as! String, width: box["width"] as! Int, height: box["height"] as! Int)
    }
    return SessionNextRequest(index: object["index"] as! Int, count: object["count"] as! Int, previous: previous)
  }

  private func driver(
    passes: Int, log: Log, answer: @escaping (Int) -> Data? = { _ in GuidedSessionDriverTests.validPass },
    outcome: @escaping (Int) -> PassOutcome = { .made(URL(fileURLWithPath: "/t/pass-\($0).png"), width: 512, height: 1024) }
  ) -> GuidedSessionDriver {
    GuidedSessionDriver(
      passes: passes, tileLimit: 2048,
      ask: { [self] data in
        let asked = request(data)
        log.asked.append(asked)
        return answer(asked.index)
      },
      runPass: { _, index in
        log.passes.append(index)
        return outcome(index)
      },
      end: { data in
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        log.ended.append(object["reason"] as! String)
      },
      progress: { log.progress.append("\($0)/\($1)") })
  }

  @Test func runsEveryPassInOrderAndEndsFinished() async {
    let log = Log()
    let outcome = await driver(passes: 3, log: log).run()
    #expect(outcome == .finished)
    #expect(log.passes == [1, 2, 3])
    #expect(log.asked.map(\.previous?.path) == [nil, "/t/pass-1.png", "/t/pass-2.png"])
    #expect(log.ended == ["finished"])
  }

  @Test func doneEndsTheSessionEarlyWithoutError() async {
    let log = Log()
    let outcome = await driver(passes: 3, log: log, answer: { $0 == 2 ? Data(#"{"done":true}"#.utf8) : GuidedSessionDriverTests.validPass }).run()
    #expect(outcome == .finished)
    #expect(log.passes == [1])
    #expect(log.ended == ["finished"])
  }

  @Test func invalidAnswerFailsWithTheReason() async {
    let log = Log()
    let bad = Data(#"{"startImage":{"path":"/t/a.png"},"size":{"width":1000,"height":1024}}"#.utf8)
    let outcome = await driver(passes: 3, log: log, answer: { _ in bad }).run()
    #expect(outcome == .failed("size must be a multiple of 64"))
    #expect(log.passes.isEmpty)
    #expect(log.ended == ["failed"])
  }

  @Test func stopDuringAPassEndsStoppedAndAsksNoMore() async {
    let log = Log()
    let outcome = await driver(passes: 4, log: log, outcome: { $0 == 2 ? .stopped : .made(URL(fileURLWithPath: "/t/p.png"), width: 512, height: 1024) }).run()
    #expect(outcome == .stopped)
    #expect(log.asked.count == 2)
    #expect(log.ended == ["stopped"])
  }

  @Test func aFailedPassStopsEverything() async {
    let log = Log()
    let outcome = await driver(passes: 3, log: log, outcome: { _ in .failed("boom") }).run()
    #expect(outcome == .failed("boom"))
    #expect(log.passes == [1])
    #expect(log.ended == ["failed"])
  }

  @Test func noAnswerClosesTheSession() async {
    let log = Log()
    let outcome = await driver(passes: 3, log: log, answer: { _ in nil }).run()
    #expect(outcome == .closed)
    #expect(log.passes.isEmpty)
    #expect(log.ended == ["closed"])
  }

  @Test func cancellationBeforeAPassStops() async {
    let log = Log()
    var handle: Task<GuidedOutcome, Never>?
    let driver = GuidedSessionDriver(
      passes: 3, tileLimit: 2048,
      ask: { _ in GuidedSessionDriverTests.validPass },
      runPass: { _, index in
        log.passes.append(index)
        handle?.cancel()
        return .made(URL(fileURLWithPath: "/t/p.png"), width: 512, height: 1024)
      },
      end: { data in
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        log.ended.append(object["reason"] as! String)
      })
    handle = Task { await driver.run() }
    let outcome = await handle!.value
    #expect(outcome == .stopped)
    #expect(log.passes == [1])
    #expect(log.ended == ["stopped"])
  }

  @Test func reportsProgress() async {
    let log = Log()
    _ = await driver(passes: 3, log: log).run()
    #expect(log.progress == ["1/3", "2/3", "3/3"])
  }
}
