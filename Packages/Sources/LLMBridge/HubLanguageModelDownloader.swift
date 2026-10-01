import Foundation
import HuggingFace
import HubKit

/// Downloads a model from Hugging Face into the models folder, only when the user asked
/// (spec §9). The files are fetched into a hidden folder next to the destination and moved to
/// it when everything has arrived, so a download that fails or is cancelled never leaves a
/// half model that the models list would offer.
public struct HubLanguageModelDownloader: LanguageModelDownloader {
  /// Glob patterns of the files to fetch; empty fetches the whole repository.
  private let patterns: [String]

  public init(matching patterns: [String] = []) {
    self.patterns = patterns
  }

  /// The hidden folders of downloads that were cut short (the app quit or crashed): they hold
  /// part of a model, nothing lists them, and each new download uses a fresh name. Only one
  /// download runs at a time, so everything with the prefix in `parent` is a leftover.
  public static func removeLeftoverStaging(in parent: URL) {
    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: parent.path) else { return }
    for name in names where name.hasPrefix(stagingPrefix) {
      try? fileManager.removeItem(at: parent.appendingPathComponent(name))
    }
  }

  static let stagingPrefix = ".dthub-download-"

  public func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard let id = HuggingFace.Repo.ID(rawValue: repository) else {
      throw LanguageModelError.downloadFailed("\(repository) is not a repository name.")
    }
    let fileManager = FileManager.default
    let parent = folder.deletingLastPathComponent()
    Self.removeLeftoverStaging(in: parent)
    let staging = parent.appendingPathComponent("\(Self.stagingPrefix)\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
      _ = try await HuggingFace.HubClient().downloadSnapshot(
        of: id, to: staging, matching: patterns,
        progressHandler: { @MainActor update in progress(update.fractionCompleted) })
      if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
      try fileManager.moveItem(at: staging, to: folder)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw LanguageModelError.downloadFailed(error.localizedDescription)
    }
  }
}
