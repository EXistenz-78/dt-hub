import CoreGraphics
import Foundation
import SwiftUI

/// What the pointer is doing to a sticker (see `PSState.pointerDown`).
enum PSDrag {
  case move(UUID, PSInteraction.Grab)
  case scale(UUID, center: CGPoint, startFOV: Double, startDistance: Double)
  case rotate(UUID, center: CGPoint, startRot: Double, startAngle: Double)
  /// In the sphere view, a drag on the empty view turns the camera: where it was and where the pointer started.
  case look(camera: PSCamera, from: CGPoint)
}

extension PSState {
  // MARK: Reading

  var selected: Sticker? { doc.selectedID.flatMap(sticker) }

  func sticker(_ id: UUID) -> Sticker? { doc.stickers.first { $0.id == id } }

  func image(for sticker: Sticker) -> CGImage? {
    images.image(for: sticker.id, loading: projectFolder?.appendingPathComponent(sticker.file))
  }

  func setImage(_ image: CGImage, for id: UUID) { images.set(image, for: id) }

  /// Width / height of the sticker's picture (1.5 until it is known).
  func aspect(of sticker: Sticker) -> Double {
    guard let image = image(for: sticker), image.height > 0 else { return 1.5 }
    return Double(image.width) / Double(image.height)
  }

  /// The layers to draw: the visible stickers whose picture is there, in order.
  func layers() -> [PSLayer] {
    doc.stickers.compactMap { sticker in
      guard sticker.visible, let image = image(for: sticker) else { return nil }
      return PSLayer(
        image: image, basis: PSProjection.basis(for: sticker, aspect: Double(image.width) / Double(image.height)),
        opacity: sticker.opacity)
    }
  }

  func renderedERP(width: Int, height: Int, uOffset: Double = 0) throws -> CGImage {
    try PSRendererFactory.make().render(layers(), width: width, height: height, uOffset: uOffset)
  }

  /// The drawing of the canvas picture for the view now chosen, ready to run anywhere: the ERP in the plane, the view from the camera in the
  /// sphere (the stickers over green, or the last result).
  func previewJob(scale: Double) -> @Sendable () throws -> CGImage {
    let renderer = PSRendererFactory.make()
    switch doc.viewMode {
    case .plane:
      let layers = layers()
      let w = Int(Self.planeSize.width * scale), h = Int(Self.planeSize.height * scale)
      return { try renderer.render(layers, width: w, height: h, uOffset: 0) }
    case .sphere:
      let camera = doc.camera
      let w = Int(Self.sphereSize.width * scale), h = Int(Self.sphereSize.height * scale)
      let source = viewSource()
      return { try renderer.renderView(source, camera: camera, width: w, height: h) }
    }
  }

  func renderPreview(scale: Double) throws -> CGImage { try previewJob(scale: scale)() }

  /// Draws the canvas picture in the background; a newer request makes an older answer be dropped.
  func refreshPreview(scale: Double) {
    previewGeneration += 1
    let generation = previewGeneration
    let job = previewJob(scale: scale)
    Task.detached(priority: .userInitiated) { [weak self] in
      let image = try? job()
      await MainActor.run {
        guard let self, self.previewGeneration == generation, let image else { return }
        self.preview = image
      }
    }
  }

  /// The keys of the canvas and of the sphere view: arrows nudge the selected sticker (Shift: 5°), ⌫ deletes it, ⌘D duplicates it. Nothing
  /// is edited while the result is shown.
  func handleKey(_ press: KeyPress) -> KeyPress.Result {
    guard doc.source == .canvas || doc.viewMode == .plane else { return .ignored }
    let step = press.modifiers.contains(.shift) ? 5.0 : 1.0
    switch press.key {
    case .leftArrow: nudge(yaw: -step, pitch: 0)
    case .rightArrow: nudge(yaw: step, pitch: 0)
    case .upArrow: nudge(yaw: 0, pitch: step)
    case .downArrow: nudge(yaw: 0, pitch: -step)
    case .delete, .deleteForward: deleteSelected()
    default:
      guard press.modifiers.contains(.command) else { return .ignored }
      duplicateSelected()
    }
    return .handled
  }

  // MARK: Writing

  func select(_ id: UUID?) { mutate { $0.selectedID = id } }

  func update(_ id: UUID, _ change: (inout Sticker) -> Void) {
    mutate { doc in
      if let index = doc.stickers.firstIndex(where: { $0.id == id }) {
        change(&doc.stickers[index])
        doc.stickers[index].clampValues()
      }
    }
  }

  /// A field of a sticker that always reads the state, never a copy the view was drawn with.
  func binding(_ id: UUID, _ keyPath: WritableKeyPath<Sticker, Double>) -> Binding<Double> {
    Binding(
      get: { self.sticker(id)?[keyPath: keyPath] ?? 0 },
      set: { value in self.update(id) { $0[keyPath: keyPath] = value } })
  }

  func nudge(yaw: Double, pitch: Double) {
    guard let id = doc.selectedID else { return }
    update(id) {
      $0.yaw = PSProjection.wrapYaw($0.yaw + yaw)
      $0.pitch = min(89, max(-89, $0.pitch + pitch))
    }
  }

  func deleteSelected() {
    guard let id = doc.selectedID, let index = doc.stickers.firstIndex(where: { $0.id == id }) else { return }
    let removedFile = doc.stickers[index].file
    mutate {
      $0.stickers.remove(at: index)
      $0.selectedID = $0.stickers.isEmpty ? nil : $0.stickers[max(0, index - 1)].id
    }
    images.remove(id)
    removeFileIfUnused(removedFile)
  }

  func duplicateSelected() {
    guard let original = selected, let index = doc.stickers.firstIndex(where: { $0.id == original.id }) else { return }
    var copy = original
    copy.id = UUID()
    copy.yaw = PSProjection.wrapYaw(original.yaw + 10)
    if let image = image(for: original) { images.set(image, for: copy.id) }
    mutate {
      $0.stickers.insert(copy, at: index + 1)
      $0.selectedID = copy.id
    }
  }

  func clearAll() {
    let files = Set(doc.stickers.map(\.file))
    mutate {
      $0.stickers = []
      $0.selectedID = nil
    }
    images.removeAll()
    files.forEach(removeFileIfUnused)
  }

  /// Deletes a sticker's picture from the project unless another sticker (a duplicate) still uses it.
  private func removeFileIfUnused(_ file: String) {
    guard let projectFolder, !doc.stickers.contains(where: { $0.file == file }) else { return }
    try? FileManager.default.removeItem(at: projectFolder.appendingPathComponent(file))
  }

  // MARK: Adding and arranging

  /// One sticker per file, in a cascade from the centre (10° of yaw each), the last one selected. A file that cannot be read, or a photo whose
  /// focal length no longer fits (cropped), is told in `notice`; the other files go in all the same.
  func addStickers(from urls: [URL]) {
    notice = nil
    guard let folder = projectFolder else {
      notice = text(.openProjectFirst)
      return
    }
    var added: [Sticker] = []
    var notes: [String] = []
    for url in urls {
      do {
        let picture = try addPicture(url, folder)
        added.append(
          Sticker(
            name: url.lastPathComponent, file: picture.file, yaw: PSProjection.wrapYaw(10 * Double(added.count)),
            hfov: picture.suggestedHFOV ?? 60))
        if picture.looksCropped { notes.append(text(.croppedPhoto, url.lastPathComponent)) }
      } catch {
        notes.append(text(.unreadableFile, url.lastPathComponent))
      }
    }
    if !added.isEmpty {
      mutate {
        $0.stickers += added
        $0.selectedID = added.last?.id
      }
    }
    notice = notes.isEmpty ? nil : notes.joined(separator: "\n")
  }

  /// Puts a sticker just above `target` in the stack (the layer after it).
  func moveSticker(_ id: UUID, inFrontOf target: UUID) {
    guard id != target, let from = doc.stickers.firstIndex(where: { $0.id == id }) else { return }
    mutate {
      let item = $0.stickers.remove(at: from)
      let to = $0.stickers.firstIndex(where: { $0.id == target }) ?? ($0.stickers.count - 1)
      $0.stickers.insert(item, at: to + 1)
    }
  }

  func setVisible(_ id: UUID, _ visible: Bool) { update(id) { $0.visible = visible } }

  func verticalFOV(of sticker: Sticker) -> Double {
    PSProjection.verticalFOV(hfov: sticker.hfov, aspect: aspect(of: sticker))
  }

  // MARK: The pointer (u, v are fractions of the canvas; `canvas` is its size in points)

  private static let grabRadius = 12.0

  /// `p` in canvas points, taken to the side of `centre` it is nearest to: the picture wraps sideways, so a sticker on the seam has its
  /// handles on both edges and distances and angles must be measured the short way round.
  static func unwrapped(_ p: CGPoint, near centre: CGPoint, width: CGFloat) -> CGPoint {
    var q = p
    if q.x - centre.x > width / 2 { q.x -= width }
    if q.x - centre.x < -width / 2 { q.x += width }
    return q
  }

  func pointerDown(at p: PSUV, canvas: CGSize) {
    drag = nil
    func point(_ q: PSUV) -> CGPoint { CGPoint(x: q.u * canvas.width, y: q.v * canvas.height) }
    if let s = selected, s.visible {
      let handles = PSProjection.handles(of: s, aspect: aspect(of: s))
      let center = point(handles.center)
      let pointer = Self.unwrapped(point(p), near: center, width: canvas.width)
      let rotate = Self.unwrapped(point(handles.rotate), near: center, width: canvas.width)
      if hypot(pointer.x - rotate.x, pointer.y - rotate.y) < Self.grabRadius {
        drag = .rotate(s.id, center: center, startRot: s.rot, startAngle: atan2(pointer.y - center.y, pointer.x - center.x))
        return
      }
      for corner in handles.corners {
        let c = Self.unwrapped(point(corner), near: center, width: canvas.width)
        if hypot(pointer.x - c.x, pointer.y - c.y) < Self.grabRadius {
          drag = .scale(
            s.id, center: center, startFOV: s.hfov, startDistance: hypot(pointer.x - center.x, pointer.y - center.y))
          return
        }
      }
    }
    let pairs = doc.stickers.map { (sticker: $0, aspect: aspect(of: $0)) }
    guard let id = PSProjection.hitTest(u: p.u, v: p.v, stickers: pairs), let hit = sticker(id) else { return }
    select(id)
    drag = .move(id, PSInteraction.grab(hit, at: p))
  }

  func pointerDragged(to p: PSUV, canvas: CGSize, shift: Bool) {
    guard let drag else { return }
    let raw = CGPoint(x: p.u * canvas.width, y: p.v * canvas.height)
    switch drag {
    case .move(let id, let grab):
      update(id) { $0 = PSInteraction.moved($0, to: p, grab: grab) }
    case .scale(let id, let center, let startFOV, let startDistance):
      let pointer = Self.unwrapped(raw, near: center, width: canvas.width)
      update(id) {
        $0 = PSInteraction.scaled(
          $0, startFOV: startFOV, startDistance: startDistance, distance: hypot(pointer.x - center.x, pointer.y - center.y))
      }
    case .rotate(let id, let center, let startRot, let startAngle):
      let pointer = Self.unwrapped(raw, near: center, width: canvas.width)
      update(id) {
        $0 = PSInteraction.rotated(
          $0, startRot: startRot, startAngle: startAngle, angle: atan2(pointer.y - center.y, pointer.x - center.x), snap: shift)
      }
    case .look:
      break
    }
  }

  func pointerUp() { drag = nil }
}
