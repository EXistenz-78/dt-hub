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
  }

  private var shownImage: CGImage? {
    if session.isRunning, let preview = session.preview { return preview }
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
      VStack(alignment: .leading, spacing: 4) {
        if let step {
          ProgressView(value: Double(step), total: Double(max(total, 1)))
          Text(String(format: String(localized: "results.progress.step"), step, total))
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ProgressView().progressViewStyle(.linear)
          Text("results.progress.preparing").font(.caption).foregroundStyle(.secondary)
        }
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
      EmptyView()
    }
  }

  private var strip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: DS.controlGap) {
        ForEach(session.results) { result in
          Button {
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
        }
      }
      .padding(2)
    }
    .frame(height: 80)
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
      Spacer(minLength: 0)
      if let url = result.fileURL {
        Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
          .buttonStyle(DSPillButtonStyle())
      }
      Button("results.resume") { controller.resume(result, with: connection) }
        .buttonStyle(DSPillButtonStyle())
    }
  }
}
