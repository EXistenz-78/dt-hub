import Foundation
import Testing

@testable import TiledUpscale

struct TUDesktopSaverTests {
  @Test func savesWithTheFirstFreeNumberAndNeverOverwrites() throws {
    let folder = TestImages.temporaryFolder()
    let png = Data("x".utf8)
    #expect(try TUDesktopSaver.save(png, in: folder).lastPathComponent == "Tiled Upscale 001.png")
    #expect(try TUDesktopSaver.save(png, in: folder).lastPathComponent == "Tiled Upscale 002.png")
    try FileManager.default.removeItem(at: folder.appendingPathComponent("Tiled Upscale 001.png"))
    #expect(try TUDesktopSaver.save(png, in: folder).lastPathComponent == "Tiled Upscale 003.png")
  }
}
