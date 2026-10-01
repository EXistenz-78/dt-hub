import Foundation
import Testing

@testable import HubCore

/// A program that is never really started: tests say what it prints and when it ends.
final class FakeProcess: ServerProcess, @unchecked Sendable {
  let processID: Int32
  private let lock = NSLock()
  private var running = true
  private(set) var terminated = false
  private(set) var killed = false
  let onExit: @Sendable (ProcessExit) -> Void
  let ignoresTerminate: Bool

  init(processID: Int32, ignoresTerminate: Bool = false, onExit: @escaping @Sendable (ProcessExit) -> Void) {
    self.processID = processID
    self.ignoresTerminate = ignoresTerminate
    self.onExit = onExit
  }

  var isRunning: Bool { lock.withLock { running } }

  func terminate() {
    lock.withLock { terminated = true }
    if !ignoresTerminate { finish(ProcessExit(status: 15, bySignal: true)) }
  }

  func kill() {
    lock.withLock { killed = true }
    finish(ProcessExit(status: 9, bySignal: true))
  }

  func finish(_ exit: ProcessExit) {
    let wasRunning = lock.withLock { () -> Bool in
      defer { running = false }
      return running
    }
    if wasRunning { onExit(exit) }
  }
}

final class FakeLauncher: ProcessLauncher, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var launches: [(executable: String, arguments: [String])] = []
  private(set) var processes: [FakeProcess] = []
  private var lineHandlers: [@Sendable (String) -> Void] = []
  var failWith: (any Error)?
  var ignoresTerminate = false

  func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess {
    if let failWith { throw failWith }
    return lock.withLock {
      launches.append((executable, arguments))
      let process = FakeProcess(processID: Int32(1000 + processes.count), ignoresTerminate: ignoresTerminate, onExit: onExit)
      processes.append(process)
      lineHandlers.append(onLine)
      return process
    }
  }

  func print(_ line: String, launch index: Int = 0) { lock.withLock { lineHandlers[index] }(line) }
  var last: FakeProcess { lock.withLock { processes.last! } }
}

struct LaunchFailure: Error, LocalizedError {
  var errorDescription: String? { "no such file" }
}

@MainActor
struct ManagedServerTests {
  let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models", port: 7861)
  let files = FileSystemProbe(isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" })

  func pidFile() -> ServerPidFile {
    ServerPidFile(
      url: FileManager.default.temporaryDirectory.appendingPathComponent("ManagedServerTests-\(UUID())/server.pid"))
  }

  /// `running` are the process ids that run the program recorded as `executable` (any program
  /// when nil); `ownPath` is what the system says a launched process runs.
  func inspector(
    alive: Set<Int32> = [], running: Set<Int32> = [], executable: String? = nil, ownPath: String? = "/real/cli",
    log: Log = Log()
  ) -> ProcessInspector {
    ProcessInspector(
      isAlive: { log.alive($0, alive) },
      isRunning: { pid, path in running.contains(pid) && (executable == nil || path == executable) },
      executablePath: { _ in ownPath },
      terminate: { log.terminated($0) }, kill: { log.killed($0) })
  }

  /// What the inspector was asked to do; a closed pid stops being alive.
  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var gone: Set<Int32> = []
    private(set) var terminatedPIDs: [Int32] = []
    private(set) var killedPIDs: [Int32] = []
    /// How long a process lingers after SIGTERM (0: gone at once).
    var lingers: TimeInterval = 0
    private var asked: [Int32: Date] = [:]
    func alive(_ pid: Int32, _ alive: Set<Int32>) -> Bool {
      lock.withLock {
        guard alive.contains(pid), !gone.contains(pid) else { return false }
        if let when = asked[pid], Date().timeIntervalSince(when) >= lingers { return false }
        return true
      }
    }
    func terminated(_ pid: Int32) { lock.withLock { terminatedPIDs.append(pid); asked[pid] = Date(); if lingers == 0 { gone.insert(pid) } } }
    func killed(_ pid: Int32) { lock.withLock { killedPIDs.append(pid); gone.insert(pid) } }
  }

  func server(_ launcher: FakeLauncher, portFree: Bool = true, pidFile: ServerPidFile? = nil, inspector: ProcessInspector? = nil)
    -> ManagedServer
  {
    ManagedServer(
      launcher: launcher, files: files, isPortFree: { _ in portFree }, pidFile: pidFile ?? self.pidFile(),
      inspector: inspector ?? self.inspector())
  }

  func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

  @Test func startsTheServerWithTheCommandLine() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    #expect(server.state == .running(pid: 1000))
    #expect(server.isRunning)
    #expect(launcher.launches.count == 1)
    #expect(launcher.launches[0].executable == "/bin/cli")
    #expect(launcher.launches[0].arguments == ServerArguments.make(settings))
  }

  @Test func doesNotStartWithSettingsThatCannotWork() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(ManagedServerSettings(mode: .managed, binaryPath: "/nowhere", modelsFolder: "/models"))
    #expect(server.state == .failedToStart(.settings(.binaryNotExecutable)))
    #expect(launcher.launches.isEmpty)
  }

  @Test func doesNotStartOnAPortSomethingElseUses() async {
    let launcher = FakeLauncher()
    let server = server(launcher, portFree: false)
    await server.start(settings)
    #expect(server.state == .failedToStart(.portInUse(7861)))
    #expect(launcher.launches.isEmpty)
  }

  @Test func reportsAProgramThatCannotBeLaunched() async {
    let launcher = FakeLauncher()
    launcher.failWith = LaunchFailure()
    let server = server(launcher)
    await server.start(settings)
    #expect(server.state == .failedToStart(.launchFailed("no such file")))
  }

  @Test func keepsTheLastLinesTheServerWrote() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    for number in 1...45 { launcher.print("line \(number)") }
    await settle()
    #expect(server.logTail.count == ManagedServer.logLimit)
    #expect(server.logTail.first == "line 16")
    #expect(server.logTail.last == "line 45")
  }

  @Test func tellsWhenTheServerEndsOnItsOwn() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    let server = server(launcher, pidFile: file)
    await server.start(settings)
    launcher.print("Address already in use")
    launcher.last.finish(ProcessExit(status: 1, bySignal: false))
    await settle()
    #expect(server.state == .exitedUnexpectedly(ProcessExit(status: 1, bySignal: false)))
    #expect(server.logTail == ["Address already in use"])
    #expect(file.read() == nil)
    // It is never started again by itself.
    #expect(launcher.launches.count == 1)
  }

  @Test func aCrashBySignalIsToldToo() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    launcher.last.finish(ProcessExit(status: 5, bySignal: true))
    await settle()
    #expect(server.state == .exitedUnexpectedly(ProcessExit(status: 5, bySignal: true)))
  }

  @Test func stoppingIsNotAnUnexpectedExit() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    let server = server(launcher, pidFile: file)
    await server.start(settings)
    #expect(file.read()?.pid == 1000)
    server.stop()
    await settle()
    #expect(server.state == .stopped)
    #expect(launcher.last.terminated)
    await server.stopAndWait()
    #expect(file.read() == nil)
  }

  @Test func startingAgainClosesTheRunningServerFirst() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    let first = launcher.last
    await server.start(settings)
    #expect(first.terminated)
    #expect(launcher.launches.count == 2)
    #expect(server.state == .running(pid: 1001))
    // The old one's end must not be mistaken for the new one's.
    await settle()
    #expect(server.state == .running(pid: 1001))
  }

  @Test func aServerThatIgnoresTheStopRequestIsKilled() async {
    let launcher = FakeLauncher()
    launcher.ignoresTerminate = true
    let server = ManagedServer(
      launcher: launcher, files: files, isPortFree: { _ in true }, pidFile: pidFile(), inspector: inspector(),
      stopTimeout: .milliseconds(200))
    await server.start(settings)
    let first = launcher.last
    await server.stopAndWait()
    #expect(first.terminated && first.killed)
    #expect(server.state == .stopped)
  }

  @Test func terminateNowStopsItAtOnce() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    server.terminateNow()
    #expect(launcher.last.terminated)
    #expect(!launcher.last.isRunning)
    #expect(server.state == .stopped)
  }

  @Test func closesAServerLeftRunningByAPreviousRun() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(pid: 777, executable: "/bin/cli")
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs == [777])
    #expect(server.state == .running(pid: 1000))
    #expect(file.read()?.pid == 1000)
    #expect(server.logTail.contains { $0.contains("777") })
  }

  @Test func thePidFileRecordsTheProgramTheSystemSaysIsRunning() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    let server = server(launcher, pidFile: file, inspector: inspector(ownPath: "/real/cli"))
    await server.start(settings)
    #expect(file.read() == ServerPidRecord(pid: 1000, executable: "/real/cli"))
  }

  @Test func closesALeftServerStartedThroughAnotherPathToTheSameProgram() async {
    // The binary was `/bin/cli` (a symbolic link) and the system reports its real path.
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(pid: 777, executable: "/real/cli")
    let log = Log()
    let server = server(
      launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], executable: "/real/cli", log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs == [777])
  }

  @Test func anOldPidFileWithoutAPathIsCheckedAgainstTheCurrentProgram() async throws {
    let launcher = FakeLauncher()
    let file = pidFile()
    try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "777".write(to: file.url, atomically: true, encoding: .utf8)
    #expect(file.read() == ServerPidRecord(pid: 777, executable: nil))
    let log = Log()
    let server = server(
      launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], executable: "/bin/cli", log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs == [777])
  }

  @Test func neverClosesAnotherProgramThatReusedTheProcessID() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(pid: 777, executable: "/bin/cli")
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs.isEmpty && log.killedPIDs.isEmpty)
    #expect(server.state == .running(pid: 1000))
  }
}

extension ManagedServerTests {
  @Test func twoStartsAtOnceLaunchOneServer() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(pid: 777, executable: "/real/cli")
    let log = Log()
    log.lingers = 0.2
    let server = server(
      launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], log: log))
    async let first: Void = server.start(settings)
    async let second: Void = server.start(settings)
    _ = await (first, second)
    #expect(launcher.launches.count == 1)
    #expect(server.state == .running(pid: 1000))
    #expect(file.read()?.pid == 1000)
  }

  @Test func aStartThatWaitsIsCancelledByAStop() async {
    // Switching to "a server already running" while the start waits must not start one.
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(pid: 777, executable: "/real/cli")
    let log = Log()
    log.lingers = 0.3
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], log: log))
    async let start: Void = server.start(settings)
    try? await Task.sleep(for: .milliseconds(80))
    await server.stopAndWait()
    await start
    #expect(launcher.launches.isEmpty)
    #expect(server.state == .stopped)
  }

  @Test func startingRightAfterAStopWaitsForTheOldServerToLeave() async {
    let launcher = FakeLauncher()
    launcher.ignoresTerminate = true
    let server = ManagedServer(
      launcher: launcher, files: files, isPortFree: { _ in true }, pidFile: pidFile(), inspector: inspector(),
      stopTimeout: .milliseconds(200))
    await server.start(settings)
    let first = launcher.last
    server.stop()
    await server.start(settings)
    #expect(first.killed)
    #expect(launcher.launches.count == 2)
    #expect(server.state == .running(pid: 1001))
  }

  @Test func quittingRightAfterAStopStillClosesTheServer() async {
    let launcher = FakeLauncher()
    launcher.ignoresTerminate = true
    let file = pidFile()
    let server = server(launcher, pidFile: file)
    await server.start(settings)
    let first = launcher.last
    server.stop()
    server.terminateNow(timeout: 0.2)
    #expect(first.killed)
    #expect(file.read() == nil)
  }

  @Test func theServerCountsAsStartingOnlyForTheStartupPeriod() async {
    let launcher = FakeLauncher()
    let server = ManagedServer(
      launcher: launcher, files: files, isPortFree: { _ in true }, pidFile: pidFile(), inspector: inspector(),
      startingPeriod: .milliseconds(150))
    #expect(!server.isStarting)
    await server.start(settings)
    #expect(server.isStarting)
    // Other tests hold the main actor for moments: wait for the period to end, up to 2 s.
    for _ in 0..<40 where server.isStarting { try? await Task.sleep(for: .milliseconds(50)) }
    #expect(!server.isStarting)
    #expect(server.isRunning)
  }

  @Test func aServerThatEndsIsNoLongerStarting() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    launcher.last.finish(ProcessExit(status: 1, bySignal: false))
    await settle()
    #expect(!server.isStarting)
  }
}

struct PortProbeTests {
  @Test func aPortNobodyListensOnIsFree() {
    #expect(PortProbe.isFree(59_999))
  }

  @Test func aPortWithAListenerIsNotFree() throws {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    _ = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    #expect(listen(descriptor, 1) == 0)
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &bound) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    #expect(!PortProbe.isFree(Int(UInt16(bigEndian: bound.sin_port))))
  }
}

struct ServerPidFileTests {
  @Test func writesReadsAndRemoves() {
    let file = ServerPidFile(
      url: FileManager.default.temporaryDirectory.appendingPathComponent("ServerPidFileTests-\(UUID())/p.pid"))
    #expect(file.read() == nil)
    file.write(pid: 4242, executable: "/real/cli")
    #expect(file.read() == ServerPidRecord(pid: 4242, executable: "/real/cli"))
    file.remove()
    #expect(file.read() == nil)
  }

  @Test func aGarbledFileReadsAsNothing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ServerPidFileTests-\(UUID()).pid")
    try "not a number".write(to: url, atomically: true, encoding: .utf8)
    #expect(ServerPidFile(url: url).read() == nil)
  }
}

struct ProcessInspectorLiveTests {
  /// `proc_pidpath` reports the real file, not the path a program was started through.
  @Test func recognizesAProgramStartedThroughASymbolicLink() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProcessInspectorLiveTests-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let link = folder.appendingPathComponent("my-sleep")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
    let process = Process()
    process.executableURL = link
    process.arguments = ["20"]
    try process.run()
    defer { process.terminate() }
    let inspector = ProcessInspector.live
    #expect(inspector.isAlive(process.processIdentifier))
    #expect(inspector.isRunning(process.processIdentifier, link.path))
    #expect(inspector.isRunning(process.processIdentifier, "/bin/sleep"))
    #expect(!inspector.isRunning(process.processIdentifier, "/bin/ls"))
    #expect(inspector.executablePath(process.processIdentifier) == "/bin/sleep")
  }
}
