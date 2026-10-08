import Foundation

/// A project: a subfolder of the output folder that groups the pictures of one job and the state the pictures do not
/// hold (Control, the results strip, the plug-ins). The state lives in a hidden `.dthub` folder inside it.
public struct Project: Equatable, Identifiable, Sendable {
  public let name: String
  /// `<output>/<name>`
  public let folder: URL

  public var id: String { name }

  public init(name: String, folder: URL) {
    self.name = name
    self.folder = folder
  }

  public var stateFolder: URL { folder.appendingPathComponent(".dthub", isDirectory: true) }
  /// What makes a subfolder a project: `{"schema": 1, "created": "<ISO 8601>"}`.
  public var markerFile: URL { stateFolder.appendingPathComponent("project.json") }
  public var controlFile: URL { stateFolder.appendingPathComponent("control.json") }
  /// The copies of the start image, mask, drawing and Moodboard.
  public var controlFolder: URL { stateFolder.appendingPathComponent("Control", isDirectory: true) }
  public var resultsFile: URL { stateFolder.appendingPathComponent("results.json") }

  /// The folder a plug-in keeps its state in for this project.
  public func pluginFolder(_ id: String) -> URL {
    stateFolder.appendingPathComponent("plugins", isDirectory: true).appendingPathComponent(id, isDirectory: true)
  }
}
