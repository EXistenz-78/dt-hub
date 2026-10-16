import CoreML
import CryptoKit
import Foundation

/// One file of the model: where it is on the server (below `DPModelManifest.baseURL`), how big, and its SHA-256 when
/// the server states one (the large file does).
struct DPModelFile: Sendable, Equatable {
  let path: String
  let size: Int64
  let sha256: String?
}

enum DPModelManifest {
  static let baseURL = URL(string: "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/")!
  static let packageName = "DepthAnythingV2SmallF16.mlpackage"
  /// Checked against Hugging Face's API on 16 October 2026.
  static let depthAnythingSmallF16: [DPModelFile] = [
    DPModelFile(path: "\(packageName)/Manifest.json", size: 617, sha256: nil),
    DPModelFile(path: "\(packageName)/Data/com.apple.CoreML/model.mlmodel", size: 399_433, sha256: nil),
    DPModelFile(
      path: "\(packageName)/Data/com.apple.CoreML/weights/weight.bin", size: 49_419_072,
      sha256: "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed"),
  ]
}

/// A flag one install at a time can take.
final class DPBusyFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var taken = false
  func tryAcquire() -> Bool {
    lock.withLock {
      if taken { return false }
      taken = true
      return true
    }
  }
  func release() { lock.withLock { taken = false } }
}

/// Where the depth model lives on disk, and how it gets there: download, check, compile, move into place. Nothing
/// is left half done.
struct DPModelStore: Sendable {
  let folder: URL
  let files: [DPModelFile]
  let packageName: String
  let downloader: any DPFileDownloading
  let compile: @Sendable (URL) throws -> URL
  let validate: @Sendable (URL) -> Bool
  private let busy = DPBusyFlag()

  init(
    folder: URL = DPModelStore.defaultFolder, files: [DPModelFile] = DPModelManifest.depthAnythingSmallF16,
    packageName: String = DPModelManifest.packageName, downloader: any DPFileDownloading = DPDownloader(),
    compile: @escaping @Sendable (URL) throws -> URL = { try MLModel.compileModel(at: $0) },
    validate: @escaping @Sendable (URL) -> Bool = { (try? MLModel(contentsOf: $0)) != nil }
  ) {
    self.folder = folder
    self.files = files
    self.packageName = packageName
    self.downloader = downloader
    self.compile = compile
    self.validate = validate
  }

  /// `~/Library/Application Support/DT Hub/Data/DepthPose`.
  static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub/Data/DepthPose", isDirectory: true)
  }

  var packageURL: URL { folder.appendingPathComponent(packageName, isDirectory: true) }
  var compiledURL: URL {
    folder.appendingPathComponent((packageName as NSString).deletingPathExtension + ".mlmodelc", isDirectory: true)
  }

  /// The compiled model is there and opens.
  func isPresent() -> Bool {
    FileManager.default.fileExists(atPath: compiledURL.path) && validate(compiledURL)
  }

  /// Removes what an install that was cut short (the app quit) left behind.
  func cleanUpLeftovers() {
    let manager = FileManager.default
    for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(".download-") {
      try? manager.removeItem(at: folder.appendingPathComponent(name))
    }
  }

  /// Downloads, checks, compiles and moves the model into place. `progress` goes from 0 to 1.
  func install(progress: @escaping @Sendable (Double) -> Void) async throws {
    guard busy.tryAcquire() else { throw DPModelError.busy }
    defer { busy.release() }
    let manager = FileManager.default
    let temp = folder.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
    var compiled: URL?
    defer {
      try? manager.removeItem(at: temp)
      if let compiled { try? manager.removeItem(at: compiled) }
    }
    do {
      try manager.createDirectory(at: temp, withIntermediateDirectories: true)
      let total = max(1, files.reduce(0) { $0 + $1.size })
      var done: Int64 = 0
      progress(0)
      for file in files {
        try Task.checkCancellation()
        let destination = temp.appendingPathComponent(file.path)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let before = done
        try await downloader.download(DPModelManifest.baseURL.appendingPathComponent(file.path), to: destination) {
          progress(min(1, Double(before + $0) / Double(total)))
        }
        try Self.verify(file, at: destination)
        done += file.size
        progress(min(1, Double(done) / Double(total)))
      }
      try Task.checkCancellation()
      do {
        compiled = try compile(temp.appendingPathComponent(packageName))
      } catch {
        throw DPModelError.compileFailed
      }
      try? manager.removeItem(at: compiledURL)
      try? manager.removeItem(at: packageURL)
      try manager.moveItem(at: temp.appendingPathComponent(packageName), to: packageURL)
      try manager.moveItem(at: compiled!, to: compiledURL)
      compiled = nil
      guard validate(compiledURL) else {
        try? manager.removeItem(at: compiledURL)
        try? manager.removeItem(at: packageURL)
        throw DPModelError.compileFailed
      }
      progress(1)
    } catch let error as DPModelError {
      throw error
    } catch is CancellationError {
      throw DPModelError.cancelled
    } catch {
      throw DPModelError.network(error.localizedDescription)
    }
  }

  private static func verify(_ file: DPModelFile, at url: URL) throws {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
    guard size == file.size else { throw DPModelError.wrongSize(file.path) }
    if let expected = file.sha256, try sha256(of: url) != expected { throw DPModelError.wrongChecksum(file.path) }
  }

  /// SHA-256 of a file, read a megabyte at a time.
  static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
