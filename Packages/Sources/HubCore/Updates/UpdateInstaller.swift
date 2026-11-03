import Foundation
import HubKit

/// Fetches one item of an update: downloads its zip, checks the sha256, unzips, and hands back the bundle.
/// The three steps that touch the outside world are injected.
public struct UpdateInstaller: Sendable {
  /// From a URL to a file; reports the progress, 0…1.
  public var download: @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
  /// A zip into an empty folder.
  public var unzip: @Sendable (URL, URL) async throws -> Void
  public var sha256: @Sendable (URL) async -> String?

  public init(
    download: @escaping @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> Void,
    unzip: @escaping @Sendable (URL, URL) async throws -> Void,
    sha256: @escaping @Sendable (URL) async -> String?
  ) {
    self.download = download
    self.unzip = unzip
    self.sha256 = sha256
  }

  /// Downloads and checks one item; returns the `.app` (for the app) or the `.dthubplugin` (for a plug-in) it holds.
  /// A wrong sha256, a zip without exactly one bundle, or a plug-in that is not the one the manifest names, throws and
  /// leaves nothing unzipped.
  public func fetchBundle(
    _ item: ReleaseItem, manifest: ReleaseManifest, base: URL, work: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws(UpdateError) -> URL {
    let manager = FileManager.default
    // The asset name is a plain file name (the manifest is checked), so it is safe as a folder name.
    let folder = work.appendingPathComponent(item.asset + ".d", isDirectory: true)
    let zip = folder.appendingPathComponent(item.asset)
    let unzipped = folder.appendingPathComponent("unzipped", isDirectory: true)
    do {
      try? manager.removeItem(at: folder)
      try manager.createDirectory(at: unzipped, withIntermediateDirectories: true)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
    do {
      try await download(manifest.downloadURL(for: item, base: base), zip, progress)
    } catch {
      throw .download(error.localizedDescription)
    }
    guard await sha256(zip) == item.sha256 else {
      try? manager.removeItem(at: folder)
      throw .checksum
    }
    do {
      try await unzip(zip, unzipped)
    } catch {
      throw .unzip(error.localizedDescription)
    }
    let wanted = item.id == ReleaseItem.appID ? "app" : PluginContract.bundleExtension
    let found =
      ((try? manager.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.pathExtension == wanted }
    guard found.count == 1, let bundle = found.first else {
      try? manager.removeItem(at: unzipped)
      throw .noBundle
    }
    if item.id != ReleaseItem.appID {
      let info: PluginBundleInfo
      do { info = try PluginBundleReader.read(bundle) } catch { throw .plugin(error) }
      guard info.identifier == item.id, info.version == item.version else {
        try? manager.removeItem(at: unzipped)
        throw .identityMismatch
      }
    }
    return bundle
  }

  /// The real one: `URLSession` for the download, `ditto` for the zip, and the same chunked sha256 as the server check.
  public static let live = UpdateInstaller(
    download: { url, destination, progress in
      let reporter = ProgressReporter(progress)
      let (file, response) = try await URLSession.shared.download(
        for: URLRequest(url: url, timeoutInterval: 60), delegate: reporter)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: file, to: destination)
      progress(1)
    },
    unzip: { zip, folder in
      try await Task.detached(priority: .utility) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.cannotDecodeContentData) }
      }.value
    },
    sha256: { url in
      await Task.detached(priority: .utility) { ServerVersionChecker.sha256(ofFileAt: url.path) }.value
    })
}

/// Hands the fraction downloaded to a closure while a download runs.
private final class ProgressReporter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let report: @Sendable (Double) -> Void
  private var observation: NSKeyValueObservation?

  init(_ report: @escaping @Sendable (Double) -> Void) {
    self.report = report
  }

  func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
    observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
      report(progress.fractionCompleted)
    }
  }
}
