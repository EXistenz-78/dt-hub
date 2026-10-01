import Foundation
import HubKit
import Observation

/// The download of a language model (spec §9), owned by the app and not by the Preferences
/// view: closing the window or changing tab does not lose it, it can be cancelled from
/// anywhere, and only one runs at a time.
@MainActor
@Observable
public final class LanguageModelDownloadController {
  /// 0…1 while a download runs, nil otherwise.
  public private(set) var progress: Double?
  /// Why the last download failed; cleared when the next one starts.
  public private(set) var failure: LanguageModelError?
  /// How many downloads have finished well (the views refresh their model list on a change).
  public private(set) var completed = 0

  public var isDownloading: Bool { progress != nil }

  @ObservationIgnored private let downloader: any LanguageModelDownloader
  @ObservationIgnored private var task: Task<Void, Never>?
  /// Names the download a progress report belongs to, so a late report of an ended one is dropped.
  @ObservationIgnored private var runID = 0

  public init(downloader: any LanguageModelDownloader) {
    self.downloader = downloader
  }

  /// Starts downloading `repository` into `folder`; does nothing while another download runs.
  public func start(repository: String, to folder: URL) {
    guard !isDownloading else { return }
    failure = nil
    progress = 0
    runID += 1
    let id = runID
    let downloader = downloader
    task = Task { [weak self] in
      do {
        try await downloader.download(
          repository: repository, to: folder,
          progress: { fraction in Task { @MainActor in self?.report(fraction, run: id) } })
        self?.finish(run: id, error: nil)
      } catch is CancellationError {
        self?.finish(run: id, error: nil, cancelled: true)
      } catch let error as LanguageModelError {
        self?.finish(run: id, error: error)
      } catch {
        self?.finish(run: id, error: .downloadFailed(error.localizedDescription))
      }
    }
  }

  /// Stops the download; the files fetched so far are removed.
  public func cancel() {
    task?.cancel()
  }

  private func report(_ fraction: Double, run id: Int) {
    guard id == runID, progress != nil else { return }
    progress = fraction
  }

  private func finish(run id: Int, error: LanguageModelError?, cancelled: Bool = false) {
    guard id == runID else { return }
    progress = nil
    task = nil
    failure = error
    if error == nil, !cancelled { completed += 1 }
  }
}
