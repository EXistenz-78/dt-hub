import AppKit
import HubCore
import HubKit
import SwiftUI

/// The results window (spec §7): live preview while running, then the chosen image; the
/// session strip; for the chosen image: seed, Show in Finder, Resume parameters.
struct ResultsView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @State private var selectedID: GeneratedImage.ID?
  /// Why "Use as image" did not work.
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
    .onChange(of: session.results.first?.id) { selectedID = session.results.first?.id }
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
  /// and the menu uses it as the start image.
  @ViewBuilder private func thumbnail(of result: GeneratedImage) -> some View {
    let button = Button {
      selectedID = result.id
    } label: {
      Image(decorative: result.image, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .strokeBorder(result.id == selected?.id ? DS.accent : Color.clear, lineWidth: 2))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(result.job.prompt)
    .contextMenu {
      Button("results.useAsImage") { useAsImage(result) }
      Button("results.addToMoodboard") { addToMoodboard(result) }
    }
    if let url = result.fileURL {
      button.draggable(url)
    } else {
      button
    }
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

  private func addToMoodboard(_ result: GeneratedImage) {
    useError = nil
    Task {
      do throws(ControlError) {
        if let url = result.fileURL {
          try await controller.control.addMoodboardImage(fileURL: url, source: .result)
        } else {
          try controller.control.addMoodboardImage(
            result.image, name: String(localized: "results.unsaved.name"), source: .result)
        }
      } catch {
        useError = ControlText.error(error)
      }
    }
  }

  private func actions(for result: GeneratedImage) -> some View {
    HStack(spacing: DS.controlGap) {
      Text(String(format: String(localized: "results.seed"), String(result.job.parameters.seed)))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      if let error = result.saveError {
        Text("results.notSaved").font(.caption).foregroundStyle(DS.remove).help(error)
      }
      if let useError {
        Text(verbatim: useError).font(.caption).foregroundStyle(DS.remove).lineLimit(2)
      }
      Spacer(minLength: 0)
      Button("results.useAsImage") { useAsImage(result) }
        .buttonStyle(DSPillButtonStyle())
      Button("results.addToMoodboard") { addToMoodboard(result) }
        .buttonStyle(DSPillButtonStyle())
      if let url = result.fileURL {
        Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
          .buttonStyle(DSPillButtonStyle())
      }
      Button("results.resume") { controller.resume(result, with: connection) }
        .buttonStyle(DSPillButtonStyle())
    }
  }
}
