import CoreML
import CryptoKit
import Foundation

/// One file of the model: where it goes inside the model folder (`path`), what it is called on the server below
/// `DPModelManifest.baseURL` (`asset`; a release has a flat list of files, so it can differ from `path`), how big it
/// is, and its SHA-256.
struct DPModelFile: Sendable, Equatable {
  let path: String
  let asset: String?
  let size: Int64
  let sha256: String?

  init(path: String, asset: String? = nil, size: Int64, sha256: String?) {
    self.path = path
    self.asset = asset
    self.size = size
    self.sha256 = sha256
  }
}

/// Depth Anything V2 Base, converted to Core ML for this plug-in (see `Scripts/convert_depth_model.py`): fp16, one
/// function for landscape pictures (1036×784) and one for portrait ones (784×1036), output already a 0–1 grey picture.
/// The original weights are CC BY-NC 4.0 (Lihe Yang et al.): the converted files carry that licence.
enum DPModelManifest {
  static let baseURL = URL(
    string: "https://github.com/EXistenz-78/dt-hub/releases/download/depth-anything-v2-base-coreml/")!
  static let packageName = "DepthAnythingV2BaseF16.mlpackage"
  static let depthAnythingBaseF16: [DPModelFile] = [
    DPModelFile(
      path: "\(packageName)/Manifest.json", asset: "DepthAnythingV2BaseF16-Manifest.json", size: 617,
      sha256: "173102fdb3d61ff6a3135377fff5f613a91536d35e9c0fe143154854f3b7a519"),
    DPModelFile(
      path: "\(packageName)/Data/com.apple.CoreML/model.mlmodel", asset: "DepthAnythingV2BaseF16-model.mlmodel",
      size: 411_200, sha256: "90484372e75ffabc60b93b9a4cf40fecc58f32e53a227399501a9e683ddf58d5"),
    DPModelFile(
      path: "\(packageName)/Data/com.apple.CoreML/weights/weight.bin", asset: "DepthAnythingV2BaseF16-weight.bin",
      size: 204_996_928, sha256: "f4a5f30746786b06e46a1a13bac7eee33ea0b64bb8d80461cae3a3e61893524d"),
  ]
}

/// DWPose-L (`dw-ll_ucoco_384`), converted to Core ML for this plug-in (see `Scripts/convert_pose_model.py`): float16,
/// input a 288×384 RGB crop of a person (the normalisation is inside), output the two SimCC vectors of the 133
/// keypoints of COCO-WholeBody. DWPose is Apache-2.0 (IDEA-Research, Zhendong Yang et al.; weights `yzd-v/DWPose`).
extension DPModelManifest {
  static let dwposeLBaseURL = URL(
    string: "https://github.com/EXistenz-78/dt-hub/releases/download/dwpose-l-coreml/")!
  static let dwposeLPackageName = "DWPoseL384F16.mlpackage"
  static let dwposeLF16: [DPModelFile] = [
    DPModelFile(
      path: "\(dwposeLPackageName)/Manifest.json", asset: "DWPoseL384F16-Manifest.json", size: 617,
      sha256: "65bf603ed9d11c56f9d3209178a6032bff2eeb385a4cb938135d2fefff5ba4be"),
    DPModelFile(
      path: "\(dwposeLPackageName)/Data/com.apple.CoreML/model.mlmodel", asset: "DWPoseL384F16-model.mlmodel",
      size: 139_633, sha256: "f9d97464e6b77682de65fe3bfaba34fab7562d0ac0494c2bde33c9a461c8a7a5"),
    DPModelFile(
      path: "\(dwposeLPackageName)/Data/com.apple.CoreML/weights/weight.bin", asset: "DWPoseL384F16-weight.bin",
      size: 67_199_424, sha256: "64691178575c974d0e5ccb59051a385546a54b78f3d42d63786ccca067d15810"),
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
  /// The release the files are asked from (`DPModelManifest.baseURL` for the depth model).
  let baseURL: URL
  let downloader: any DPFileDownloading
  let compile: @Sendable (URL) throws -> URL
  let validate: @Sendable (URL) -> Bool
  private let busy = DPBusyFlag()

  init(
    folder: URL = DPModelStore.defaultFolder, files: [DPModelFile] = DPModelManifest.depthAnythingBaseF16,
    packageName: String = DPModelManifest.packageName, baseURL: URL = DPModelManifest.baseURL,
    downloader: any DPFileDownloading = DPDownloader(),
    compile: @escaping @Sendable (URL) throws -> URL = { try MLModel.compileModel(at: $0) },
    validate: @escaping @Sendable (URL) -> Bool = { (try? MLModel(contentsOf: $0)) != nil }
  ) {
    self.folder = folder
    self.files = files
    self.packageName = packageName
    self.baseURL = baseURL
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

  /// Every file of the model is in the folder, under its path (a package someone put there by hand).
  func hasPackageOnDisk() -> Bool {
    files.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.path).path) }
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
    try await perform(progress: progress) { temp in
      let total = max(1, files.reduce(0) { $0 + $1.size })
      var done: Int64 = 0
      progress(0)
      for file in files {
        try Task.checkCancellation()
        let destination = temp.appendingPathComponent(file.path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let before = done
        let url = baseURL.appendingPathComponent(file.asset ?? file.path)
        try await downloader.download(url, to: destination) { progress(min(1, Double(before + $0) / Double(total))) }
        try Self.verify(file, at: destination)
        done += file.size
        progress(min(1, Double(done) / Double(total)))
      }
    }
  }

  /// Takes a package that is already on disk (`directory` holds the package under the paths of `files`, as after a
  /// download): checks it like a download, compiles it and copies it into place. The original stays where it is.
  func installLocalPackage(from directory: URL) async throws {
    try await perform(progress: { _ in }) { temp in
      let manager = FileManager.default
      for file in files {
        try Task.checkCancellation()
        let source = directory.appendingPathComponent(file.path)
        guard manager.fileExists(atPath: source.path) else { throw DPModelError.wrongSize(file.path) }
        let destination = temp.appendingPathComponent(file.path)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: destination)
        try Self.verify(file, at: destination)
      }
    }
  }

  /// The shared frame of both installs: a temporary folder `fill` puts the checked files in, then compile, move,
  /// validate. Whatever happens, no temporary folder stays.
  private func perform(
    progress: @escaping @Sendable (Double) -> Void, fill: (URL) async throws -> Void
  ) async throws {
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
      try await fill(temp)
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
