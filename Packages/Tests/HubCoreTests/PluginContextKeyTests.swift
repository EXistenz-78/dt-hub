import Testing

@testable import HubCore

struct PluginContextKeyTests {
  private let base = PluginContextKey(
    model: "m.ckpt", family: "flux2_9b", startImageID: nil, moodboardIDs: "", width: 1024, height: 1024)

  @Test func theSameStateIsTheSameKeySoNothingIsSentTwice() {
    #expect(base == PluginContextKey(model: "m.ckpt", family: "flux2_9b", startImageID: nil, moodboardIDs: "", width: 1024, height: 1024))
  }

  @Test func aSizeChangedByHandIsANewKeySoThePluginsHearAboutIt() {
    // Prompt Master's «Apply» keeps the area of the size it was told: it must be told when the user changes it.
    var wider = base
    wider.width = 1536
    var taller = base
    taller.height = 768
    #expect(base != wider && base != taller && wider != taller)
  }

  @Test func theModelTheFamilyTheStartImageAndTheMoodboardCountToo() {
    var other = base
    other.model = "n.ckpt"
    #expect(base != other)
    other = base
    other.family = "qwen_image_2.1"
    #expect(base != other)
    other = base
    other.startImageID = "A"
    #expect(base != other)
    other = base
    other.moodboardIDs = "A,B"
    #expect(base != other)
  }
}
