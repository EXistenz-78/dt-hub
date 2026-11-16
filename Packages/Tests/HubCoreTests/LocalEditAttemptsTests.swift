import Foundation
import HubKit
import Testing

@testable import HubCore

@Suite struct LocalEditAttemptsTests {
  private let opened = Date(timeIntervalSince1970: 1_000_000)

  private func session() -> LocalEditSession {
    LocalEditSession(
      id: UUID(), rect: PixelRect(x: 10, y: 20, width: 1024, height: 1023),
      original: ReferenceImage(
        id: UUID(), name: "photo.png", pixelWidth: 3000, pixelHeight: 2000, source: .result, fileName: "a.png"),
      framing: Framing(), mask: nil, paint: nil, strength: nil, marginFill: nil, generationWidth: 768,
      generationHeight: 512, generationHighRes: false, openedAt: opened)
  }

  private func result(
    after seconds: TimeInterval, video: Bool = false
  ) -> GeneratedImage {
    GeneratedImage(
      image: testImage(),
      job: GenerationJob(
        prompt: "p", model: "m", parameters: GenerationParameters(), videoFPS: video ? 16 : nil),
      date: opened.addingTimeInterval(seconds), fileURL: nil, saveError: nil)
  }

  @Test func keepsOnlyPicturesOfTheCropMadeDuringTheSession() {
    let older = result(after: -5)
    let video = result(after: 10, video: true)
    let wrongSize = result(after: 20)
    let good = result(after: 30)
    let sizes: [GeneratedImage.ID: (width: Int, height: Int)] = [
      older.id: (1024, 1023), video.id: (1024, 1023), wrongSize.id: (1024, 1024), good.id: (1024, 1023),
    ]
    let picked = LocalEditAttempts.select(
      [good, wrongSize, video, older], session: session(), pixelSize: { sizes[$0.id] })
    #expect(picked.map(\.id) == [good.id])
  }

  @Test func aPictureMadeAtTheOpeningCounts() {
    let atOpening = result(after: 0)
    let picked = LocalEditAttempts.select(
      [atOpening], session: session(), pixelSize: { _ in (1024, 1023) })
    #expect(picked.map(\.id) == [atOpening.id])
  }

  @Test func aPictureWithoutAReadableSizeIsLeftOut() {
    let unknown = result(after: 5)
    #expect(LocalEditAttempts.select([unknown], session: session(), pixelSize: { _ in nil }).isEmpty)
  }

  @Test func theNewestComesFirst() {
    let first = result(after: 10)
    let second = result(after: 20)
    let third = result(after: 30)
    let picked = LocalEditAttempts.select(
      [second, first, third], session: session(), pixelSize: { _ in (1024, 1023) })
    #expect(picked.map(\.id) == [third.id, second.id, first.id])
  }
}
