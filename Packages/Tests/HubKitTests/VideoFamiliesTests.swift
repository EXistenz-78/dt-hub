import Testing

@testable import HubKit

struct VideoFamiliesTests {
  @Test(arguments: [
    "wan_v2.1_1.3b", "wan_v2.1_14b", "wan_v2.2_5b", "ltx2", "ltx2.3", "hunyuan_video", "svd_i2v", "minimax_h3",
    "longcat_video_avatar_v1.5",
  ])
  func theVideoFamiliesAreRecognised(family: String) {
    #expect(VideoFamilies.contains(family))
  }

  @Test(arguments: ["flux1", "flux2_9b", "z_image", "sdxl_base_v0.9", "v1", "qwen_image_2.1", "cosmos2.5_2b"])
  func theImageFamiliesAreNot(family: String) {
    #expect(!VideoFamilies.contains(family))
  }

  @Test func noFamilyIsNotVideo() {
    #expect(!VideoFamilies.contains(nil))
  }
}
