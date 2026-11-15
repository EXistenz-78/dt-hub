import Darwin
import Foundation
import HubKit

/// Where the numbers of the memory meter come from; replaced with fixed values in tests.
public struct MemorySampler: Sendable {
  /// One reading of the system, DT Hub and (when a pid is given) the server.
  public var sample: @Sendable (_ serverPid: Int32?) -> MemorySnapshot?
  /// The pid of the image server when DT Hub did not start it (Draw Things in attach mode); nil when none runs.
  public var findServer: @Sendable () -> Int32?

  public init(
    sample: @escaping @Sendable (Int32?) -> MemorySnapshot?, findServer: @escaping @Sendable () -> Int32?
  ) {
    self.sample = sample
    self.findServer = findServer
  }

  /// Names of the processes that run the image models (`pbi_comm` is cut at 16 characters, so by prefix).
  static let serverNames = ["gRPCServerCLI", "Draw Things"]

  public static let live = MemorySampler(
    sample: { serverPid in
      guard let available = SystemMemory.availableBytes() else { return nil }
      return MemorySnapshot(
        totalBytes: ProcessInfo.processInfo.physicalMemory, availableBytes: available,
        appBytes: SystemMemory.footprint(of: getpid()) ?? 0,
        serverBytes: serverPid.flatMap { SystemMemory.footprint(of: $0) },
        swapUsedBytes: SystemMemory.swapUsedBytes(), pressure: SystemMemory.pressure())
    },
    findServer: { SystemMemory.firstProcess(namedLike: serverNames) })
}

/// The system calls behind `MemorySampler.live` (no privileges, no entitlements).
enum SystemMemory {
  /// Free, inactive, speculative and purgeable pages, as `MemoryProbe` counts them.
  static func availableBytes() -> UInt64? {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &statistics) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let pages = UInt64(statistics.free_count) + UInt64(statistics.inactive_count)
      + UInt64(statistics.speculative_count) + UInt64(statistics.purgeable_count)
    return pages * UInt64(sysconf(_SC_PAGESIZE))
  }

  static func swapUsedBytes() -> UInt64 {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : 0
  }

  /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
  static func pressure() -> MemoryPressureLevel {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
    switch level {
    case 4...: return .critical
    case 2...: return .warning
    default: return .normal
    }
  }

  /// The physical footprint of a process (what Activity Monitor calls "Memory"); nil when it is gone.
  static func footprint(of pid: Int32) -> UInt64? {
    var info = rusage_info_current()
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
    }
    return result == 0 ? info.ri_phys_footprint : nil
  }

  /// The first process of this user whose name starts with one of the prefixes.
  static func firstProcess(namedLike prefixes: [String]) -> Int32? {
    var pids = [pid_t](repeating: 0, count: 4096)
    let count = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
      / MemoryLayout<pid_t>.size
    let me = getpid()
    for pid in pids.prefix(max(count, 0)) where pid > 1 && pid != me {
      var info = proc_bsdinfo()
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { continue }
      let name = withUnsafePointer(to: info.pbi_comm) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
      }
      if prefixes.contains(where: { name.hasPrefix($0) }) { return pid }
    }
    return nil
  }
}
