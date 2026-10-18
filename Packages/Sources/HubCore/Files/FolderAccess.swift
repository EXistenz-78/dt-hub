import Darwin
import Foundation

/// Whether DT Hub can look inside a folder. Tells a folder that is missing (an unmounted disk)
/// from one macOS does not let DT Hub read, which `try?` would show as empty.
public enum FolderAccess: Equatable, Sendable {
  case readable
  /// Does not exist (for example, the disk is not connected).
  case missing
  /// Exists, but macOS does not let DT Hub read it.
  case denied

  public static func access(of path: String, fileManager: FileManager = .default) -> FolderAccess {
    guard fileManager.fileExists(atPath: path) else { return .missing }
    do {
      _ = try fileManager.contentsOfDirectory(atPath: path)
      return .readable
    } catch {
      return isPermissionDenied(error) ? .denied : .readable
    }
  }

  /// A Cocoa "no permission" error, or POSIX `EACCES`/`EPERM` directly or underneath.
  static func isPermissionDenied(_ error: any Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain,
      ns.code == CocoaError.fileReadNoPermission.rawValue || ns.code == CocoaError.fileWriteNoPermission.rawValue
    { return true }
    if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EACCES) || ns.code == Int(EPERM) { return true }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionDenied(underlying) }
    return false
  }
}
