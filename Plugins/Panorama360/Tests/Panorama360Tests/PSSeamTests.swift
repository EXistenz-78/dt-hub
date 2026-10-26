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

  @Test func planForTheThreeSizes() throws {
    let a = try plan(2048, 1024)
    #expect(a.square == 1024 && a.bandWidth == 512 && a.bandX == 768 && a.cropX == 512 && a.fade == 64 && a.seamX == 1024)
    let b = try plan(1024, 512)
    #expect(b.square == 512 && b.bandWidth == 256 && b.bandX == 384 && b.cropX == 256 && b.fade == 32)
    let c = try plan(4096, 2048)
    #expect(c.square == 2048 && c.bandWidth == 1024 && c.bandX == 1536 && c.cropX == 1024 && c.fade == 128)
  }

  @Test func theBandSitsOnTheSeamAndInsideTheSquare() throws {
    for (w, h) in [(2048, 1024), (1024, 512), (4096, 2048), (1536, 768)] {
      let p = try plan(w, h)
      #expect(p.bandX + p.bandWidth / 2 == p.seamX && p.cropX + p.square / 2 == p.seamX)
      #expect(p.cropX >= 0 && p.cropX + p.square <= w && p.bandX >= p.cropX && p.bandX + p.bandWidth <= p.cropX + p.square)
      #expect(p.bandWidth * 2 == p.square)
    }
  }

  @Test func reasonsForRefusal() {
    #expect(PSSeam.plan(width: 1000, height: 1024) == .failure(.notTwoToOne))
    #expect(PSSeam.plan(width: 2000, height: 1000) == .failure(.heightNotMultipleOf64))
    #expect(PSSeam.plan(width: 6144, height: 3072) == .failure(.tooBig))
    #expect((try? plan(2128, 1024)) != nil, "4 % off 2:1 is still taken")
    #expect(PSSeam.plan(width: 2150, height: 1024) == .failure(.notTwoToOne), "5 % off is not")
  }

  @Test func theConstantsAreTheOnesOfTheSpec() {
    #expect(PSSeam.presetName == "PAN · 360 Seamless" && PSSeam.strength == 1 && PSSeam.maskBlur == 30 && PSSeam.maskOutset == 0)
    #expect(PSSeam.maxSquare == 2048)
  }
}
