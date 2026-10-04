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

  private var session: GenerationSession { controller.session }
  private var selected: GeneratedImage? {
    session.results.first { $0.id == picks.primary } ?? session.results.first
  }

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      imageArea
      statusLine
      if !session.results.isEmpty {
        strip
        if let selected { actions(for: selected) }
      }
    }
    .padding(20)
    .frame(minWidth: 520, idealWidth: 720, minHeight: 560, idealHeight: 820)
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

  private var imageArea: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .fill(Color.primary.opacity(0.06))
      if let shownImage {
        Image(decorative: shownImage, scale: 1)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .padding(6)
      } else if session.isRunning {
        ProgressView()
      } else {
        ContentUnavailableView(
          "results.empty.title", systemImage: "photo.on.rectangle",
          description: Text("results.empty.message"))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    ScrollView(.horizontal) {
      HStack(spacing: DS.controlGap) {
        ForEach(session.results) { result in
          thumbnail(of: result)
        }
      }
      .padding(2)
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
            .strokeBorder(isSelected ? DS.accent : Color.clear, lineWidth: 2))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(result.job.prompt)
    .contextMenu {
      let targets = targets(of: result)
      if targets.count == 1 { Button("results.useAsImage") { useAsImage(result) } }
      Button("results.addToMoodboard") { addToMoodboard(targets) }
      Button("results.trash") { trash(targets.map(\.id)) }
    }
    if let url = result.fileURL {
      button.draggable(url)
    } else {
      button
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
      let urls = chosen.compactMap(\.fileURL)
      if !urls.isEmpty {
        Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
          .buttonStyle(DSPillButtonStyle())
      }
      if chosen.count <= 1 {
        Button("results.resume") { controller.resume(result, with: connection) }
          .buttonStyle(DSPillButtonStyle())
      }
      Button("results.trash") { trash(chosen.map(\.id)) }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "results.trash.help"))
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
