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

  public func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard let id = HuggingFace.Repo.ID(rawValue: repository) else {
      throw LanguageModelError.downloadFailed("\(repository) is not a repository name.")
    }
    let fileManager = FileManager.default
    let parent = folder.deletingLastPathComponent()
    let staging = parent.appendingPathComponent(".dthub-download-\(UUID().uuidString)", isDirectory: true)
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
