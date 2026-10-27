import Foundation
import Testing

@testable import Panorama360

@Suite("Seam geometry")
struct PSSeamTests {
  func plan(_ w: Int, _ h: Int) throws -> PSSeamPlan {
    switch PSSeam.plan(width: w, height: h) {
    case .success(let plan): return plan
    case .failure(let reason): throw reason
    }
  }

  @Test func planForThreeSizes() throws {
    let a = try plan(2048, 1024)
    #expect(a.greenWidth == 256 && a.bandWidth == 512 && a.greenX == 896 && a.bandX == 768 && a.fade == 64 && a.seamX == 1024)
    let b = try plan(1024, 512)
    #expect(b.greenWidth == 128 && b.bandWidth == 256 && b.greenX == 448 && b.bandX == 384 && b.fade == 32)
    let c = try plan(4352, 2176)
    #expect(c.greenWidth == 544 && c.bandWidth == 1088 && c.seamX == 2176 && c.greenX == 1904 && c.bandX == 1632 && c.fade == 136)
  }

  @Test func theGreenIsAnEighthAndTheBandAQuarterBothOnTheSeam() throws {
    for (w, h) in [(2048, 1024), (1024, 512), (4352, 2176), (1536, 768)] {
      let p = try plan(w, h)
      #expect(p.greenWidth == w / 8 && p.bandWidth == w / 4 && p.bandWidth == 2 * p.greenWidth)
      #expect(p.greenX + p.greenWidth / 2 == p.seamX && p.bandX + p.bandWidth / 2 == p.seamX)
      #expect(p.bandX >= 0 && p.bandX + p.bandWidth <= w && p.bandX <= p.greenX && p.greenX + p.greenWidth <= p.bandX + p.bandWidth)
      #expect(p.greenWidth % 2 == 0 && p.bandWidth % 2 == 0)
    }
  }

  @Test func reasonsForRefusal() {
    #expect(PSSeam.plan(width: 1000, height: 1024) == .failure(.notTwoToOne))
    #expect(PSSeam.plan(width: 2000, height: 1000) == .failure(.sizeNotMultipleOf64))
    #expect(PSSeam.plan(width: 2048, height: 1000) == .failure(.sizeNotMultipleOf64), "the whole picture is the pass: both sides count")
    #expect(PSSeam.plan(width: 8320, height: 4160) == .failure(.tooBig))
    #expect((try? plan(8192, 4096)) != nil, "8192 on a side is still taken")
    #expect((try? plan(4352, 2176)) != nil, "more than 2048 is taken now: the pass is the whole panorama")
    #expect((try? plan(2112, 1024)) != nil, "3 % off 2:1 is still taken")
    #expect(PSSeam.plan(width: 2150, height: 1024) == .failure(.notTwoToOne), "5 % off is not")
  }

  @Test func theConstantsAreTheOnesOfTheDesign() {
    #expect(PSSeam.presetName == "PAN · 360 ERP Fast" && PSSeam.strength == 1)
    #expect(PSSeam.greenDivisor == 8 && PSSeam.bandDivisor == 4 && PSSeam.maxSide == 8192)
  }
}
