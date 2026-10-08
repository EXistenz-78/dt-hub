import Foundation

/// The Control state DT Hub kept before there were projects, in Application Support. The first project adopts it, so the
/// work of before is not lost.
public struct LegacyState: Sendable {
  public let controlFile: URL
  public let controlFolder: URL

  /// The paths of the old state (`live` is the real one).
  public init(controlFile: URL, controlFolder: URL) {
    self.controlFile = controlFile
    self.controlFolder = controlFolder
  }

  @MainActor public static var live: LegacyState {
    LegacyState(controlFile: ControlStore.defaultFileURL, controlFolder: FileReferenceStorage.defaultFolder)
  }

  /// `control.json`, or a `Control` folder with something in it.
  public var exists: Bool {
    FileManager.default.fileExists(atPath: controlFile.path) || !controlFolderItems().isEmpty
  }

  /// Moves the old state into the project; true when it moved something. A project that already has a `control.json` is
  /// left alone, and so is the old state.
  public func adopt(into project: Project) throws -> Bool {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: project.controlFile.path) else { return false }
    var moved = false
    try fileManager.createDirectory(at: project.stateFolder, withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: controlFile.path) {
      try fileManager.moveItem(at: controlFile, to: project.controlFile)
      moved = true
    }
    let items = controlFolderItems()
    if !items.isEmpty {
      try fileManager.createDirectory(at: project.controlFolder, withIntermediateDirectories: true)
      for item in items {
        try fileManager.moveItem(at: item, to: project.controlFolder.appendingPathComponent(item.lastPathComponent))
      }
      try? fileManager.removeItem(at: controlFolder)  // empty now
      moved = true
    }
    return moved
  }

  private func controlFolderItems() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: controlFolder, includingPropertiesForKeys: nil)) ?? []
  }
}
