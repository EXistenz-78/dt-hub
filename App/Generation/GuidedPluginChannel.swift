import Foundation

/// What the controller needs from the plug-in registry to run a pipeline the plug-in guides.
struct GuidedPluginChannel {
  /// A message to the plug-in and its answer (nil: none within the time).
  var request: @MainActor (Data, String, Duration) async -> Data?
  /// A new folder for the pictures of one session.
  var sessionFolder: @MainActor () -> URL
  var removeSessionFolder: @MainActor (URL) -> Void
}
