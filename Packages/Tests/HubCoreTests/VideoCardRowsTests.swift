import HubKit
import Testing

@testable import HubCore

struct VideoCardRowsTests {
  private func model(_ family: String?) -> CatalogModel {
    CatalogModel(
      file: "m.ckpt", name: "M", family: family,
      capabilities: ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false,
        optionalT5: false, clipSkip: false, nativeSize: 1024))
  }

  @Test func imageModelHasNoVideoCards() {
    let rows = VideoCardRows(model: model("flux1"), sampler: .tcd)
    #expect(!rows.showsVideoCard && !rows.showsAccelerators && !rows.showsAudioShift && !rows.showsStochasticSampling)
    #expect(!VideoCardRows(model: nil, sampler: .tcd).showsVideoCard)
  }

  @Test func h3ShowsAudioShiftAndAcceleratorsButNotStochastic() {
    let rows = VideoCardRows(model: model("minimax_h3"), sampler: .tcdTrailing)
    #expect(rows.showsVideoCard && rows.showsAudioShift && rows.showsAccelerators)
    #expect(!rows.showsStochasticSampling)
  }

  @Test func ltxShowsStochasticOnlyWithTCDSamplers() {
    #expect(VideoCardRows(model: model("ltx2.3"), sampler: .tcd).showsStochasticSampling)
    #expect(VideoCardRows(model: model("ltx2.3"), sampler: .tcdTrailing).showsStochasticSampling)
    #expect(!VideoCardRows(model: model("ltx2.3"), sampler: .eulerAncestral).showsStochasticSampling)
    #expect(!VideoCardRows(model: model("ltx2.3"), sampler: .tcd).showsAccelerators)
  }
}
