import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct TUSettingsTests {
  let folder = TestImages.temporaryFolder()

  @Test func theDefaultsAreTheOnesOfTheSpec() {
    #expect(TUSettings.standard == TUSettings(free: 192, blur: 30, outset: 29, fade: 64, tile: 1024, toneStrength: 100, toneRadius: 16))
    #expect(TUSettings.standard.tile == 1024)
  }

  @Test func theFadeNeverReachesIntoTheFreePart() {
    let clamped = TUSettings(free: 200, blur: 30, outset: 30, fade: 100).clamped(overlap: .standard)
    #expect(clamped.fade == 56, "256 − 200 is all that is left to fade in")
    #expect(TUSettings(free: 240, blur: 30, outset: 30, fade: 48).clamped(overlap: .standard).fade == 16)
    #expect(TUSettings(free: 300, blur: 99, outset: 500, fade: 5).clamped(overlap: .standard) == TUSettings(free: 256, blur: 30, outset: 100, fade: 0))
    #expect(TUSettings(free: -5, blur: -1, outset: -1, fade: -3).clamped(overlap: .standard) == TUSettings(free: 0, blur: 0, outset: 0, fade: 0))
  }

  @Test func theTileSizeIsAMultipleOf64Between1024And2048() {
    func tile(_ value: Int) -> Int { TUSettings(free: 200, blur: 30, outset: 30, fade: 48, tile: value).clamped(overlap: .standard).tile }
    #expect(tile(3000) == 2048 && tile(900) == 1024 && tile(1100) == 1088 && tile(1536) == 1536 && tile(2048) == 2048)
  }

  @Test func aSettingsFileWithoutTheTileKeepsItsOtherValues() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"factor":2,"overlap":256,"loraWeight":1,"settings":{"free":100,"blur":10,"outset":20,"fade":30}}"#.utf8)
      .write(to: folder.appendingPathComponent("state.json"))
    let choice = TUStore(folder: folder).load()
    #expect(choice.settings == TUSettings(free: 100, blur: 10, outset: 20, fade: 30, tile: 1024, toneStrength: 100, toneRadius: 16))
  }

  @Test func theTileSizeOfTheStateChangesThePassesAndIsKept() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    s.factor = 4
    #expect(s.tileSize == 1536 && s.summary?.passes == 9, "set by the picture, not 25 passes of 1024")
    s.tileSize = 2048
    #expect(s.summary?.passes == 9 && s.plan?.count == 9)
    s.tileSize = 1024
    #expect(s.summary?.passes == 25 && s.plan?.count == 25)
    s.tileSize = 1000
    #expect(s.tileSize == 1024)
    let one = folder.appendingPathComponent("tile")
    s.switchProject(folder: one)
    s.tileSize = 1536
    s.switchProject(folder: folder.appendingPathComponent("other"))
    #expect(s.tileSize == 1024)
    s.switchProject(folder: one)
    #expect(s.tileSize == 1536)
  }

  @Test func theSlidersOfTheStateKeepTheRules() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    #expect(s.maskFree == 192 && s.junctionFade == 64 && s.fadeRange == 0...64)
    s.junctionFade = 100
    #expect(s.junctionFade == 64)
    s.maskFree = 240
    #expect(s.junctionFade == 16 && s.fadeRange == 0...16)
    s.overlap = .wide
    #expect(s.maskFree == 256 && s.fadeRange == 0...64, "the free part goes to the default of 320")
    s.maskFree = 400
    #expect(s.maskFree == 320 && s.junctionFade == 0)
    s.overlap = .standard
    #expect(s.maskFree == 192, "and back to the default of 256")
  }

  @Test func theSettingsAreKeptPerProject() {
    let one = folder.appendingPathComponent("one")
    let two = folder.appendingPathComponent("two")
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.switchProject(folder: one)
    s.maskFree = 100; s.maskBlur = 10; s.maskOutset = 20; s.junctionFade = 64
    s.switchProject(folder: two)
    #expect(s.maskFree == 192 && s.maskBlur == 30 && s.maskOutset == 29 && s.junctionFade == 64)
    s.switchProject(folder: one)
    #expect(s.maskFree == 100 && s.maskBlur == 10 && s.maskOutset == 20 && s.junctionFade == 64)
  }

  @Test func anOldStateFileWithoutSettingsGetsTheDefaults() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"factor":4,"overlap":320,"loraWeight":0.8}"#.utf8).write(to: folder.appendingPathComponent("state.json"))
    let choice = TUStore(folder: folder).load()
    #expect(choice.factor == 4 && choice.settings == TUSettings.defaults(for: .wide))
  }
}
