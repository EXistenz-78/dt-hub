import Foundation
import Observation

/// The gRPCServerCLI that DT Hub starts and stops (spec §5, §10): starts it when the app
/// opens, stops it when the app quits, tells when it ended without being asked, and offers
/// to start it again. It never restarts by itself: a server that keeps crashing must be seen.
@MainActor
@Observable
public final class ManagedServer {
  public enum Failure: Equatable, Sendable {
    case settings(ManagedServerSettings.ValidationError)
    /// Something already listens on the port (the Draw Things app's own server, another
    /// program, a server of a previous run that is not DT Hub's).
    case portInUse(Int)
    case launchFailed(String)
  }

  public enum State: Equatable, Sendable {
    case stopped
    case running(pid: Int32)
    /// DT Hub could not start it.
    case failedToStart(Failure)
    /// It started and then ended without DT Hub asking: a crash, or a port or models folder
    /// the program itself refused.
    case exitedUnexpectedly(ProcessExit)
  }

  public private(set) var state: State = .stopped
  /// The last lines the server wrote, for the Preferences and for bug reports.
  public private(set) var logTail: [String] = []
  public static let logLimit = 30

  @ObservationIgnored private let launcher: any ProcessLauncher
  @ObservationIgnored private let files: FileSystemProbe
  @ObservationIgnored private let isPortFree: @Sendable (Int) -> Bool
  @ObservationIgnored private let pidFile: ServerPidFile
  @ObservationIgnored private let inspector: ProcessInspector
  @ObservationIgnored private var process: (any ServerProcess)?
  /// Names the launch a callback belongs to, so a late callback of an old one is dropped.
  @ObservationIgnored private var launchID = 0

  public init(
    launcher: any ProcessLauncher = FoundationProcessLauncher(), files: FileSystemProbe = .live,
    isPortFree: @escaping @Sendable (Int) -> Bool = PortProbe.isFree,
    pidFile: ServerPidFile = ServerPidFile(url: ServerPidFile.defaultURL),
    inspector: ProcessInspector = .live
  ) {
    self.launcher = launcher
    self.files = files
    self.isPortFree = isPortFree
    self.pidFile = pidFile
    self.inspector = inspector
  }

  public var isRunning: Bool {
    if case .running = state { return true }
    return false
  }

  /// Starts the server (closing the one DT Hub already started first). Returns when it has
  /// been launched or has failed to; the program needs a few more seconds before it answers.
  public func start(_ settings: ManagedServerSettings) async {
    await stopAndWait()
    logTail = []
    if let problem = settings.validationError(files) {
      state = .failedToStart(.settings(problem))
      return
    }
    let binary = settings.binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    await closeServerLeftByAPreviousRun(binary: binary)
    guard isPortFree(settings.port) else {
      state = .failedToStart(.portInUse(settings.port))
      return
    }
    launchID += 1
    let id = launchID
    do {
      let started = try launcher.launch(
        executable: binary, arguments: ServerArguments.make(settings),
        onLine: { [weak self] line in Task { @MainActor in self?.append(line, launch: id) } },
        onExit: { [weak self] exit in Task { @MainActor in self?.ended(exit, launch: id) } })
      process = started
      pidFile.write(started.processID)
      state = .running(pid: started.processID)
    } catch {
      state = .failedToStart(.launchFailed(error.localizedDescription))
    }
  }

  /// Stops the server DT Hub started; the next `start` launches a new one.
  public func stop() {
    guard let process else {
      if case .running = state { state = .stopped }
      return
    }
    launchID += 1  // its exit is expected: the callback of the old launch is dropped
    self.process = nil
    state = .stopped
    pidFile.remove()
    process.terminate()
    Task {
      try? await Task.sleep(for: .seconds(3))
      if process.isRunning { process.kill() }
    }
  }

  /// Stops the server and waits until it is gone (up to `timeout`).
  public func stopAndWait(timeout: Duration = .seconds(5)) async {
    guard let running = process else {
      stop()
      return
    }
    stop()
    let deadline = ContinuousClock.now + timeout
    while running.isRunning, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if running.isRunning { running.kill() }
  }

  /// For the moment the app quits: no waiting for the main actor, only a short pause for
  /// the program to leave.
  public func terminateNow(timeout: TimeInterval = 3) {
    guard let running = process else { return }
    stop()
    let deadline = Date().addingTimeInterval(timeout)
    while running.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if running.isRunning { running.kill() }
  }

  // MARK: Callbacks

  private func append(_ line: String, launch id: Int) {
    guard id == launchID else { return }
    logTail.append(line)
    if logTail.count > Self.logLimit { logTail.removeFirst(logTail.count - Self.logLimit) }
  }

  private func ended(_ exit: ProcessExit, launch id: Int) {
    guard id == launchID else { return }
    process = nil
    pidFile.remove()
    state = .exitedUnexpectedly(exit)
  }

  // MARK: A server left by a previous run

  /// A DT Hub that crashed or was killed leaves its server running, holding the port and the
  /// models in memory. The process id in the file is closed when it still is this program.
  private func closeServerLeftByAPreviousRun(binary: String) async {
    guard let pid = pidFile.read() else { return }
    defer { pidFile.remove() }
    guard inspector.isAlive(pid), inspector.isRunning(pid, binary) else { return }
    inspector.terminate(pid)
    for _ in 0..<60 where inspector.isAlive(pid) { try? await Task.sleep(for: .milliseconds(50)) }
    if inspector.isAlive(pid) { inspector.kill(pid) }
    logTail.append("Closed a server left running by a previous run (pid \(pid)).")
  }
}
