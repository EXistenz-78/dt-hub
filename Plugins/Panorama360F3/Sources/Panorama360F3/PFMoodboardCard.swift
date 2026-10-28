import AppKit
import DTHubDesign
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The Moodboard: the reference pictures (the row's badge is the number `<image N>` the model sees), reorderable by dragging, with the eye and the bin.
struct PFMoodboardCard: View {
  @ObservedObject var state: PFState
  @State private var choosingFiles = false
  @State private var dropTargeted = false
  private static let rowPrefix = "pf3-row:"

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "photo.on.rectangle", title: state.text(.moodboardTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        list
        HStack(spacing: DS.controlGap) {
          Button { choosingFiles = true } label: { Image(systemName: "plus") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.add))
          Spacer(minLength: 0)
          if state.doc.images.isEmpty { Text(state.text(.dropHere)).font(.caption).foregroundStyle(.secondary) }
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(DS.accent, lineWidth: dropTargeted ? 2 : 0))
    .onDrop(of: PFDrop.types, isTargeted: $dropTargeted) { providers in
      PFDrop.collect(providers, tempFolder: state.exchangeFolder) { state.addImages($0) }
      return true
    }
    .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
      guard case .success(let urls) = result else { return }
      let opened = urls.filter { $0.startAccessingSecurityScopedResource() }
      state.addImages(urls)
      opened.forEach { $0.stopAccessingSecurityScopedResource() }
    }
  }

  private var list: some View {
    VStack(spacing: 6) {
      ForEach(state.doc.images) { image in row(image) }
    }
  }

  /// The number the model sees for a picture that is on (1-based); nil for a hidden one.
  private func number(of image: PFImage) -> Int? {
    state.visibleImages.firstIndex(where: { $0.id == image.id }).map { $0 + 1 }
  }

  private func row(_ image: PFImage) -> some View {
    HStack(spacing: 8) {
      PFThumbnail(url: state.imageURL(image))
      Text(image.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
      Text(verbatim: number(of: image).map { "<\($0)>" } ?? "—").font(.caption.monospaced()).foregroundStyle(.secondary)
      Button { state.toggleVisible(image.id) } label: {
        Image(systemName: image.visible ? "eye" : "eye.slash").frame(width: 24, height: 24)
      }
      .buttonStyle(.plain).help(state.text(.toggleVisible))
      Button { state.remove(image.id) } label: { Image(systemName: "trash").frame(width: 24, height: 24) }
        .buttonStyle(.plain).help(state.text(.delete))
    }
    .padding(6)
    .opacity(image.visible ? 1 : 0.45)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius).fill(Color.primary.opacity(0.06)))
    .contentShape(Rectangle())
    .draggable(Self.rowPrefix + image.id.uuidString)
    .dropDestination(for: String.self) { items, _ in
      guard let raw = items.first, raw.hasPrefix(Self.rowPrefix), let id = UUID(uuidString: String(raw.dropFirst(Self.rowPrefix.count)))
      else { return false }
      state.moveImage(id, before: image.id)
      return true
    }
  }
}

/// A small picture of a file, read in the background.
struct PFThumbnail: View {
  let url: URL?
  @State private var image: CGImage?

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
      } else {
        Color.primary.opacity(0.15)
      }
    }
    .frame(width: 46, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
    .task(id: url) {
      guard let url else { return }
      image = await Task.detached(priority: .utility) { () -> CGImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
          source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary)
      }.value
    }
  }
}
