import Foundation

/// The JSON the plug-in sends to DT Hub. Pure, so it can be tested.
enum DPMessages {
  /// The names of the maps in the Moodboard.
  static let depthName = "Depth"
  static let poseName = "Pose"
  /// The files in the app's picture folder (named after the plug-in, as Sphere Light does).
  static let depthFile = "com.exiztenz.dthub.depthpose-depth.png"
  static let poseFile = "com.exiztenz.dthub.depthpose-pose.png"

  /// The `moodboard` of a `contribute`: only the maps with a path, depth first.
  static func moodboard(depthPath: String?, posePath: String?) -> [[String: Any]] {
    var entries: [[String: Any]] = []
    if let depthPath { entries.append(["name": depthName, "path": depthPath]) }
    if let posePath { entries.append(["name": poseName, "path": posePath]) }
    return entries
  }
}
