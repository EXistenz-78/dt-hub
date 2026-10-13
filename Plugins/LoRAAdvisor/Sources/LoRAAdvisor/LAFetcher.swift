import Foundation

/// Why a page or a picture could not be had.
enum LAFetchError: Error, Equatable {
  case notFound
  /// 401 or 403, or a page that is not public.
  case needsAccess
  /// 429: the site asks to slow down.
  case rateLimited
  case unreachable
  case tooLarge
  /// An address, or a redirect, outside the hosts the plug-in contacts.
  case notAllowed
  case unreadable
}

enum LALimits {
  /// A JSON answer or a model card.
  static let text = 5_000_000
  static let image = 10_000_000
}

/// The network as the plug-in needs it; the tests give a table of answers.
protocol LAFetching: Sendable {
  func data(from url: URL, limit: Int) async throws(LAFetchError) -> Data
}

/// The plug-in's only door to the network (spec §6.5): GET over https to Civitai and Hugging Face, with no cookies,
/// no credentials and no cache; a redirect out of those hosts is refused, and so is a body beyond the limit.
final class LAFetcher: LAFetching {
  private let configuration: URLSessionConfiguration

  init(configuration: URLSessionConfiguration = LAFetcher.configuration) {
    self.configuration = configuration
  }

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 60
    configuration.httpAdditionalHeaders = ["User-Agent": "DTHub-LoRAAdvisor/1.0"]
    return configuration
  }

  func data(from url: URL, limit: Int) async throws(LAFetchError) -> Data {
    guard LAHosts.isAllowed(url) else { throw .notAllowed }
    let job = Job(limit: limit)
    let session = URLSession(configuration: configuration, delegate: job, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let task = session.dataTask(with: request)
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Result<Data, LAFetchError>, Never>) in
        job.start(continuation)
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
    return try result.get()
  }

  /// One download: gathers the body up to the limit and judges redirects.
  private final class Job: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var body = Data()
    private var failure: LAFetchError?
    private var status = 0
    private var continuation: CheckedContinuation<Result<Data, LAFetchError>, Never>?

    init(limit: Int) { self.limit = limit }

    func start(_ continuation: CheckedContinuation<Result<Data, LAFetchError>, Never>) {
      lock.withLock { self.continuation = continuation }
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      guard let url = request.url, LAHosts.isAllowed(url) else {
        lock.withLock { failure = .notAllowed }
        completionHandler(nil)
        task.cancel()
        return
      }
      completionHandler(request)
    }

    func urlSession(
      _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
      completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
      lock.withLock { status = (response as? HTTPURLResponse)?.statusCode ?? 0 }
      if response.expectedContentLength > Int64(limit) {
        lock.withLock { failure = failure ?? .tooLarge }
        completionHandler(.cancel)
      } else {
        completionHandler(.allow)
      }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      let over = lock.withLock { () -> Bool in
        body.append(data)
        guard body.count > limit else { return false }
        failure = failure ?? .tooLarge
        return true
      }
      if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      let (continuation, result) = lock.withLock { () -> (CheckedContinuation<Result<Data, LAFetchError>, Never>?, Result<Data, LAFetchError>) in
        defer { self.continuation = nil }
        if let failure { return (self.continuation, .failure(failure)) }
        if error != nil { return (self.continuation, .failure(.unreachable)) }
        switch status {
        case 200..<300: return (self.continuation, .success(body))
        case 404, 410: return (self.continuation, .failure(.notFound))
        case 401, 403: return (self.continuation, .failure(.needsAccess))
        case 429: return (self.continuation, .failure(.rateLimited))
        case 300..<400: return (self.continuation, .failure(.notAllowed))
        default: return (self.continuation, .failure(.unreachable))
        }
      }
      continuation?.resume(returning: result)
    }
  }
}
