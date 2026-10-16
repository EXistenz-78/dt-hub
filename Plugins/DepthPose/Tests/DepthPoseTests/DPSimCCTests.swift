import Testing

@testable import DepthPose

@Suite("DPSimCC")
struct DPSimCCTests {
  /// Vectors for `count` keypoints with a value `v` at the given bin of each (zero elsewhere).
  private func vectors(bins: Int, peaks: [(Int, Float)]) -> [Float] {
    var data = [Float](repeating: 0, count: peaks.count * bins)
    for (index, peak) in peaks.enumerated() { data[index * bins + peak.0] = peak.1 }
    return data
  }

  @Test func theLocationIsTheArgmaxOfEachAxis() {
    let x = vectors(bins: 576, peaks: [(100, 0.8), (7, 0.9)])
    let y = vectors(bins: 768, peaks: [(300, 0.6), (5, 0.4)])
    let peaks = DPSimCC.decode(x: x, y: y, keypoints: 2)
    #expect(peaks.count == 2)
    #expect(peaks[0].x == 100 && peaks[0].y == 300)
    #expect(peaks[1].x == 7 && peaks[1].y == 5)
  }

  @Test func theScoreIsTheMeanOfTheTwoMaxima() {
    let peaks = DPSimCC.decode(
      x: vectors(bins: 576, peaks: [(10, 0.8)]), y: vectors(bins: 768, peaks: [(20, 0.6)]), keypoints: 1)
    #expect(abs(peaks[0].score - 0.7) < 1e-6)
    #expect(peaks[0].isFound)
  }

  @Test func aNonPositiveScoreMeansNotFound() {
    let zero = DPSimCC.decode(x: [Float](repeating: 0, count: 576), y: [Float](repeating: 0, count: 768), keypoints: 1)
    #expect(!zero[0].isFound)
    let negative = DPSimCC.decode(
      x: [Float](repeating: -1, count: 576), y: [Float](repeating: -2, count: 768), keypoints: 1)
    #expect(!negative[0].isFound)
  }

  @Test func theBinCountsComeFromTheLength() {
    let wholeBody = DPSimCC.decode(
      x: [Float](repeating: 0.1, count: 133 * 576), y: [Float](repeating: 0.1, count: 133 * 768))
    #expect(wholeBody.count == 133)
    let small = DPSimCC.decode(x: vectors(bins: 10, peaks: [(4, 1)]), y: vectors(bins: 20, peaks: [(9, 1)]), keypoints: 1)
    #expect(small.count == 1 && small[0].x == 4 && small[0].y == 9)
  }

  @Test func emptyOrMismatchedInputGivesNoPeaks() {
    #expect(DPSimCC.decode(x: [], y: [], keypoints: 133).isEmpty)
    #expect(DPSimCC.decode(x: [1, 2, 3], y: [1, 2, 3, 4], keypoints: 2).isEmpty)
    #expect(DPSimCC.decode(x: [1, 2], y: [1, 2], keypoints: 0).isEmpty)
  }

  @Test func theFigureIsEmptyByDefault() {
    let figure = DPFigure(body: [:])
    #expect(figure.face.isEmpty && figure.leftHand.isEmpty && figure.rightHand.isEmpty)
    #expect(DPFigure(body: [:], face: [DPPoint(x: 0, y: 0, confidence: 1)]).face.count == 1)
  }
}
