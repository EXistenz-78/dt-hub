import Foundation
import Testing

@testable import DepthPose

/// A fake network: what each address answers, by its full text.
final class FakeHTTP: URLProtocol, @unchecked Sendable {
  enum Route {
    case body(Data, status: Int)
    case redirect(String)
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var routes: [String: Route] = [:]

  static func set(_ routes: [String: Route]) { lock.withLock { Self.routes = routes } }
  private static func route(_ url: String) -> Route? { lock.withLock { routes[url] } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let url = request.url, let route = Self.route(url.absoluteString) else {
      client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
      return
    }
    switch route {
    case .redirect(let target):
      let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
      client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
    case .body(let data, let status):
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }
  }
}

@Suite("DPDownloader", .serialized)
struct DPDownloaderTests {
  private func downloader() -> DPDownloader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FakeHTTP.self]
    return DPDownloader(configuration: configuration)
  }

  private func target() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dpd-\(UUID().uuidString)")
  }

  @Test func theAllowListIsHuggingFaceAndItsSubdomainsOverHTTPS() {
    for good in [
      "https://huggingface.co/a", "https://cdn-lfs.huggingface.co/x", "https://cas-bridge.xethub.hf.co/y",
      "https://hf.co/z",
    ] { #expect(DPHosts.isAllowed(URL(string: good)!), "\(good)") }
    for bad in [
      "https://evilhuggingface.co/a", "https://huggingface.co.evil.com/a", "http://huggingface.co/a",
      "https://example.com", "file:///etc/passwd",
    ] { #expect(!DPHosts.isAllowed(URL(string: bad)!), "\(bad)") }
  }

  @Test func aFileIsWrittenAndProgressReachesItsSize() async throws {
    FakeHTTP.set(["https://huggingface.co/f": .body(Data(repeating: 7, count: 1000), status: 200)])
    let file = target()
    defer { try? FileManager.default.removeItem(at: file) }
    let last = LockedValue<Int64>(0)
    try await downloader().download(URL(string: "https://huggingface.co/f")!, to: file) { last.set($0) }
    #expect(try Data(contentsOf: file).count == 1000)
    #expect(last.value == 1000)
  }

  @Test func aRedirectToAHuggingFaceSubdomainIsFollowed() async throws {
    FakeHTTP.set([
      "https://huggingface.co/f": .redirect("https://cdn-lfs.huggingface.co/real"),
      "https://cdn-lfs.huggingface.co/real": .body(Data("hello".utf8), status: 200),
    ])
    let file = target()
    defer { try? FileManager.default.removeItem(at: file) }
    try await downloader().download(URL(string: "https://huggingface.co/f")!, to: file) { _ in }
    #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
  }

  @Test func aRedirectToAnotherHostIsRefused() async {
    FakeHTTP.set([
      "https://huggingface.co/f": .redirect("https://evil.example.com/real"),
      "https://evil.example.com/real": .body(Data("x".utf8), status: 200),
    ])
    let file = target()
    defer { try? FileManager.default.removeItem(at: file) }
    await #expect(throws: DPModelError.notAllowed) {
      try await downloader().download(URL(string: "https://huggingface.co/f")!, to: file) { _ in }
    }
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func anHTTPErrorFails() async {
    FakeHTTP.set(["https://huggingface.co/f": .body(Data("nope".utf8), status: 404)])
    let file = target()
    defer { try? FileManager.default.removeItem(at: file) }
    await #expect(throws: DPModelError.network("HTTP 404")) {
      try await downloader().download(URL(string: "https://huggingface.co/f")!, to: file) { _ in }
    }
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func anAddressOutsideTheAllowListIsRefusedBeforeAnyRequest() async {
    FakeHTTP.set([:])
    await #expect(throws: DPModelError.notAllowed) {
      try await downloader().download(URL(string: "http://huggingface.co/f")!, to: target()) { _ in }
    }
  }
}

/// A value several threads write and one reads.
final class LockedValue<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T
  init(_ value: T) { stored = value }
  var value: T { lock.withLock { stored } }
  func set(_ value: T) { lock.withLock { stored = value } }
  func update(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
}
