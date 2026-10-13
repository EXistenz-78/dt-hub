import DrawThingsClient
import Foundation
import Testing

@testable import DTBridge

/// Counts the downloads and answers what the test says.
final class FakeDownload: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  private var answer: Result<Data, any Error> = .failure(URLError(.notConnectedToInternet))
  var calls: Int { lock.withLock { count } }
  func set(_ text: String) { lock.withLock { answer = .success(Data(text.utf8)) } }
  func fail() { lock.withLock { answer = .failure(URLError(.notConnectedToInternet)) } }
  func get(_ url: URL) async throws -> Data {
    try lock.withLock {
      count += 1
      return try answer.get()
    }
  }
}

final class FakeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1_000_000)
  var now: Date { lock.withLock { date } }
  func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
}

struct LiveModelListTests {
  let cache = FileManager.default.temporaryDirectory
    .appendingPathComponent("live-models-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("models-list.json")
  let download = FakeDownload()
  let clock = FakeClock()
  static let two = #"[{"file":"qwen_image_2.1_turbo_i8x.ckpt","name":"Qwen Image 2.1 Turbo (8-bit S)","version":"qwen_image_2.1"},{"file":"b.ckpt","name":"B","version":"flux1"}]"#

  func list() -> LiveModelList {
    let download = download
    let clock = clock
    return LiveModelList(cacheURL: cache, download: { try await download.get($0) }, now: { clock.now })
  }

  func name(_ spec: Data?) -> String? {
    spec.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["name"] as? String
  }

  @Test func theListIsDownloadedSavedAndReadByFile() async throws {
    download.set(Self.two)
    let specs = await list().specs()
    #expect(specs.count == 2)
    #expect(name(specs["qwen_image_2.1_turbo_i8x.ckpt"]) == "Qwen Image 2.1 Turbo (8-bit S)")
    #expect(try Data(contentsOf: cache) == Data(Self.two.utf8))
  }

  @Test func withoutTheNetworkTheSavedCopyIsUsed() async {
    download.set(Self.two)
    _ = await list().specs()
    download.fail()
    // Another launch, offline.
    let specs = await list().specs()
    #expect(specs.count == 2)
  }

  @Test func withNeitherThereIsNothing() async {
    #expect(await list().specs().isEmpty)
  }

  @Test(arguments: ["<html>down</html>", "{}", "[]", #"[{"name":"no file"}]"#, ""])
  func anAnswerThatIsNotTheListDoesNotReplaceTheSavedCopy(answer: String) async throws {
    download.set(Self.two)
    _ = await list().specs()
    download.set(answer)
    #expect(await list().specs().count == 2)
    #expect(try Data(contentsOf: cache) == Data(Self.two.utf8))
  }

  @Test func entriesWithoutAFileAreSkipped() async {
    download.set(#"[{"file":"a.ckpt","name":"A"},{"name":"x"},7,{"file":""}]"#)
    #expect(await list().specs().keys.sorted() == ["a.ckpt"])
  }

  @Test func theListIsDownloadedOncePerLaunch() async {
    download.set(Self.two)
    let list = list()
    for _ in 0..<5 { _ = await list.specs() }
    clock.advance(24 * 3600)
    _ = await list.specs()
    #expect(download.calls == 1)
  }

  @Test func aFailedDownloadIsTriedAgainOnlyAfterTenMinutes() async {
    let list = list()
    _ = await list.specs()
    _ = await list.specs()
    #expect(download.calls == 1)
    clock.advance(9 * 60)
    _ = await list.specs()
    #expect(download.calls == 1)
    clock.advance(2 * 60)
    download.set(Self.two)
    #expect(await list.specs().count == 2)
    #expect(download.calls == 2)
  }

  @Test func theSpecsOfTheFilesTheServerHasAreTheOnesToRegister() {
    let live = ["a.ckpt": Data(#"{"file":"a.ckpt","name":"A","version":"flux1"}"#.utf8), "z.ckpt": Data(#"{"file":"z.ckpt"}"#.utf8), "bad.ckpt": Data("x".utf8)]
    let specs = DrawThingsBackend.specs(toRegisterFor: ["a.ckpt", "other.ckpt", "bad.ckpt"], live: live)
    #expect(specs.map(\.file) == ["a.ckpt"] && specs.first?.version == "flux1")
  }
}
