import AppKit
import HubCore
import HubKit
import SwiftUI

/// The results window (spec §7): live preview while running, then the chosen image; the
/// session strip; for the chosen image: seed, Show in Finder, Resume parameters.
struct ResultsView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  /// The pictures selected in the strip (⌘-click adds or takes away, ⇧-click extends) and the one
  /// shown large. Something is always selected while the strip is not empty.
  @State private var picks = ResultSelection()
  /// The keys ⌫ and ⌘A act on the strip only after a click in it: this window comes to the front
  /// at every RUN, and the prompt's editing keys must never reach the pictures.
  @State private var stripActive = false
  @Environment(\.controlActiveState) private var activeState
  /// Why "Use as image" or the removal did not work.
  @State private var useError: String?
  /// The chosen picture of a previous launch, read from its file at a larger size than the strip's.
  @State private var restoredFull: (id: GeneratedImage.ID, image: CGImage)?
  /// The information sidebar (prompt, settings, file); open the first time, then as the user left it.
  @AppStorage("results.sidebar.open") private var sidebarOpen = true
  /// The zoom of the large picture (wheel, pinch, drag to move, double-click to fit).
  @State private var zoom = ResultZoom()
  @State private var dragLast: CGSize = .zero
  @State private var pinchLast: CGFloat = 1

  private var session: GenerationSession { controller.session }
  private var selected: GeneratedImage? {
    session.results.first { $0.id == picks.primary } ?? session.results.first
  }

  var body: some View {
    HStack(spacing: DS.panelPadding) {
      VStack(spacing: DS.panelPadding) {
        imageArea
        statusLine
        if !session.results.isEmpty {
          strip
          if let selected { actions(for: selected) }
        }
      }
      if sidebarOpen {
        Divider()
        ResultInfoSidebar(image: selected, selectionCount: picks.ids.count)
      }
    }
    .padding(20)
    .frame(
      minWidth: sidebarOpen ? 820 : 520, idealWidth: sidebarOpen ? 1020 : 720, minHeight: 560, idealHeight: 820)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
    .onChange(of: session.results.first?.id, initial: true) {
      picks = ResultSelection(only: session.results.first?.id)
    }
    .onChange(of: session.results.map(\.id)) { picks.keepOnly(order: session.results.map(\.id)) }
    // Coming back to this window (a RUN brings it to the front) the keys are not on the strip.
    .onChange(of: activeState) { if activeState == .inactive { stripActive = false } }
    .background(DeleteKeyMonitor(isActive: stripActive) { trash(selectedResults.map(\.id)) })
    .background(ArrowKeyMonitor { delta in picks.step(delta, order: session.results.map(\.id)) })
    // A new picture, or a RUN, goes back to the fitted view.
    .onChange(of: selected?.id) { zoom.reset() }
    .onChange(of: session.isRunning) { zoom.reset() }
    .task(id: selected?.id) {
      // A picture read back at launch is a small one: the chosen one is loaded from its file.
      guard let chosen = selected, chosen.isRestored, let url = chosen.fileURL else { return restoredFull = nil }
      let image = await Task.detached { PNGImageStore.image(at: url, maxPixel: 2048) }.value
      restoredFull = image.map { (chosen.id, $0) }
    }
  }

  private var shownImage: CGImage? {
    if session.isRunning, let preview = session.preview { return preview }
    if let restoredFull, restoredFull.id == selected?.id { return restoredFull.image }
    return selected?.image
  }

  /// The clip of the chosen result, shown in place of its still; the live preview of a running generation wins.
  private var shownVideoURL: URL? {
    if session.isRunning, session.preview != nil { return nil }
    return selected?.videoURL
  }

  private var imageArea: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .fill(Color.primary.opacity(0.06))
      if let videoURL = shownVideoURL {
        VideoPlayerView(url: videoURL)
          .id(videoURL)
          .clipShape(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous))
          .padding(6)
      } else if let shownImage {
        zoomableImage(shownImage)
      } else if session.isRunning {
        ProgressView()
      } else {
        ContentUnavailableView(
          "results.empty.title", systemImage: "photo.on.rectangle",
          description: Text("results.empty.message"))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottomLeading) {
      if shownVideoURL != nil, selected?.isPartialVideo == true {
        Text("results.video.partial")
          .font(.caption)
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Capsule().fill(.regularMaterial))
          .padding(10)
      }
    }
    .contextMenu {
      // Lists again the project's pictures the history file forgot (it keeps the last 2000, the strip shows 100).
      if let folder = controller.projectFolder {
        Button("results.rebuild") { Task { await session.rebuildHistory(from: folder) } }
          .disabled(session.isRunning)
      }
    }
    .overlay(alignment: .topTrailing) {
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
  }

  /// The wheel, the pinch and the drag work on a still while nothing is generating; never on a clip or the live preview.
  private var canZoom: Bool { !session.isRunning && shownVideoURL == nil }

  private func fittedSize(of image: CGImage, in view: CGSize) -> CGSize {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    guard w > 0, h > 0, view.width > 0, view.height > 0 else { return .zero }
    let scale = min(view.width / w, view.height / h)
    return CGSize(width: w * scale, height: h * scale)
  }

  private func zoomableImage(_ image: CGImage) -> some View {
    GeometryReader { geo in
      let area = CGSize(width: max(geo.size.width - 12, 1), height: max(geo.size.height - 12, 1))
      let fitted = fittedSize(of: image, in: area)
      let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
      ZStack {
        Image(decorative: image, scale: 1)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .padding(6)
          .scaleEffect(canZoom ? zoom.scale : 1)
          .offset(x: canZoom ? zoom.offset.x : 0, y: canZoom ? zoom.offset.y : 0)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .contentShape(Rectangle())
      .clipped()
      .background(
        ZoomEventMonitor(isActive: canZoom) { anchor, factor in
          zoom.zoom(by: factor, at: anchor, view: area, fitted: fitted)
        }
      )
      .onTapGesture(count: 2) { if canZoom { zoom.reset() } }
      .gesture(
        DragGesture(minimumDistance: 2)
          .onChanged { value in
            guard canZoom, zoom.isZoomed else { return }
            let step = CGSize(
              width: value.translation.width - dragLast.width, height: value.translation.height - dragLast.height)
            dragLast = value.translation
            zoom.pan(by: step, view: area, fitted: fitted)
          }
          .onEnded { _ in dragLast = .zero }
      )
      .gesture(
        MagnifyGesture()
          .onChanged { value in
            guard canZoom else { return }
            let anchor = CGPoint(x: value.startLocation.x - center.x, y: value.startLocation.y - center.y)
            zoom.zoom(by: value.magnification / pinchLast, at: anchor, view: area, fitted: fitted)
            pinchLast = value.magnification
          }
          .onEnded { _ in pinchLast = 1 }
      )
    }
    .padding(0)
  }

  @ViewBuilder private var statusLine: some View {
    switch session.phase {
    case .running(let step, let total):
      HStack(alignment: .center, spacing: DS.controlGap) {
        VStack(alignment: .leading, spacing: 4) {
          if let step {
            ProgressView(value: Double(step), total: Double(max(total, 1)))
          } else {
            ProgressView().progressViewStyle(.linear)
          }
          HStack(spacing: DS.controlGap) {
            if session.batch.count > 1 {
              Text(String(format: String(localized: "results.progress.batch"), session.batch.index, session.batch.count))
            }
            if let step {
              Text(String(format: String(localized: "results.progress.step"), step, total))
            } else {
              Text("results.progress.preparing")
            }
          }
          .font(.caption).foregroundStyle(.secondary)
        }
        Button {
          controller.stop()
        } label: {
          Label("header.stop", systemImage: "stop.fill")
        }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "header.stop.help"))
      }
    case .failed(let error):
      HStack(alignment: .top, spacing: DS.controlGap) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.remove)
        VStack(alignment: .leading, spacing: 2) {
          Text(GenerationErrorText.headline(error))
          if let detail = GenerationErrorText.detail(error) {
            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
          }
        }
        Spacer(minLength: 0)
        Button("results.dismiss") { session.dismissFailure() }
          .buttonStyle(DSPillButtonStyle())
      }
    case .idle:
      if controller.isPreparing {
        HStack(spacing: DS.controlGap) {
          ProgressView().controlSize(.small)
          if let pass = controller.pipelinePass {
            Text(verbatim: String(format: String(localized: "header.stop.pass"), pass.index, pass.count))
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("results.preparingMemory").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var strip: some View {
    ScrollViewReader { proxy in
      stripScroll
        // The arrow keys can move the choice out of sight: the strip follows it.
        .onChange(of: picks.primary) {
          if let id = picks.primary { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
        }
    }
  }

  private var stripScroll: some View {
    ScrollView(.horizontal) {
      HStack(spacing: DS.controlGap) {
        ForEach(session.results) { result in
          thumbnail(of: result)
        }
      }
      .padding(2)
      // Dragging a picture of the selection takes the whole selection; any other picture goes alone.
      .dragContainer(for: DraggedResult.self) { ids in
        session.results.filter { ids.contains($0.id) }.compactMap { result in
          result.exportURL.map { DraggedResult(id: result.id, url: $0) }
        }
      }
      .dragContainerSelection(Array(picks.ids))
    }
    .frame(height: 80)
    .focusable()
    .focusEffectDisabled()
    .onCommand(#selector(NSResponder.selectAll(_:))) { picks.selectAll(order: session.results.map(\.id)) }
  }

  /// One picture of the strip: it can be dragged into the Control tab (or any app) as its file,
  /// and the menu uses it as the start image. A click selects it; ⌘ adds or takes it away, ⇧ extends.
  @ViewBuilder private func thumbnail(of result: GeneratedImage) -> some View {
    let isSelected = picks.ids.contains(result.id)
    let button = Button {
      click(result)
    } label: {
      Image(decorative: result.image, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .strokeBorder(isSelected ? DS.accent : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .top) { elapsedLabel(result.elapsed) }
        .overlay(alignment: .bottomTrailing) { videoBadge(result) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(result.job.prompt)
    .contextMenu {
      let targets = targets(of: result)
      if targets.count == 1 { Button("results.useAsImage") { useAsImage(result) } }
      Button("results.addToMoodboard") { addToMoodboard(targets) }
      Button("results.trash") { trash(targets.map(\.id)) }
    }
    if result.exportURL != nil {
      button.draggable(containerItemID: result.id)
    } else {
      button
    }
  }

  /// The time the picture took, over the top of its thumbnail ("42sec"); nothing for a picture without one.
  @ViewBuilder private func elapsedLabel(_ elapsed: TimeInterval?) -> some View {
    if let text = ElapsedText.label(elapsed) {
      Text(verbatim: text)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .padding(.top, 3)
        .accessibilityLabel(text)
    }
  }

  /// A small play icon and the clip length ("5 s") over the thumbnail of a video; nothing for a picture.
  @ViewBuilder private func videoBadge(_ result: GeneratedImage) -> some View {
    if let seconds = result.videoBadgeSeconds {
      let text = String(format: String(localized: "results.video.badge"), seconds)
      HStack(spacing: 2) {
        Image(systemName: "play.fill")
        Text(verbatim: text)
      }
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(Capsule().fill(Color.black.opacity(0.6)))
      .padding(3)
      .accessibilityLabel(text)
    }
  }

  // MARK: Selection

  /// What a menu on `result` acts on: the whole selection when it is part of it, else just that picture.
  private func targets(of result: GeneratedImage) -> [GeneratedImage] {
    picks.ids.contains(result.id) && picks.ids.count > 1
      ? session.results.filter { picks.ids.contains($0.id) } : [result]
  }

  /// The pictures selected, in the order of the strip.
  private var selectedResults: [GeneratedImage] {
    session.results.filter { picks.ids.contains($0.id) }
  }

  private func click(_ result: GeneratedImage) {
    let modifiers = NSEvent.modifierFlags
    stripActive = true
    picks.click(
      result.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift),
      order: session.results.map(\.id))
  }

  /// Moves the pictures to the Trash and picks the nearest one left.
  private func trash(_ ids: [GeneratedImage.ID]) {
    guard !ids.isEmpty else { return }
    useError = nil
    let before = session.results.map(\.id)
    let failures = session.remove(Set(ids))
    if !failures.isEmpty { useError = failures.joined(separator: "; ") }
    picks.afterRemoval(removed: Set(ids), order: before, remaining: session.results.map(\.id))
  }

  private func useAsImage(_ result: GeneratedImage) {
    useError = nil
    Task {
      do throws(ControlError) {
        if let url = result.fileURL {
          try await controller.control.setImage(fileURL: url, source: .result)
        } else {
          try controller.control.setImage(result.image, name: String(localized: "results.unsaved.name"), source: .result)
        }
      } catch {
        useError = ControlText.error(error)
      }
    }
  }

  private func addToMoodboard(_ results: [GeneratedImage]) {
    useError = nil
    Task {
      var firstError: String?
      for result in results {
        do throws(ControlError) {
          if let url = result.fileURL {
            try await controller.control.addMoodboardImage(fileURL: url, source: .result)
          } else {
            try controller.control.addMoodboardImage(
              result.image, name: String(localized: "results.unsaved.name"), source: .result)
          }
        } catch {
          firstError = firstError ?? ControlText.error(error)
        }
      }
      useError = firstError
    }
  }

  private func actions(for result: GeneratedImage) -> some View {
    let chosen = selectedResults
    return HStack(spacing: DS.controlGap) {
      if chosen.count > 1 {
        Text(String(format: String(localized: "results.selected"), chosen.count))
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text(String(format: String(localized: "results.seed"), String(result.job.parameters.seed)))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        if let error = result.saveError {
          Text("results.notSaved").font(.caption).foregroundStyle(DS.remove).help(error)
        }
      }
      if let useError {
        Text(verbatim: useError).font(.caption).foregroundStyle(DS.remove).lineLimit(2)
      }
      Spacer(minLength: 0)
      if chosen.count <= 1 {
        Button("results.useAsImage") { useAsImage(result) }
          .buttonStyle(DSPillButtonStyle())
      }
      Button("results.addToMoodboard") { addToMoodboard(chosen) }
        .buttonStyle(DSPillButtonStyle())
      if chosen.count <= 1 {
        Button("results.resume") { controller.resume(result, with: connection) }
          .buttonStyle(DSPillButtonStyle())
      }
      let urls = chosen.compactMap(\.exportURL)
      if !urls.isEmpty {
        Button { NSWorkspace.shared.activateFileViewerSelecting(urls) } label: {
          Image(systemName: "folder.fill")
        }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "results.showInFinder"))
        .accessibilityLabel(String(localized: "results.showInFinder"))
      }
      Button { trash(chosen.map(\.id)) } label: {
        Image(systemName: "trash.fill")
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "results.trash.help"))
      .accessibilityLabel(String(localized: "results.trash"))
    }
  }
}

/// ⌫ and ⌘⌫ while the Results window is the key one and the strip has been clicked: calls `onDelete`
/// and takes the key. An AppKit monitor, because the key never reached a SwiftUI key handler on the
/// strip (⌘A, which goes through the menu, did).
private struct DeleteKeyMonitor: NSViewRepresentable {
  var isActive: Bool
  var onDelete: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isActive = isActive
    context.coordinator.onDelete = onDelete
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.remove()
  }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var isActive = false
    var onDelete: () -> Void = {}
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        // Local monitors run on the main thread; the event never leaves it.
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, self.isActive, unsafeEvent.keyCode == 51,
            let window = self.view?.window, unsafeEvent.window === window, window.isKeyWindow
          else { return false }
          let flags = unsafeEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
          guard flags.isEmpty || flags == .command else { return false }
          self.onDelete()
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// ← and → while the Results window is the key one: calls `onStep(-1)` / `onStep(1)` and takes the key. Not with a
/// modifier, and not while a text is being edited. An AppKit monitor, like ⌫ above (SwiftUI never got the arrows here).
private struct ArrowKeyMonitor: NSViewRepresentable {
  var onStep: (Int) -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onStep = onStep }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var onStep: (Int) -> Void = { _ in }
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, unsafeEvent.keyCode == 123 || unsafeEvent.keyCode == 124,
            let window = self.view?.window, unsafeEvent.window === window, window.isKeyWindow,
            !(window.firstResponder is NSText)
          else { return false }
          // The arrow keys always carry .numericPad and .function.
          let flags = unsafeEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
          guard flags.isEmpty else { return false }
          self.onStep(unsafeEvent.keyCode == 123 ? -1 : 1)
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// The scroll wheel over the large picture: calls `onZoom(anchor, factor)` with the point under the cursor (from the
/// centre of this view, y down) and takes the event. Only when `isActive`.
private struct ZoomEventMonitor: NSViewRepresentable {
  var isActive: Bool
  var onZoom: (CGPoint, CGFloat) -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isActive = isActive
    context.coordinator.onZoom = onZoom
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var isActive = false
    var onZoom: (CGPoint, CGFloat) -> Void = { _, _ in }
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, self.isActive, let view = self.view, let window = view.window,
            unsafeEvent.window === window
          else { return false }
          let local = view.convert(unsafeEvent.locationInWindow, from: nil)
          guard view.bounds.contains(local), unsafeEvent.scrollingDeltaY != 0 else { return false }
          // A wheel notch is a coarse step; a trackpad sends many small ones.
          let rate: CGFloat = unsafeEvent.hasPreciseScrollingDeltas ? 0.01 : 0.08
          let factor = exp(unsafeEvent.scrollingDeltaY * rate)
          let anchor = CGPoint(x: local.x - view.bounds.midX, y: view.bounds.midY - local.y)
          self.onZoom(anchor, factor)
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// A picture of the strip while it is dragged: its file (so the Control tab, the Finder and other apps take it).
private struct DraggedResult: Identifiable, Transferable {
  let id: GeneratedImage.ID
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation { $0.url }
  }
}
