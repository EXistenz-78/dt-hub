import CoreGraphics
import DTHubPluginKit
import Foundation

/// Dove sta l'immagine dentro la tela (spec §4, §5). La tela dell'immagine di partenza è il canvas di uscita (le proporzioni
/// della Generazione) con l'immagine ingrandita e posizionata come nella card Canvas di Control; quelle del Moodboard sono
/// l'immagine stessa. Le coordinate dei riquadri sono sempre della **tela** (0–1000).
struct StageGeometry: Equatable, Sendable {
  /// Larghezza su altezza della tela.
  var canvasAspect: Double
  /// Dove sta l'immagine, in frazioni della tela (può uscirne: zoom > 0; o non riempirla: zoom < 0, margini).
  var imageFrame: CGRect

  /// `canvas`: la dimensione della Generazione (nil se non si sa: la tela è l'immagine). `window`: la finestra dell'app
  /// (`startImageWindow`); senza, l'immagine intera adattata alla tela.
  init(canvas: CGSize?, image: CGSize, window: DTHubImageWindow?) {
    let imageOK = image.width > 0 && image.height > 0
    guard let canvas, canvas.width > 0, canvas.height > 0, imageOK else {
      canvasAspect = imageOK ? image.width / image.height : 1
      imageFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
      return
    }
    canvasAspect = canvas.width / canvas.height
    if let window, window.width > 0, window.height > 0 {
      imageFrame = CGRect(
        x: -window.x / window.width, y: -window.y / window.height, width: image.width / window.width,
        height: image.height / window.height)
      return
    }
    let imageAspect = image.width / image.height
    if imageAspect > canvasAspect {
      let height = canvasAspect / imageAspect
      imageFrame = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    } else {
      let width = imageAspect / canvasAspect
      imageFrame = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    }
  }

  /// La tela di un'immagine del Moodboard: l'immagine intera, senza ritagli.
  static func plain(image: CGSize) -> StageGeometry { StageGeometry(canvas: nil, image: image, window: nil) }
}
