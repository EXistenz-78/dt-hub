import Darwin
import Foundation

/// How a process ended.
public struct ProcessExit: Equatable, Sendable {
  public let status: Int32
  /// True when a signal ended it (a crash, or a SIGTERM), false when it exited by itself.
  public let bySignal: Bool

  public init(status: Int32, bySignal: Bool) {
    self.status = status
    self.bySignal = bySignal
  }
}

/// A running program DT Hub started.
public protocol ServerProcess: Sendable {
  var processID: Int32 { get }
  var isRunning: Bool { get }
  /// SIGTERM: ask it to stop.
  func terminate()
  /// SIGKILL: make it stop.
  func kill()
}

/// Starts programs (spec §4: HubCore reaches the system only through protocols like this one).
public protocol ProcessLauncher: Sendable {
  /// Starts `executable`; `onLine` receives each line of its output (errors included),
  /// `onExit` how it ended. Both may be called from any thread.
  func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess
}

/// The real thing, on Foundation's `Process`.
public struct FoundationProcessLauncher: ProcessLauncher {
  public init() {}

  public func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    let lines = LineBuffer(onLine)
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        lines.flush()
      } else {
        lines.append(data)
      }
    }
    process.terminationHandler = { finished in
      onExit(
        ProcessExit(status: finished.terminationStatus, bySignal: finished.terminationReason == .uncaughtSignal))
    }
    try process.run()
    return FoundationServerProcess(process)
  }
}

private final class FoundationServerProcess: ServerProcess, @unchecked Sendable {
  private let process: Process

  init(_ process: Process) {
    self.process = process
  }

  var processID: Int32 { process.processIdentifier }
  var isRunning: Bool { process.isRunning }
  func terminate() { process.terminate() }
  func kill() { Darwin.kill(process.processIdentifier, SIGKILL) }
}

/// Cuts a stream of bytes into lines.
private final class LineBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var pending = Data()
  private let onLine: @Sendable (String) -> Void

  init(_ onLine: @escaping @Sendable (String) -> Void) {
    self.onLine = onLine
  }

  func append(_ data: Data) {
    var complete: [String] = []
    lock.withLock {
      pending.append(data)
      while let newline = pending.firstIndex(of: 0x0A) {
        complete.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
        pending.removeSubrange(pending.startIndex...newline)
      }
    }
    complete.forEach(onLine)
  }

  func flush() {
    let rest = lock.withLock { () -> String? in
      defer { pending = Data() }
      return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
    if let rest { onLine(rest) }
  }
}
