import Foundation

public enum ProjectCatalogError: Error, Equatable, Sendable {
  case invalidName(ProjectNameError)
  /// The file system's own reason.
  case cannotWrite(String)
}

/// The projects of an output folder, on disk: a project is a direct subfolder that has `.dthub/project.json`.
public struct ProjectCatalog: Sendable {
  public let outputFolder: URL

  public init(outputFolder: URL) {
    self.outputFolder = outputFolder
  }

  /// By name, in the order a person reads (case ignored).
  public func projects() -> [Project] {
    entries().compactMap { project(named: $0) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Only when the folder has the marker.
  public func project(named name: String) -> Project? {
    let project = Project(name: name, folder: outputFolder.appendingPathComponent(name, isDirectory: true))
    return FileManager.default.fileExists(atPath: project.markerFile.path) ? project : nil
  }

  /// Makes the folder, its `.dthub` state folder and the marker. Every name already in the output folder counts as used,
  /// projects and plain folders alike.
  public func create(named raw: String) throws(ProjectCatalogError) -> Project {
    let name: String
    switch ProjectName.validate(raw, existing: entries()) {
    case .success(let valid): name = valid
    case .failure(let error): throw .invalidName(error)
    }
    let project = Project(name: name, folder: outputFolder.appendingPathComponent(name, isDirectory: true))
    do {
      try FileManager.default.createDirectory(at: project.controlFolder, withIntermediateDirectories: true)
      let marker: [String: Any] = ["schema": 1, "created": ISO8601DateFormatter().string(from: Date())]
      let data = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
      try data.write(to: project.markerFile, options: .atomic)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
    return project
  }

  /// The names of everything in the output folder.
  private func entries() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []
  }
}
