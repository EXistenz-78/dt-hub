import CryptoKit
import Foundation
import Testing

@testable import DepthPose

/// Writes known bytes instead of going to the network; can wait at a gate or fail on a file.
final class FakeDownloader: DPFileDownloading, @unchecked Sendable {
  var contents: [String: Data] = [:]
  var failOn: String?
  var gate: AsyncGate?
  private let lock = NSLock()
  private var _calls: [String] = []
  var calls: [String] { lock.withLock { _calls } }

  func download(_ url: URL, to file: URL, progress: @Sendable (Int64) -> Void) async throws {
    lock.withLock { _calls.append(url.lastPathComponent) }
    if let gate { await gate.wait() }
    try Task.checkCancellation()
    if failOn == url.lastPathComponent { throw DPModelError.network("boom") }
    let data = contents[url.lastPathComponent] ?? Data()
    progress(Int64(data.count / 2))
    try data.write(to: file)
    progress(Int64(data.count))
  }
}

/// Holds a download until the test lets it go.
actor AsyncGate {
  private var open = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if open { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func release() {
    open = true
    waiters.forEach { $0.resume() }
    waiters = []
  }
}

@Suite("DPModelStore")
struct DPModelStoreTests {
  let manifestData = Data(#"{"a":1}"#.utf8)
  let weightData = Data(repeating: 9, count: 5000)

  private func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  private func files(weightSum: String? = nil, weightSize: Int64? = nil) -> [DPModelFile] {
    [
      DPModelFile(path: "M.mlpackage/Manifest.json", size: Int64(manifestData.count), sha256: nil),
      DPModelFile(
        path: "M.mlpackage/Data/weight.bin", size: weightSize ?? Int64(weightData.count),
        sha256: weightSum ?? hex(weightData)),
    ]
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dpm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func downloader() -> FakeDownloader {
    let d = FakeDownloader()
    d.contents = ["Manifest.json": manifestData, "weight.bin": weightData]
    return d
  }

  /// A "compile" that copies the package to a folder with a marker, and a "validate" that looks for the marker.
  private func store(
    _ folder: URL, files: [DPModelFile], downloader: any DPFileDownloading, compileFails: Bool = false,
    opens: Bool = true
  ) -> DPModelStore {
    DPModelStore(
      folder: folder, files: files, packageName: "M.mlpackage", downloader: downloader,
      compile: { package in
        if compileFails { throw DPModelError.compileFailed }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).mlmodelc")
        try FileManager.default.copyItem(at: package, to: out)
        try Data("ok".utf8).write(to: out.appendingPathComponent("marker"))
        return out
      },
      validate: { opens && FileManager.default.fileExists(atPath: $0.appendingPathComponent("marker").path) })
  }

  private func leftovers(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix(".download-") }
  }

  @Test func installDownloadsVerifiesCompilesAndMoves() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = store(folder, files: files(), downloader: downloader())
    #expect(!store.isPresent())
    try await store.install { _ in }
    #expect(store.isPresent())
    #expect(FileManager.default.fileExists(atPath: store.compiledURL.path))
    #expect(FileManager.default.fileExists(atPath: store.packageURL.appendingPathComponent("Manifest.json").path))
    #expect(leftovers(folder).isEmpty)
  }

  @Test func progressGoesFromZeroToOne() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let seen = LockedValue<[Double]>([])
    try await store(folder, files: files(), downloader: downloader()).install { value in seen.update { $0.append(value) } }
    let values = seen.value
    #expect(values.first == 0 && values.last == 1)
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func aWrongSizeFailsAndLeavesNothing() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = store(folder, files: files(weightSize: 4999), downloader: downloader())
    await #expect(throws: DPModelError.wrongSize("M.mlpackage/Data/weight.bin")) { try await store.install { _ in } }
    #expect(!store.isPresent() && leftovers(folder).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.packageURL.path))
  }

  @Test func aWrongChecksumFailsAndLeavesNothing() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = store(folder, files: files(weightSum: String(repeating: "0", count: 64)), downloader: downloader())
    await #expect(throws: DPModelError.wrongChecksum("M.mlpackage/Data/weight.bin")) { try await store.install { _ in } }
    #expect(!store.isPresent() && leftovers(folder).isEmpty)
  }

  @Test func aDownloadErrorLeavesNothing() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let d = downloader()
    d.failOn = "weight.bin"
    let store = store(folder, files: files(), downloader: d)
    await #expect(throws: DPModelError.network("boom")) { try await store.install { _ in } }
    #expect(!store.isPresent() && leftovers(folder).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.packageURL.path))
  }

  @Test func aCompileFailureLeavesNothing() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = store(folder, files: files(), downloader: downloader(), compileFails: true)
    await #expect(throws: DPModelError.compileFailed) { try await store.install { _ in } }
    #expect(!store.isPresent() && leftovers(folder).isEmpty)
  }

  @Test func cancellingLeavesNothing() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let d = downloader()
    let gate = AsyncGate()
    d.gate = gate
    let store = store(folder, files: files(), downloader: d)
    let task = Task { try await store.install { _ in } }
    while d.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    task.cancel()
    await gate.release()
    await #expect(throws: DPModelError.cancelled) { try await task.value }
    #expect(!store.isPresent() && leftovers(folder).isEmpty)
  }

  @Test func aModelThatDoesNotOpenIsNotPresent() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let good = store(folder, files: files(), downloader: downloader())
    try await good.install { _ in }
    let damaged = store(folder, files: files(), downloader: downloader(), opens: false)
    #expect(FileManager.default.fileExists(atPath: damaged.compiledURL.path))
    #expect(!damaged.isPresent())
  }

  @Test func reinstallingReplacesADamagedModel() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = store(folder, files: files(), downloader: downloader())
    try await store.install { _ in }
    try Data().write(to: store.compiledURL.appendingPathComponent("marker"))
    try FileManager.default.removeItem(at: store.compiledURL.appendingPathComponent("marker"))
    #expect(!store.isPresent())
    try await store.install { _ in }
    #expect(store.isPresent())
  }

  @Test func aSecondInstallWhileOneRunsIsRefused() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let d = downloader()
    let gate = AsyncGate()
    d.gate = gate
    let store = store(folder, files: files(), downloader: d)
    let first = Task { try await store.install { _ in } }
    while d.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    await #expect(throws: DPModelError.busy) { try await store.install { _ in } }
    #expect(d.calls.count == 1)
    await gate.release()
    try await first.value
    #expect(store.isPresent())
  }

  @Test func cleanUpLeftoversRemovesTemporaryFolders() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = folder.appendingPathComponent(".download-old")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    let keep = folder.appendingPathComponent("keep")
    try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
    store(folder, files: files(), downloader: downloader()).cleanUpLeftovers()
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: keep.path))
  }

  @Test func theRealManifestIsTheOneOfTheSpec() {
    let all = DPModelManifest.depthAnythingSmallF16
    #expect(all.map(\.size) == [617, 399_433, 49_419_072])
    #expect(all.last?.sha256 == "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed")
    #expect(all.allSatisfy { $0.path.hasPrefix("DepthAnythingV2SmallF16.mlpackage/") })
    #expect(DPModelManifest.baseURL.absoluteString == "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/")
    #expect(DPHosts.isAllowed(DPModelManifest.baseURL))
  }
}
