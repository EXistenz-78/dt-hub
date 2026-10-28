import CoreGraphics
import Foundation
import ImageIO

extension PFState {
  func setViewerOpen(_ open: Bool) {
    if doc.viewerOpen != open { mutate { $0.viewerOpen = open } }
  }

  /// Pictures dropped on the viewer (from the Finder or the Results strip): the first one that can be read is shown as the result, and «Fix the seam»
  /// works on it. A file that cannot be read says so and changes nothing.
  func dropPictures(_ urls: [URL]) {
    error = nil
    for url in urls {
      guard PFResultLoader.load(url) != nil else {
        error = text(.unreadableFile, url.lastPathComponent)
        continue
      }
      markDropped(url.path)
      setShown(url.path)
      setViewerOpen(true)
      error = nil
      return
    }
  }

  // MARK: the seam button

  /// Why «Fix the seam» is off; nil when it is on. It looks at the real size of the shown picture's file, not at the (reduced) picture drawn.
  var seamReason: PFSeamReason? {
    guard let path = lastResultPath else { return .noResult }
    guard let size = Self.pixelSize(of: URL(fileURLWithPath: path)) else { return .unreadable }
    if case .failure(let reason) = PFSeam.plan(width: size.width, height: size.height) { return reason }
    return nil
  }

  func seamReasonText(_ reason: PFSeamReason) -> String {
    switch reason {
    case .noResult: text(.seamNoResult)
    case .unreadable: text(.seamUnreadable)
    case .notTwoToOne: text(.seamNotTwoToOne)
    case .sizeNotMultipleOf64: text(.seamSize)
    case .tooBig: text(.seamTooBig)
    }
  }

  private static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }

  /// Proposes the one-pass pipeline (the Seamfix pass on the shown panorama) to the app; the user then presses RUN.
  func fixSeam(contribute: PFContribute) async {
    error = nil
    notice = nil
    if let reason = seamReason {
      error = seamReasonText(reason)
      return
    }
    guard let path = lastResultPath, !isSending else { return }
    isSending = true
    defer { isSending = false }
    // The reading of a big panorama is not done on the main thread.
    let image = await Task.detached(priority: .userInitiated) { PFResultLoader.load(URL(fileURLWithPath: path), maxSide: nil) }.value
    guard let image else {
      error = text(.seamUnreadable)
      return
    }
    let made = PFSession(kind: .seamOnly(panorama: image), folder: exchangeFolder)
    let pipeline: [String: Any] = ["name": text(.seamPipelineName), "guided": true, "passes": made.passCount, "estimate": made.estimate()]
    if let message = problem(in: await contribute(["pipeline": pipeline])) {
      error = message
      return
    }
    session = made
    notice = readyNote()
  }

  // MARK: looking around

  func lookAround(dx: Double, dy: Double, width: Double) {
    var turned = camera
    turned.look(dx: dx, dy: dy, width: width)
    camera = turned
  }

  func zoom(by delta: Double) {
    var zoomed = camera
    zoomed.zoom(by: delta)
    camera = zoomed
  }

  func resetCamera() { camera = PSCamera() }

  /// Draws the view of the shown panorama from the camera into `preview`. One render runs at a time and only the newest request waits, so a fast drag
  /// never piles up work.
  func renderPreview(width: Int, height: Int) async {
    pendingPreviewSize = (width, height)
    guard !previewBusy else { return }
    previewBusy = true
    defer { previewBusy = false }
    while let size = pendingPreviewSize {
      pendingPreviewSize = nil
      guard let image = resultImage else {
        preview = nil
        continue
      }
      let camera = self.camera
      let drawn = await Task.detached(priority: .userInitiated) {
        try? PSRendererFactory.make().renderView(.panorama(image), camera: camera, width: size.width, height: size.height)
      }.value
      preview = drawn
    }
  }
}
