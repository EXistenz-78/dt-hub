import Foundation

enum DPModelError: Error, Equatable {
  case notAllowed
  case wrongSize(String)
  case wrongChecksum(String)
  case compileFailed
  case cancelled
  case busy
  case network(String)
}

/// The only addresses the plug-in contacts: Hugging Face, over HTTPS (the files themselves come from a subdomain of it).
enum DPHosts {
  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return ["huggingface.co", "hf.co"].contains { host == $0 || host.hasSuffix("." + $0) }
  }
}

/// Fetches one file into another: a seam for the tests.
protocol DPFileDownloading: Sendable {
  /// `progress` gets the bytes written so far.
  func download(_ url: URL, to file: URL, progress: @Sendable @escaping (Int64) -> Void) async throws
}

/// One GET per file, in a session of its own: no cookies, no cache, no credentials; a redirect outside the allowed
/// hosts is refused.
final class DPDownloader: DPFileDownloading, @unchecked Sendable {
  private let configuration: URLSessionConfiguration

  init(configuration: URLSessionConfiguration = .ephemeral) {
    self.configuration = configuration.copy() as! URLSessionConfiguration
    self.configuration.httpCookieStorage = nil
    self.configuration.urlCredentialStorage = nil
    self.configuration.urlCache = nil
    self.configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.configuration.timeoutIntervalForRequest = 60
    self.configuration.timeoutIntervalForResource = 20 * 60
  }

  func download(_ url: URL, to file: URL, progress: @Sendable @escaping (Int64) -> Void) async throws {
    guard DPHosts.isAllowed(url) else { throw DPModelError.notAllowed }
    let job = Job(destination: file, progress: progress)
    let session = URLSession(configuration: configuration, delegate: job, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: url)
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let task = session.downloadTask(with: request)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        job.start(task, continuation)
      }
    } onCancel: {
      task.cancel()
    }
  }

  /// One download: judges redirects and the answer, moves the file, tells the end once.
  private final class Job: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var failure: DPModelError?

    init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
      self.destination = destination
      self.progress = progress
    }

    func start(_ task: URLSessionDownloadTask, _ continuation: CheckedContinuation<Void, any Error>) {
      lock.withLock { self.continuation = continuation }
      task.resume()
    }

    private func fail(_ error: DPModelError) { lock.withLock { if failure == nil { failure = error } } }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
      if let url = request.url, DPHosts.isAllowed(url) {
        completionHandler(request)
      } else {
        fail(.notAllowed)
        completionHandler(nil)
        task.cancel()  // do not wait for the body of the refused redirect
      }
    }

    func urlSession(
      _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
      progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
      if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
        fail(.network("HTTP \(status)"))
        return
      }
      // The system deletes `location` when this returns: move it now.
      do {
        let manager = FileManager.default
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: location, to: destination)
      } catch {
        fail(.network(error.localizedDescription))
      }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      let (continuation, failure) = lock.withLock { () -> (CheckedContinuation<Void, any Error>?, DPModelError?) in
        defer { self.continuation = nil }
        return (self.continuation, self.failure)
      }
      guard let continuation else { return }
      if let failure {
        try? FileManager.default.removeItem(at: destination)
        continuation.resume(throwing: failure)
      } else if let error {
        let mapped: DPModelError =
          (error as? URLError)?.code == .cancelled ? .cancelled : .network(error.localizedDescription)
        continuation.resume(throwing: mapped)
      } else {
        continuation.resume()
      }
    }
  }
}
