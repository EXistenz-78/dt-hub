import ImageIO
import Foundation
import HubKit
import Testing

@testable import HubCore

struct PNGImageStoreTests {
  let job = GenerationJob(
    prompt: "a lighthouse at dusk", model: "flux_2_klein_9b_f16.ckpt",
    parameters: GenerationParameters(seed: 1234, randomSeed: false))
  let date = Date(timeIntervalSince1970: 1_790_000_000)

  func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PNGImageStoreTests-\(UUID())", isDirectory: true)
  }

  @Test func trashingAFileThatIsAlreadyGoneIsDone() throws {
    let store = PNGImageStore(folder: tempFolder())
    try store.trash(URL(fileURLWithPath: "/tmp/DTHub-gone-\(UUID()).png"))
  }

  @Test func savesAPNGWithTheJobInside() throws {
    let store = PNGImageStore(folder: tempFolder())
    let url = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(url.pathExtension == "png")
    #expect(url.lastPathComponent.hasSuffix("-1234.png"))
    #expect(PNGImageStore.job(in: url) == job)
  }

  @Test func aPromptWithAccentsAndSymbolsComesBackAsItWasWritten() throws {
    // The "UserComment" is stored as ASCII by ImageIO: a character outside it turned into "?".
    let text = "Tiled Upscale 4× · 3×3 tile · luminosità 100% · città, perché ✓ 日本語 😀"
    let accented = GenerationJob(prompt: text, negativePrompt: "sfocato — più", model: "m.ckpt", parameters: GenerationParameters(seed: 7, randomSeed: false))
    let url = try PNGImageStore(folder: tempFolder()).save(testImage(), job: accented, index: 0, date: date)
    #expect(PNGImageStore.job(in: url)?.prompt == text)
    #expect(PNGImageStore.job(in: url)?.negativePrompt == "sfocato — più")
  }

  @Test func theCommentStaysPlainASCIIAndStillReadsAsJSON() throws {
    let text = "4× · luminosità 😀"
    let accented = GenerationJob(prompt: text, model: "m.ckpt", parameters: GenerationParameters(seed: 7, randomSeed: false))
    let comment = PNGImageStore.legacyComment(for: accented, elapsed: 3)
    #expect(comment.unicodeScalars.allSatisfy { $0.isASCII }, "nothing that ASCII cannot hold")
    let object = try #require(try JSONSerialization.jsonObject(with: Data(comment.utf8)) as? [String: Any])
    #expect(object["prompt"] as? String == text)
  }

  @Test func theDescriptionIsThePromptSentWithItsTriggerWords() throws {
    let triggered = GenerationJob(
      prompt: "a fox", model: "m.ckpt",
      parameters: GenerationParameters(seed: 5, randomSeed: false, loras: [LoRASelection(file: "t", trigger: "vintage tarot style")]))
    let url = try PNGImageStore(folder: tempFolder()).save(testImage(), job: triggered, index: 0, date: date)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    #expect(png?[kCGImagePropertyPNGDescription] as? String == "vintage tarot style a fox")
    #expect(PNGImageStore.job(in: url) == triggered)
  }

  @Test func namesEachImageOfABatchAndNeverOverwrites() throws {
    let store = PNGImageStore(folder: tempFolder())
    let first = try store.save(testImage(), job: job, index: 0, date: date)
    let second = try store.save(testImage(), job: job, index: 1, date: date)
    let again = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(second.lastPathComponent.hasSuffix("-1234-2.png"))
    #expect(Set([first, second, again]).count == 3)
  }

  @Test func reportsAFolderItCannotCreate() {
    let store = PNGImageStore(folder: URL(fileURLWithPath: "/System/DT Hub test"))
    #expect(throws: ImageStoreError.self) { try store.save(testImage(), job: job, index: 0, date: date) }
  }

  @Test func theElapsedTimeIsSavedInsideAndTheJobStaysTheSame() throws {
    let store = PNGImageStore(folder: tempFolder())
    let url = try store.save(testImage(), job: job, index: 0, date: date, elapsed: 41.6)
    #expect(PNGImageStore.elapsed(in: url) == 41.6)
    #expect(PNGImageStore.job(in: url) == job)
  }

  @Test func aFileWithoutTheElapsedTimeHasNone() throws {
    let store = PNGImageStore(folder: tempFolder())
    let url = try store.save(testImage(), job: job, index: 0, date: date, elapsed: nil)
    #expect(PNGImageStore.elapsed(in: url) == nil)
    #expect(PNGImageStore.job(in: url) == job)
  }

  @Test func theElapsedTimeIsWrittenAsPlainText() {
    #expect(ElapsedText.label(41.6) == "42sec")
    #expect(ElapsedText.label(0.2) == "1sec")
    #expect(ElapsedText.label(1234) == "1234sec")
    #expect(ElapsedText.label(nil) == nil)
  }

  @Test func saveVideoWritesPosterAndMP4Together() async throws {
    let store = PNGImageStore(folder: tempFolder())
    let frames = (0..<3).map { _ in testImage(width: 256, height: 144) }
    let poster = try await store.saveVideo(
      GeneratedVideo(frames: frames, audio: nil, framesPerSecond: 24), job: job, date: date, elapsed: 2)
    let twin = PNGImageStore.videoURL(forPoster: poster)
    #expect(poster.pathExtension == "png")
    #expect(twin.pathExtension == "mp4")
    #expect(twin.deletingPathExtension() == poster.deletingPathExtension())
    #expect(FileManager.default.fileExists(atPath: poster.path))
    #expect(FileManager.default.fileExists(atPath: twin.path))
    #expect(PNGImageStore.job(in: poster) == job)
  }

  @Test func trashRemovesBothFiles() async throws {
    let store = PNGImageStore(folder: tempFolder())
    let frames = (0..<3).map { _ in testImage(width: 256, height: 144) }
    let poster = try await store.saveVideo(
      GeneratedVideo(frames: frames, audio: nil, framesPerSecond: 24), job: job, date: date, elapsed: nil)
    let twin = PNGImageStore.videoURL(forPoster: poster)
    try store.trash(poster)
    #expect(!FileManager.default.fileExists(atPath: poster.path))
    #expect(!FileManager.default.fileExists(atPath: twin.path))
    // A twin that is already gone is not an error.
    let lone = try store.save(testImage(), job: job, index: 5, date: date)
    try store.trash(lone)
  }

  @Test func saveVideoFailureRemovesThePoster() async throws {
    let folder = tempFolder()
    let store = PNGImageStore(folder: folder)
    let frames = (0..<2).map { _ in testImage(width: 256, height: 144) }
    let bad = GeneratedAudioTrack(channels: [[0, 0.1]], sampleRate: 0)
    await #expect(throws: ImageStoreError.self) {
      try await store.saveVideo(
        GeneratedVideo(frames: frames, audio: bad, framesPerSecond: 24), job: job, date: date, elapsed: nil)
    }
    let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
      .filter { !$0.hasDirectoryPath }
    #expect(files.isEmpty)
  }
}
