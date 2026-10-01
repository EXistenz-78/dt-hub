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

  func inspector(alive: Set<Int32> = [], running: Set<Int32> = [], log: Log = Log()) -> ProcessInspector {
    ProcessInspector(
      isAlive: { log.alive($0, alive) }, isRunning: { pid, _ in running.contains(pid) },
      terminate: { log.terminated($0) }, kill: { log.killed($0) })
  }

  /// What the inspector was asked to do; a closed pid stops being alive.
  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var gone: Set<Int32> = []
    private(set) var terminatedPIDs: [Int32] = []
    private(set) var killedPIDs: [Int32] = []
    func alive(_ pid: Int32, _ alive: Set<Int32>) -> Bool { lock.withLock { alive.contains(pid) && !gone.contains(pid) } }
    func terminated(_ pid: Int32) { lock.withLock { terminatedPIDs.append(pid); gone.insert(pid) } }
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
    #expect(file.read() == 1000)
    server.stop()
    await settle()
    #expect(server.state == .stopped)
    #expect(launcher.last.terminated)
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
    let server = server(launcher)
    await server.start(settings)
    let first = launcher.last
    await server.stopAndWait(timeout: .milliseconds(200))
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
    file.write(777)
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs == [777])
    #expect(server.state == .running(pid: 1000))
    #expect(file.read() == 1000)
    #expect(server.logTail.contains { $0.contains("777") })
  }

  @Test func neverClosesAnotherProgramThatReusedTheProcessID() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(777)
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs.isEmpty && log.killedPIDs.isEmpty)
    #expect(server.state == .running(pid: 1000))
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
    file.write(4242)
    #expect(file.read() == 4242)
    file.remove()
    #expect(file.read() == nil)
  }

  @Test func aGarbledFileReadsAsNothing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ServerPidFileTests-\(UUID()).pid")
    try "not a number".write(to: url, atomically: true, encoding: .utf8)
    #expect(ServerPidFile(url: url).read() == nil)
  }
}
