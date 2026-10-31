import AppKit
import DTHubDesign
import HubCore
import SwiftUI

/// The Explore tab: every picture of every project (and of the extra folders) in one grid, with a search over the
/// metadata, a star on each picture and a filter for the starred ones.
struct ExploreView: View {
  @Bindable var model: GalleryModel
  let controller: GenerationController
  let connection: DrawThingsConnection
  /// The chosen picture with its job, loaded for the sidebar (and read by the row of buttons for "Resume parameters").
  @Binding var primaryImage: GeneratedImage?
  let onUse: (GalleryEntry) -> Void
  let onMoodboard: ([GalleryEntry]) -> Void
  let onTrash: ([GalleryEntry]) -> Void

  /// The thumbnails are 50% larger than the strip's (72 pt).
  static let cellSize: CGFloat = 108
  static let cellGap: CGFloat = 8
  private static let gridPadding: CGFloat = 12

  @AppStorage("results.sidebar.open") private var sidebarOpen = true
  @State private var draft = ""
  /// How many cells fit on a row (for ↑ and ↓).
  @State private var columns = 1
  /// The keys ⌫ and ⌘A act on the grid only after a click in it, never while the search box is being typed in.
  @State private var gridActive = false
  @FocusState private var searchFocused: Bool
  @Environment(\.controlActiveState) private var activeState

  var body: some View {
    HStack(spacing: DS.panelPadding) {
      panel
      if sidebarOpen {
        Divider()
        ResultInfoSidebar(image: primaryImage, selectionCount: model.selection.ids.count)
      }
    }
    .task { await model.refresh() }
    .task(id: draft) {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled, model.query != draft else { return }
      model.query = draft
      model.clampSelection()
    }
    .task(id: model.selection.primary) {
      guard let path = model.selection.primary, let entry = model.entries.first(where: { $0.path == path }) else {
        return primaryImage = nil
      }
      primaryImage = await GalleryActions.image(for: entry)
    }
    .onAppear { draft = model.query }
    .onChange(of: model.onlyFavorites) { model.clampSelection() }
    .onChange(of: controller.session.results.first?.id) { Task { await model.refresh() } }
    .onChange(of: searchFocused) { if searchFocused { gridActive = false } }
    .onChange(of: activeState) { if activeState == .inactive { gridActive = false } }
    .background(DeleteKeyMonitor(isActive: gridActive) { onTrash(selectedEntries) })
    .background(
      ArrowKeyMonitor(
        onStep: { model.selection.step($0, order: model.visible.map(\.path)) },
        onVertical: { model.selection.step($0 * columns, order: model.visible.map(\.path)) })
    )
  }

  private var panel: some View {
    ZStack(alignment: .topTrailing) {
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
      VStack(spacing: 0) {
        toolbar
        grid
      }
      Button {
        sidebarOpen.toggle()
      } label: {
        Image(systemName: "sidebar.trailing")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "results.info.toggle"))
      .accessibilityLabel(String(localized: "results.info.toggle"))
      .padding(10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: Toolbar

  private var toolbar: some View {
    HStack(spacing: DS.controlGap) {
      Button(action: addFolder) {
        Image(systemName: "plus")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "results.explore.addFolder"))
      .accessibilityLabel(String(localized: "results.explore.addFolder"))
      foldersMenu
      if model.isIndexing {
        ProgressView().controlSize(.small)
        Text("results.explore.indexing").font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Button {
        model.onlyFavorites.toggle()
      } label: {
        Image(systemName: model.onlyFavorites ? "star.fill" : "star")
          .foregroundStyle(model.onlyFavorites ? Color.yellow : Color.primary)
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "results.explore.favorites"))
      .accessibilityLabel(String(localized: "results.explore.favorites"))
      TextField("results.explore.search", text: $draft)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .frame(width: 240)
    }
    // The corner on the right belongs to the sidebar button.
    .padding(.leading, Self.gridPadding)
    .padding(.trailing, 56)
    .padding(.vertical, 10)
  }

  private var foldersMenu: some View {
    Menu {
      if model.extraFolders.isEmpty {
        Text("results.explore.noFolders")
      }
      ForEach(model.extraFolders, id: \.self) { folder in
        Menu(folder.lastPathComponent) {
          Text(verbatim: folder.path)
          Button("results.explore.removeFolder", role: .destructive) { Task { await model.removeFolder(folder) } }
        }
      }
    } label: {
      Text("results.explore.folders")
    }
    .menuStyle(.button)
    .buttonStyle(DSPillButtonStyle())
    .fixedSize()
  }

  private func addFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = String(localized: "results.explore.addFolder.prompt")
    guard panel.runModal() == .OK else { return }
    Task { for url in panel.urls { await model.addFolder(url) } }
  }

  // MARK: Grid

  @ViewBuilder private var grid: some View {
    let visible = model.visible
    if visible.isEmpty {
      ContentUnavailableView(
        "results.explore.empty.title", systemImage: "photo.on.rectangle",
        description: Text("results.explore.empty.message")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      GeometryReader { geo in
        ScrollViewReader { proxy in
          ScrollView {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: Self.cellSize, maximum: Self.cellSize), spacing: Self.cellGap)],
              alignment: .leading, spacing: Self.cellGap
            ) {
              ForEach(visible) { entry in
                GalleryCell(
                  entry: entry, isSelected: model.selection.ids.contains(entry.path),
                  isFavorite: model.favorites.contains(entry.path),
                  onClick: { click(entry) }, onStar: { model.toggleFavorite(entry.path) }
                )
                .contextMenu {
                  let targets = targets(of: entry)
                  if targets.count == 1 { Button("results.useAsImage") { onUse(entry) } }
                  Button("results.addToMoodboard") { onMoodboard(targets) }
                  Button("results.trash") { onTrash(targets) }
                }
                .draggable(containerItemID: entry.path)
              }
            }
            .padding(Self.gridPadding)
            // Dragging a picture of the selection takes the whole selection; any other picture goes alone.
            .dragContainer(for: DraggedGalleryFile.self) { paths in
              paths.map { DraggedGalleryFile(id: $0, url: URL(fileURLWithPath: $0)) }
            }
            .dragContainerSelection(Array(model.selection.ids))
          }
          .focusable()
          .focusEffectDisabled()
          .onCommand(#selector(NSResponder.selectAll(_:))) { model.selection.selectAll(order: visible.map(\.path)) }
          // The arrow keys can move the choice out of sight: the grid follows it.
          .onChange(of: model.selection.primary) {
            if let id = model.selection.primary { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
          }
        }
        .onChange(of: geo.size.width, initial: true) {
          let room = geo.size.width - 2 * Self.gridPadding + Self.cellGap
          columns = max(1, Int(room / (Self.cellSize + Self.cellGap)))
        }
      }
    }
  }

  /// The pictures selected, in the order of the grid.
  private var selectedEntries: [GalleryEntry] {
    model.visible.filter { model.selection.ids.contains($0.path) }
  }

  /// What a menu on `entry` acts on: the whole selection when it is part of it, else just that picture.
  private func targets(of entry: GalleryEntry) -> [GalleryEntry] {
    model.selection.ids.contains(entry.path) && model.selection.ids.count > 1 ? selectedEntries : [entry]
  }

  private func click(_ entry: GalleryEntry) {
    let modifiers = NSEvent.modifierFlags
    gridActive = true
    searchFocused = false
    model.selection.click(
      entry.path, command: modifiers.contains(.command), shift: modifiers.contains(.shift),
      order: model.visible.map(\.path))
  }
}

/// One picture of the grid: its thumbnail, the star (top left), the name of its project while the mouse is on it.
private struct GalleryCell: View {
  let entry: GalleryEntry
  let isSelected: Bool
  let isFavorite: Bool
  let onClick: () -> Void
  let onStar: () -> Void

  @State private var thumbnail: GalleryThumbnails.Thumbnail?
  @State private var hovering = false

  var body: some View {
    Button(action: onClick) {
      ZStack {
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.08))
        if let thumbnail {
          Image(decorative: thumbnail.image, scale: 1).resizable().scaledToFill()
        }
      }
      .frame(width: ExploreView.cellSize, height: ExploreView.cellSize)
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .strokeBorder(isSelected ? DS.accent : Color.clear, lineWidth: 2)
      )
      .overlay(alignment: .bottomTrailing) {
        if thumbnail?.isVideo == true {
          Image(systemName: "play.fill")
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(4)
        }
      }
      .overlay(alignment: .bottom) {
        if hovering {
          Text(verbatim: entry.project)
            .font(.system(size: 10)).foregroundStyle(.white).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(4)
        }
      }
      .overlay(alignment: .topLeading) { star }
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(entry.url.lastPathComponent)
    .task(id: entry.path) {
      thumbnail = await GalleryThumbnails.shared.thumbnail(for: entry.url, maxPixel: Int(ExploreView.cellSize * 2))
    }
    .id(entry.path)
  }

  private var star: some View {
    Button(action: onStar) {
      Image(systemName: isFavorite ? "star.fill" : "star")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.8))
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color.black.opacity(isFavorite ? 0.6 : 0.45)))
    }
    .buttonStyle(.plain)
    .padding(5)
    .help(String(localized: "results.explore.star"))
    .accessibilityLabel(String(localized: "results.explore.star"))
  }
}
