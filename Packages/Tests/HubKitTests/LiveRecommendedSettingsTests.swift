import Foundation
import Testing

@testable import HubKit

final class CountingDownload: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  private var answer: Data?
  var calls: Int { lock.withLock { count } }
  func set(_ text: String?) { lock.withLock { answer = text.map { Data($0.utf8) } } }
  func get(_ url: URL) async throws -> Data {
    try lock.withLock {
      count += 1
      guard let answer else { throw URLError(.notConnectedToInternet) }
      return answer
    }
  }
}

final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1_000_000)
  var now: Date { lock.withLock { date } }
  func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
}

struct CachedDownloadTests {
  let cache = FileManager.default.temporaryDirectory
    .appendingPathComponent("cached-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("list.json")
  let download = CountingDownload()
  let clock = TestClock()

  func source() -> CachedDownload {
    let download = download
    let clock = clock
    return CachedDownload(
      address: URL(string: "https://example.com/list.json")!, cacheURL: cache, isValid: { $0.first == UInt8(ascii: "[") && $0.count > 2 },
      download: { try await download.get($0) }, now: { clock.now })
  }

  @Test func whatIsDownloadedIsSavedAndGivenBack() async throws {
    download.set("[1]")
    #expect(await source().data() == Data("[1]".utf8))
    #expect(try Data(contentsOf: cache) == Data("[1]".utf8))
  }

  @Test func withoutTheNetworkTheSavedCopyIsGiven() async {
    download.set("[1]")
    _ = await source().data()
    download.set(nil)
    #expect(await source().data() == Data("[1]".utf8))
  }

  @Test func withNeitherThereIsNothing() async {
    #expect(await source().data() == nil)
  }

  @Test func anAnswerThatIsNotValidDoesNotReplaceTheSavedCopy() async throws {
    download.set("[1]")
    _ = await source().data()
    download.set("<html>")
    #expect(await source().data() == Data("[1]".utf8))
    #expect(try Data(contentsOf: cache) == Data("[1]".utf8))
  }

  @Test func oneDownloadPerLaunchAndARetryOnlyAfterTenMinutes() async {
    let source = source()
    _ = await source.data()
    _ = await source.data()
    #expect(download.calls == 1)
    clock.advance(9 * 60)
    _ = await source.data()
    #expect(download.calls == 1)
    clock.advance(2 * 60)
    download.set("[2]")
    #expect(await source.data() == Data("[2]".utf8))
    clock.advance(24 * 3600)
    _ = await source.data()
    #expect(download.calls == 2)
  }
}

struct LiveRecommendedSettingsTests {
  static let list = """
    [{"name":"Qwen Image 2.1 Turbo","version":"qwen_image_2.1","configuration":{"model":"qwen_image_2.1_turbo_q8p.ckpt","steps":8,"guidanceScale":1,"sampler":16,"shift":6.5,"resolutionDependentShift":false}},
     {"name":"Qwen Image 2.1","version":"qwen_image_2.1","configuration":{"model":"qwen_image_2.1_q8p.ckpt","steps":40,"guidanceScale":1,"sampler":16,"shift":1,"resolutionDependentShift":true}},
     {"name":"With Lightning","version":"qwen_image","configuration":{"model":"qwen_image_1.0_q8p.ckpt","steps":4,"guidanceScale":1,"sampler":16,"loras":[{"file":"x.ckpt"}]}},
     {"name":"No steps","version":"flux1","configuration":{"model":"flux_1_dev_q8p.ckpt","guidanceScale":1,"sampler":16}},
     {"name":"No shift","version":"newfam","configuration":{"model":"new_model_f16.ckpt","steps":20,"guidanceScale":4.5,"sampler":0}},
     7, {"name":"no configuration"}]
    """

  @Test func theListOfDrawThingsGivesTheValuesOfEachModel() {
    let table = RecommendedSettings(configurations: Data(Self.list.utf8))
    let turbo = table.values(forFile: "qwen_image_2.1_turbo_i8x.ckpt", family: nil)
    #expect(turbo == RecommendedValues(steps: 8, guidanceScale: 1, sampler: Sampler(rawValue: 16)!, shift: 6.5, resolutionDependentShift: false))
    #expect(table.values(forFile: "qwen_image_2.1_f16.ckpt", family: nil)?.steps == 40)
    #expect(table.values(forFile: "new_model_q6p.ckpt", family: nil) == RecommendedValues(steps: 20, guidanceScale: 4.5, sampler: Sampler(rawValue: 0)!))
    // The entries that use LoRAs are not the model's base values; those without the basic ones say nothing.
    #expect(table.values(forFile: "qwen_image_1.0_q8p.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "flux_1_dev_q8p.ckpt", family: nil) == nil)
    #expect(RecommendedSettings(configurations: Data("x".utf8)) == .empty)
  }

  @Test func theLiveListAddsModelsButDoesNotChangeTheFamiliesTheAppKnows() {
    let base = RecommendedValues(steps: 40, guidanceScale: 1, sampler: Sampler(rawValue: 16)!, shift: 1, resolutionDependentShift: true)
    let old = RecommendedValues(steps: 30, guidanceScale: 3, sampler: Sampler(rawValue: 16)!)
    let app = RecommendedSettings(models: ["qwen_image_2.1": old, "kept": old], families: ["qwen_image_2.1": base])
    let merged = app.merging(RecommendedSettings(configurations: Data(Self.list.utf8)))
    // A model the app did not know.
    #expect(merged.values(forFile: "qwen_image_2.1_turbo_i8x.ckpt", family: "qwen_image_2.1")?.steps == 8)
    // The live values of a model win over the app's.
    #expect(merged.values(forFile: "qwen_image_2.1_q8p.ckpt", family: nil)?.steps == 40)
    #expect(merged.values(forFile: "kept_q8p.ckpt", family: nil) == old)
    // In the live list the Turbo comes first: it must not become what every other Qwen 2.1 file falls back to.
    #expect(merged.values(forFile: "some_other_qwen_q8p.ckpt", family: "qwen_image_2.1") == base)
    // A family the app did not know is taken from the live list.
    #expect(merged.values(forFile: "unknown.ckpt", family: "newfam")?.steps == 20)
  }
}
