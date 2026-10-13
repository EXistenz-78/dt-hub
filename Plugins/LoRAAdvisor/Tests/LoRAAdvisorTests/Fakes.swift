import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import LoRAAdvisor

/// Answers from a table instead of the network, and remembers what was asked.
final class FakeFetcher: LAFetching, @unchecked Sendable {
  private let lock = NSLock()
  private var table: [String: Result<Data, LAFetchError>] = [:]
  private var asked: [String] = []
  /// Called before each answer (to stop a job half-way, for example).
  var onRequest: (@Sendable (String) -> Void)?

  func set(_ url: URL, _ result: Result<Data, LAFetchError>) { lock.withLock { table[url.absoluteString] = result } }
  func set(_ url: URL, text: String) { set(url, .success(Data(text.utf8))) }
  var requests: [String] { lock.withLock { asked } }

  func data(from url: URL, limit: Int) async throws(LAFetchError) -> Data {
    let key = url.absoluteString
    lock.withLock { asked.append(key) }
    onRequest?(key)
    guard let result = lock.withLock({ table[key] }) else { throw .notFound }
    return try result.get()
  }
}

enum Pictures {
  /// A solid PNG of the given size.
  static func png(width: Int = 600, height: Int = 400) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  static func size(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return (image.width, image.height)
  }

  static func type(of data: Data) -> String? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
  }
}

/// Stands in for the network under `LAFetcher`: a table of answers per address.
final class StubProtocol: URLProtocol, @unchecked Sendable {
  struct Answer {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
  }
  private static let lock = NSLock()
  nonisolated(unsafe) private static var answers: [String: Answer] = [:]
  nonisolated(unsafe) private static var asked: [String] = []

  static func set(_ url: String, _ answer: Answer) { lock.withLock { answers[url] = answer } }
  static var requests: [String] { lock.withLock { asked } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let url = request.url!
    Self.lock.withLock { Self.asked.append(url.absoluteString) }
    let answer = Self.lock.withLock { Self.answers[url.absoluteString] } ?? Answer(status: 404)
    let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
    if (300..<400).contains(answer.status), let location = answer.headers["Location"].flatMap(URL.init(string:)) {
      client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: answer.body)
    client?.urlProtocolDidFinishLoading(self)
  }
}
