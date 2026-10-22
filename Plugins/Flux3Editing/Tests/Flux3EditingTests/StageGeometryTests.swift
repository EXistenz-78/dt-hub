import CoreGraphics
import DTHubPluginKit
import Testing

@testable import Flux3Editing

struct StageGeometryTests {
  private let image = CGSize(width: 300, height: 200)
  private let square = CGSize(width: 200, height: 200)

  @Test func theWindowPlacesTheImageInTheCanvasLikeControlDoes() {
    // Zoom 0: the image fills the canvas on one axis and is cut on the other (the window is 200×200 at x = 50).
    let geometry = StageGeometry(canvas: square, image: image, window: DTHubImageWindow(x: 50, y: 0, width: 200, height: 200))
    #expect(geometry.canvasAspect == 1)
    #expect(geometry.imageFrame == CGRect(x: -0.25, y: 0, width: 1.5, height: 1))
  }

  @Test func aWindowLargerThanTheImageLeavesMargins() {
    // Zoom −100: the window is 800 wide, the image a quarter of the canvas on each side of the middle.
    let geometry = StageGeometry(canvas: square, image: image, window: DTHubImageWindow(x: -250, y: -300, width: 800, height: 800))
    #expect(geometry.imageFrame.minX > 0 && geometry.imageFrame.minY > 0)
    #expect(geometry.imageFrame.maxX < 1 && geometry.imageFrame.maxY < 1)
    #expect(abs(geometry.imageFrame.midX - 0.5) < 1e-9 && abs(geometry.imageFrame.midY - 0.5) < 1e-9)
  }

  @Test func aZoomedInWindowCutsTheImageBeyondTheCanvas() {
    let geometry = StageGeometry(canvas: square, image: image, window: DTHubImageWindow(x: 125, y: 75, width: 50, height: 50))
    #expect(geometry.imageFrame.width == 6 && geometry.imageFrame.height == 4)
    #expect(geometry.imageFrame.minX < 0 && geometry.imageFrame.maxX > 1)
  }

  @Test func withoutAWindowTheWholeImageFitsAndIsCentered() {
    let wide = StageGeometry(canvas: square, image: image, window: nil)
    #expect(wide.imageFrame.width == 1 && abs(wide.imageFrame.height - 2.0 / 3.0) < 1e-9 && abs(wide.imageFrame.midY - 0.5) < 1e-9)
    let tall = StageGeometry(canvas: square, image: CGSize(width: 200, height: 400), window: nil)
    #expect(tall.imageFrame.height == 1 && abs(tall.imageFrame.width - 0.5) < 1e-9 && abs(tall.imageFrame.midX - 0.5) < 1e-9)
  }

  @Test func withoutACanvasSizeTheCanvasIsTheImage() {
    let geometry = StageGeometry(canvas: nil, image: image, window: nil)
    #expect(geometry.canvasAspect == 1.5 && geometry.imageFrame == CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  @Test func aPlainStageHasTheProportionsOfTheImage() {
    let geometry = StageGeometry.plain(image: CGSize(width: 200, height: 400))
    #expect(geometry.canvasAspect == 0.5 && geometry.imageFrame == CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  @Test func nonsenseSizesDoNotBreakIt() {
    #expect(StageGeometry(canvas: .zero, image: .zero, window: nil).canvasAspect == 1)
    let broken = StageGeometry(canvas: square, image: image, window: DTHubImageWindow(x: 0, y: 0, width: 0, height: 0))
    #expect(broken.imageFrame.width.isFinite && broken.imageFrame.height.isFinite)
  }
}
