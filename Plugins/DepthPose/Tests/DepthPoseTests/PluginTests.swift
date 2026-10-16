import DTHubPluginKit
import Foundation
import Testing

@testable import DepthPose

@MainActor
@Suite("DepthPosePlugin")
struct PluginTests {
  @Test func theManifestIsTheOneOfTheSpec() {
    let manifest = DepthPosePlugin().manifest
    #expect(manifest.id == "com.exiztenz.dthub.depthpose")
    #expect(manifest.name == "Depth & Pose")
    #expect(manifest.version == "1.0")
    #expect(manifest.families == nil)
    #expect(manifest.requiresEditModel == true, "the maps are references: only edit and in-context models read them")
  }

  @Test func anUnknownMessageIsUnsupported() async {
    let answer = await DepthPosePlugin().handle(Data(#"{"type":"whatever"}"#.utf8))
    #expect(answer.flatMap { DTHubMessage.type(of: $0) } == "unsupported")
  }
}
