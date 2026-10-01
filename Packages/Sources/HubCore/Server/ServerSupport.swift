import Darwin
import Foundation

/// Whether something already listens on a port of this Mac. A connection attempt, not a
/// bind: a bind also fails for leftover connections of a server that just stopped.
public enum PortProbe {
  public static func isFree(_ port: Int) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return true }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port)).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return result != 0
  }
}

/// The process id of the server DT Hub started, kept in a file so that a server left running
/// by a DT Hub that crashed or was killed can be recognized and closed at the next start.
public struct ServerPidFile: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// ~/Library/Application Support/DT Hub/managed-server.pid.
  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("managed-server.pid")
  }

  public func read() -> Int32? {
    (try? String(contentsOf: url, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
  }

  public func write(_ pid: Int32) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? String(pid).write(to: url, atomically: true, encoding: .utf8)
  }

  public func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Facts about running processes, replaceable in tests.
public struct ProcessInspector: Sendable {
  /// Whether the process exists.
  public var isAlive: @Sendable (Int32) -> Bool
  /// Whether the process runs this program: a recycled process id must never be closed.
  public var isRunning: @Sendable (_ pid: Int32, _ executable: String) -> Bool
  public var terminate: @Sendable (Int32) -> Void
  public var kill: @Sendable (Int32) -> Void

  public init(
    isAlive: @escaping @Sendable (Int32) -> Bool,
    isRunning: @escaping @Sendable (Int32, String) -> Bool,
    terminate: @escaping @Sendable (Int32) -> Void, kill: @escaping @Sendable (Int32) -> Void
  ) {
    self.isAlive = isAlive
    self.isRunning = isRunning
    self.terminate = terminate
    self.kill = kill
  }

  public static let live = ProcessInspector(
    isAlive: { Darwin.kill($0, 0) == 0 },
    isRunning: { pid, executable in
      var buffer = [CChar](repeating: 0, count: 4096)
      guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
      return String(cString: buffer) == executable
    },
    terminate: { _ = Darwin.kill($0, SIGTERM) },
    kill: { _ = Darwin.kill($0, SIGKILL) })
}
