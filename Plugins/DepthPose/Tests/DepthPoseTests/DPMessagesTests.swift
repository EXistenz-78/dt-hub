import Testing

@testable import DepthPose

@Suite("DPMessages")
struct DPMessagesTests {
  private func entries(_ depth: String?, _ pose: String?) -> [[String: String]] {
    DPMessages.moodboard(depthPath: depth, posePath: pose).map { $0.compactMapValues { $0 as? String } }
  }

  @Test func onlyTheGivenMapsAreSentDepthFirst() {
    #expect(entries("/t/d.png", "/t/p.png") == [["name": "Depth", "path": "/t/d.png"], ["name": "Pose", "path": "/t/p.png"]])
    #expect(entries("/t/d.png", nil) == [["name": "Depth", "path": "/t/d.png"]])
    #expect(entries(nil, "/t/p.png") == [["name": "Pose", "path": "/t/p.png"]])
    #expect(entries(nil, nil).isEmpty)
  }

  @Test func theFilesHaveTheNamesOfThePlan() {
    #expect(DPMessages.depthFile == "com.exiztenz.dthub.depthpose-depth.png")
    #expect(DPMessages.poseFile == "com.exiztenz.dthub.depthpose-pose.png")
  }
}
