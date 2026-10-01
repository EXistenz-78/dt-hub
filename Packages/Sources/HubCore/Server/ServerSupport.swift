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

/// What the pid file holds: the process id of the server DT Hub started and the program the
/// system says that process runs (its real path: a link such as `/usr/local/bin/gRPCServerCLI`
/// is reported as its target).
public struct ServerPidRecord: Equatable, Sendable {
  public let pid: Int32
  /// nil in a file written without it: the current program is compared instead.
  public let executable: String?

  public init(pid: Int32, executable: String?) {
    self.pid = pid
    self.executable = executable
  }
}

/// The record of the server DT Hub started, kept in a file so that a server left running by a
/// DT Hub that crashed or was killed can be recognized and closed at the next start.
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

  /// Two lines: the process id, then the program (the second may be missing).
  public func read() -> ServerPidRecord? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    guard let first = lines.first, let pid = Int32(first.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return nil
    }
    let program = lines.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
    return ServerPidRecord(pid: pid, executable: (program?.isEmpty ?? true) ? nil : program)
  }

  public func write(pid: Int32, executable: String?) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "\(pid)\n\(executable ?? "")".write(to: url, atomically: true, encoding: .utf8)
  }

  public func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Facts about running processes, replaceable in tests.
public struct ProcessInspector: Sendable {
  /// Whether the process exists.
  public var isAlive: @Sendable (Int32) -> Bool
  /// Whether the process runs this program (compared by real path): a recycled process id
  /// must never be closed.
  public var isRunning: @Sendable (_ pid: Int32, _ executable: String) -> Bool
  /// The real path of the program a process runs.
  public var executablePath: @Sendable (Int32) -> String?
  public var terminate: @Sendable (Int32) -> Void
  public var kill: @Sendable (Int32) -> Void

  public init(
    isAlive: @escaping @Sendable (Int32) -> Bool,
    isRunning: @escaping @Sendable (Int32, String) -> Bool,
    executablePath: @escaping @Sendable (Int32) -> String?,
    terminate: @escaping @Sendable (Int32) -> Void, kill: @escaping @Sendable (Int32) -> Void
  ) {
    self.isAlive = isAlive
    self.isRunning = isRunning
    self.executablePath = executablePath
    self.terminate = terminate
    self.kill = kill
  }

  /// `proc_pidpath` reports the real file, not the path (or link) the program was started
  /// through, so both sides are resolved before they are compared.
  private static func path(of pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }

  public static let live = ProcessInspector(
    isAlive: { Darwin.kill($0, 0) == 0 },
    isRunning: { pid, executable in
      guard let actual = path(of: pid) else { return false }
      return resolved(actual) == resolved(executable)
    },
    executablePath: { pid in path(of: pid).map(resolved) },
    terminate: { _ = Darwin.kill($0, SIGTERM) },
    kill: { _ = Darwin.kill($0, SIGKILL) })
}
