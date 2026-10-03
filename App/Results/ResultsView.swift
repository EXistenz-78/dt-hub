import AppKit
import HubCore
import HubKit
import SwiftUI

/// The results window (spec §7): live preview while running, then the chosen image; the
/// session strip; for the chosen image: seed, Show in Finder, Resume parameters.
struct ResultsView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  /// The picture shown large: the last one clicked.
  @State private var selectedID: GeneratedImage.ID?
  /// Every picture selected in the strip (⌘-click adds or takes away, ⇧-click extends from `anchorID`).
  @State private var selection: Set<GeneratedImage.ID> = []
  @State private var anchorID: GeneratedImage.ID?
  /// Why "Use as image" or the removal did not work.
  @State private var useError: String?
  /// The chosen picture of a previous launch, read from its file at a larger size than the strip's.
  @State private var restoredFull: (id: GeneratedImage.ID, image: CGImage)?

  private var session: GenerationSession { controller.session }
  private var selected: GeneratedImage? {
    session.results.first { $0.id == selectedID } ?? session.results.first
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
    .onChange(of: session.results.first?.id) {
      selectedID = session.results.first?.id
      selection = selectedID.map { [$0] } ?? []
      anchorID = selectedID
    }
    .background(shortcuts)
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
          session.cancel()
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
          Text("results.preparingMemory").font(.caption).foregroundStyle(.secondary)
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
  }

  /// One picture of the strip: it can be dragged into the Control tab (or any app) as its file,
  /// and the menu uses it as the start image. A click selects it; ⌘ adds or takes it away, ⇧ extends.
  @ViewBuilder private func thumbnail(of result: GeneratedImage) -> some View {
    let isSelected = selection.contains(result.id) || (selection.isEmpty && result.id == selected?.id)
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
    selection.contains(result.id) && selection.count > 1
      ? session.results.filter { selection.contains($0.id) } : [result]
  }

  /// The pictures selected, in the order of the strip.
  private var selectedResults: [GeneratedImage] {
    selection.isEmpty ? selected.map { [$0] } ?? [] : session.results.filter { selection.contains($0.id) }
  }

  private func click(_ result: GeneratedImage) {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.command) {
      if selection.contains(result.id) {
        selection.remove(result.id)
        if selectedID == result.id { selectedID = session.results.first { selection.contains($0.id) }?.id }
      } else {
        selection.insert(result.id)
        selectedID = result.id
      }
      anchorID = result.id
    } else if modifiers.contains(.shift), let anchor = anchorID,
      let from = session.results.firstIndex(where: { $0.id == anchor }),
      let to = session.results.firstIndex(where: { $0.id == result.id })
    {
      selection = Set(session.results[min(from, to)...max(from, to)].map(\.id))
      selectedID = result.id
    } else {
      selection = [result.id]
      selectedID = result.id
      anchorID = result.id
    }
  }

  private func selectAll() {
    selection = Set(session.results.map(\.id))
  }

  /// Moves the pictures to the Trash and picks the nearest one left.
  private func trash(_ ids: [GeneratedImage.ID]) {
    guard !ids.isEmpty else { return }
    useError = nil
    let first = session.results.firstIndex { ids.contains($0.id) } ?? 0
    let failures = session.remove(Set(ids))
    if !failures.isEmpty { useError = failures.joined(separator: "; ") }
    let next = session.results.isEmpty ? nil : session.results[min(first, session.results.count - 1)]
    selectedID = next?.id
    selection = next.map { [$0.id] } ?? []
    anchorID = next?.id
  }

  /// Keys for the strip: ⌫ and ⌘⌫ move the selection to the Trash, ⌘A selects every picture.
  private var shortcuts: some View {
    ZStack {
      Button(action: { trash(selectedResults.map(\.id)) }) { EmptyView() }
        .keyboardShortcut(.delete, modifiers: [])
      Button(action: { trash(selectedResults.map(\.id)) }) { EmptyView() }
        .keyboardShortcut(.delete, modifiers: .command)
      Button(action: { selectAll() }) { EmptyView() }
        .keyboardShortcut("a", modifiers: .command)
    }
    .opacity(0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
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
