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
  /// True for the first moments after the launch, while the program loads and does not
  /// answer yet (spec §7: yellow). After that, a server that does not answer is in trouble.
  public private(set) var isStarting = false

  @ObservationIgnored private let launcher: any ProcessLauncher
  @ObservationIgnored private let files: FileSystemProbe
  @ObservationIgnored private let isPortFree: @Sendable (Int) -> Bool
  @ObservationIgnored private let pidFile: ServerPidFile
  @ObservationIgnored private let inspector: ProcessInspector
  @ObservationIgnored private let stopTimeout: Duration
  @ObservationIgnored private let startingPeriod: Duration
  @ObservationIgnored private var process: (any ServerProcess)?
  /// Servers asked to stop that may not have left yet: a start waits for them, and the app
  /// quitting closes them.
  @ObservationIgnored private var stopping: [any ServerProcess] = []
  /// Names the launch a callback belongs to, so a late callback of an old one is dropped.
  @ObservationIgnored private var launchID = 0
  /// Names the latest request to start or stop, so a start that waited (for the old server to
  /// leave) gives up when a later request replaced it.
  @ObservationIgnored private var requestID = 0

  public init(
    launcher: any ProcessLauncher = FoundationProcessLauncher(), files: FileSystemProbe = .live,
    isPortFree: @escaping @Sendable (Int) -> Bool = PortProbe.isFree,
    pidFile: ServerPidFile = ServerPidFile(url: ServerPidFile.defaultURL),
    inspector: ProcessInspector = .live, stopTimeout: Duration = .seconds(5),
    startingPeriod: Duration = .seconds(60)
  ) {
    self.launcher = launcher
    self.files = files
    self.isPortFree = isPortFree
    self.pidFile = pidFile
    self.inspector = inspector
    self.stopTimeout = stopTimeout
    self.startingPeriod = startingPeriod
  }

  public var isRunning: Bool {
    if case .running = state { return true }
    return false
  }

  /// Starts the server (closing the one DT Hub already started first). Returns when it has
  /// been launched or has failed to, or when a later start or stop replaced this request; the
  /// program needs a few more seconds before it answers.
  public func start(_ settings: ManagedServerSettings) async {
    requestID += 1
    let request = requestID
    await closeStoppedAndRunning()
    guard request == requestID else { return }
    logTail = []
    if let problem = settings.validationError(files) {
      state = .failedToStart(.settings(problem))
      return
    }
    let binary = settings.binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    await closeServerLeftByAPreviousRun(binary: binary)
    guard request == requestID, process == nil else { return }
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
      pidFile.write(pid: started.processID, executable: inspector.executablePath(started.processID))
      state = .running(pid: started.processID)
      beginStartingPeriod(launch: id)
    } catch {
      state = .failedToStart(.launchFailed(error.localizedDescription))
    }
  }

  /// Stops the server DT Hub started (and cancels a start that is still waiting); the next
  /// `start` launches a new one.
  public func stop() {
    requestID += 1
    stopProcess()
  }

  /// Stops the server and waits until it is gone (up to the stop timeout, then it is killed).
  public func stopAndWait() async {
    requestID += 1
    await closeStoppedAndRunning()
  }

  /// For the moment the app quits: no waiting for the main actor, only a short pause for
  /// the program to leave; whatever is still running after it is killed.
  public func terminateNow(timeout: TimeInterval = 3) {
    requestID += 1
    stopProcess()
    let deadline = Date().addingTimeInterval(timeout)
    while stopping.contains(where: \.isRunning), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    stopping.filter(\.isRunning).forEach { $0.kill() }
    reap()
  }

  // MARK: Stopping

  /// SIGTERM to the running server, which then counts as "stopping" until it has gone; after
  /// a few seconds it is killed.
  private func stopProcess() {
    isStarting = false
    guard let running = process else {
      if case .running = state { state = .stopped }
      return
    }
    launchID += 1  // its exit is expected: the callback of the old launch is dropped
    process = nil
    state = .stopped
    running.terminate()
    stopping.append(running)
    Task {
      try? await Task.sleep(for: .seconds(3))
      if running.isRunning { running.kill() }
      reap()
    }
  }

  /// Stops what runs and waits for everything that was asked to stop.
  private func closeStoppedAndRunning() async {
    stopProcess()
    let deadline = ContinuousClock.now + stopTimeout
    while stopping.contains(where: \.isRunning), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    stopping.filter(\.isRunning).forEach { $0.kill() }
    for _ in 0..<20 where stopping.contains(where: \.isRunning) { try? await Task.sleep(for: .milliseconds(50)) }
    reap()
  }

  /// Forgets what has left; the record of the server goes with the last of our own that was
  /// stopping (a record found at the start, of a server of a previous run, is not ours yet).
  private func reap() {
    let hadStopping = !stopping.isEmpty
    stopping.removeAll { !$0.isRunning }
    if hadStopping, stopping.isEmpty, process == nil { pidFile.remove() }
  }

  // MARK: Callbacks

  private func beginStartingPeriod(launch id: Int) {
    isStarting = true
    let period = startingPeriod
    Task { [weak self] in
      try? await Task.sleep(for: period)
      guard let self, id == self.launchID else { return }
      self.isStarting = false
    }
  }

  private func append(_ line: String, launch id: Int) {
    guard id == launchID else { return }
    logTail.append(line)
    if logTail.count > Self.logLimit { logTail.removeFirst(logTail.count - Self.logLimit) }
  }

  private func ended(_ exit: ProcessExit, launch id: Int) {
    guard id == launchID else { return }
    process = nil
    isStarting = false
    pidFile.remove()
    state = .exitedUnexpectedly(exit)
  }

  // MARK: A server left by a previous run

  /// A DT Hub that crashed or was killed leaves its server running, holding the port and the
  /// models in memory. The record in the file is closed when its process still runs the
  /// program the record names (the current program for a file without one). The record is
  /// replaced by the next launch: it is not removed after a wait, when another start may
  /// already have written its own.
  private func closeServerLeftByAPreviousRun(binary: String) async {
    guard let record = pidFile.read() else { return }
    let program = record.executable ?? binary
    guard inspector.isAlive(record.pid), inspector.isRunning(record.pid, program) else {
      pidFile.remove()
      return
    }
    inspector.terminate(record.pid)
    for _ in 0..<60 where inspector.isAlive(record.pid) { try? await Task.sleep(for: .milliseconds(50)) }
    if inspector.isAlive(record.pid) {
      inspector.kill(record.pid)
      for _ in 0..<20 where inspector.isAlive(record.pid) { try? await Task.sleep(for: .milliseconds(50)) }
    }
    logTail.append("Closed a server left running by a previous run (pid \(record.pid)).")
  }
}
