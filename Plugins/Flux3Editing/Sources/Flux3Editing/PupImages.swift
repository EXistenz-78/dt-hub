import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Le immagini per il PUP, preparate come `policy_reference` di `flux3/pup.py`: lati multipli di 32, un budget di pixel per numero
/// di immagini, ridimensionate e salvate in JPEG q92. Il numero di `<ref_image_N>` deve coincidere con l'ordine di allegato.
enum PupImages {
  static let maxImages = 10
  static let quality = 0.92

  /// `reference_size` di BFL; l'arrotondamento è «al pari», come `round` di Python.
  static func size(width: Int, height: Int, count: Int) -> (width: Int, height: Int) {
    let cap = count <= 1 ? 1024 * 1024 : count == 2 ? 724 * 724 : 512 * 512
    func multiple(_ value: Double) -> Int { max(32, Int((value / 32).rounded(.toNearestOrEven)) * 32) }
    func floorMultiple(_ value: Double) -> Int { max(32, Int((value / 32).rounded(.down)) * 32) }
    var (w, h) = (multiple(Double(width)), multiple(Double(height)))
    if w * h > cap {
      let beta = (Double(width * height) / Double(cap)).squareRoot()
      (w, h) = (floorMultiple(Double(width) / beta), floorMultiple(Double(height) / beta))
    }
    if w * h > cap {
      if w == 32 { h = floorMultiple(Double(cap) / Double(w)) } else { w = floorMultiple(Double(cap) / Double(h)) }
    }
    return (w, h)
  }

  /// Scrive i JPEG (`flux3editing-pup-<n>.jpg`) nella cartella, nell'ordine dato; una sorgente che non si legge si salta.
  static func prepare(sources: [(number: Int, path: String)], to folder: URL) -> [EditPicture] {
    let sources = Array(sources.prefix(maxImages))
    return sources.compactMap { source in
      guard let reader = CGImageSourceCreateWithURL(URL(fileURLWithPath: source.path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(reader, 0, nil)
      else { return nil }
      let (w, h) = size(width: image.width, height: image.height, count: sources.count)
      guard let context = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: w, height: h))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      let url = folder.appendingPathComponent("flux3editing-pup-\(source.number).jpg")
      guard let result = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
      else { return nil }
      CGImageDestinationAddImage(destination, result, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { return nil }
      return EditPicture(number: source.number, role: source.number == RefNumbering.startImageNumber ? .start : .reference, path: url.path)
    }
  }
}
