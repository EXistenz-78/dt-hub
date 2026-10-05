/// What decides that the active plug-ins are told where the app stands again (`PluginRegistry.updateContext`): the model
/// and its family, the start image, the Moodboard and the size of the Generation tab. A plug-in that works from the size
/// (Prompt Master's «Apply» keeps the area) has to hear about a change the user makes by hand.
public struct PluginContextKey: Equatable, Sendable {
  public var model: String?
  public var family: String?
  public var startImageID: String?
  /// The ids of the Moodboard pictures that are on, in order, joined by commas.
  public var moodboardIDs: String
  public var width: Int
  public var height: Int

  public init(model: String?, family: String?, startImageID: String?, moodboardIDs: String, width: Int, height: Int) {
    self.model = model
    self.family = family
    self.startImageID = startImageID
    self.moodboardIDs = moodboardIDs
    self.width = width
    self.height = height
  }
}
