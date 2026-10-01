import Foundation
import Testing

@testable import HubCore
@testable import HubKit

/// A downloader that waits for the test: reports 0.5, then holds until told to go on.
actor FakeDownloader: LanguageModelDownloader {
  private(set) var calls: [String] = []
  var failure: LanguageModelError?
  private let gate = Gate()

  func fail(with error: LanguageModelError?) { failure = error }
  func finish() async { await gate.open() }

  func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    calls.append(repository)
    progress(0.5)
    await gate.wait()
    try Task.checkCancellation()
    if let failure { throw failure }
  }
}

@MainActor
struct LanguageModelDownloadTests {
  func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
  }

  @Test func oneDownloadAtATime() async throws {
    let downloader = FakeDownloader()
    let controller = LanguageModelDownloadController(downloader: downloader)
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    try await waitUntil { controller.progress == 0.5 }
    #expect(await downloader.calls == ["a/b"])
    await downloader.finish()
    try await waitUntil { !controller.isDownloading }
    #expect(controller.failure == nil)
  }

  @Test func showsTheProgressUntilItEnds() async throws {
    let downloader = FakeDownloader()
    let controller = LanguageModelDownloadController(downloader: downloader)
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    try await waitUntil { controller.progress == 0.5 }
    #expect(controller.isDownloading)
    await downloader.finish()
    try await waitUntil { !controller.isDownloading }
    #expect(controller.progress == nil)
    #expect(controller.completed == 1)
  }

  @Test func cancellingEndsWithoutAFailure() async throws {
    let downloader = FakeDownloader()
    let controller = LanguageModelDownloadController(downloader: downloader)
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    try await waitUntil { controller.isDownloading }
    controller.cancel()
    await downloader.finish()
    try await waitUntil { !controller.isDownloading }
    #expect(controller.failure == nil)
    #expect(controller.completed == 0)
  }

  @Test func aFailureIsKeptUntilTheNextAttempt() async throws {
    let downloader = FakeDownloader()
    await downloader.fail(with: .downloadFailed("no network"))
    let controller = LanguageModelDownloadController(downloader: downloader)
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    await downloader.finish()
    try await waitUntil { !controller.isDownloading && controller.failure != nil }
    #expect(controller.failure == .downloadFailed("no network"))
    await downloader.fail(with: nil)
    controller.start(repository: "a/b", to: URL(fileURLWithPath: "/tmp/x"))
    #expect(controller.failure == nil)
  }
}
