import Foundation
import HubKit
import Testing

@testable import HubCore

@Suite struct GeneratedImageVideoTests {
  private func result(poster: URL?, mp4: URL?, seconds: Double?) -> GeneratedImage {
    var image = GeneratedImage(
      image: testImage(), job: GenerationJob(prompt: "a", model: "m", parameters: GenerationParameters()),
      date: Date(), fileURL: poster, saveError: nil)
    image.videoURL = mp4
    image.videoSeconds = seconds
    return image
  }

  @Test func exportUsesTheVideoWhenThereIsOne() {
    let poster = URL(fileURLWithPath: "/tmp/a.png")
    let mp4 = URL(fileURLWithPath: "/tmp/a.mp4")
    #expect(result(poster: poster, mp4: mp4, seconds: 5).exportURL == mp4)
    #expect(result(poster: poster, mp4: nil, seconds: 5).exportURL == poster)
  }

  @Test func badgeSecondsOnlyForVideosWithALength() {
    let mp4 = URL(fileURLWithPath: "/tmp/a.mp4")
    #expect(result(poster: nil, mp4: mp4, seconds: 5.17).videoBadgeSeconds == 5)
    #expect(result(poster: nil, mp4: mp4, seconds: 0.2).videoBadgeSeconds == 1)
    #expect(result(poster: nil, mp4: mp4, seconds: nil).videoBadgeSeconds == nil)
    #expect(result(poster: nil, mp4: nil, seconds: 5).videoBadgeSeconds == nil)
  }
}
