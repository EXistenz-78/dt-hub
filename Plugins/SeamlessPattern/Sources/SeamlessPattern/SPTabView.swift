import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The tab, in the look of the app (named apart from `SPView`, the enum of the repeated views).
struct SPTabView: View {
  @ObservedObject var state: SPState
  @State private var isTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.groupGap) {
      if let warning = state.warning {
        Text(warning).font(.callout).foregroundStyle(.secondary)
          .padding(DS.panelPadding)
          .frame(maxWidth: .infinity, alignment: .leading)
          .dsPanel()
        Spacer(minLength: 0)
      } else {
        controls
        preview
      }
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var controls: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.grid.3x3", title: L.title)
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack(spacing: DS.controlGap) {
          Text(L.repeatTitle).font(.callout).foregroundStyle(.secondary)
          ForEach(SPMode.allCases, id: \.self) { mode in
            Button(L.mode(mode)) { Task { await state.setMode(mode) } }
              .buttonStyle(DSPillButtonStyle(prominent: state.mode == mode))
          }
        }
        HStack(spacing: DS.controlGap) {
          Button(L.prepare) { Task { await state.prepare() } }
            .buttonStyle(DSPillButtonStyle(prominent: true))
            .disabled(!state.canPrepare || !state.active)
          Button(L.stop) { Task { await state.stop() } }
            .buttonStyle(DSPillButtonStyle())
            .disabled(!state.isPrepared)
        }
        if let notice = state.notice {
          Text(notice).font(.caption).foregroundStyle(DS.remove)
        } else if state.isPrepared {
          Text(L.prepared).font(.caption).foregroundStyle(.secondary)
        } else if !state.familySupported {
          Text("This model family is not supported.").font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var preview: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "photo", title: state.source == nil ? L.lastResult : state.source!.lastPathComponent)
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ZStack {
          RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
          if let image = state.previewImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
          } else {
            Text(L.noImage).font(.caption).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
          if isTargeted {
            RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).stroke(DS.accent, lineWidth: 2)
          }
        }
        .dropDestination(for: URL.self) { urls, _ in
          guard let url = urls.first else { return false }
          Task { await state.show(url: url) }
          return true
        } isTargeted: { isTargeted = $0 }

        HStack(spacing: 6) {
          Text(L.view).font(.callout).foregroundStyle(.secondary)
          ForEach(SPView.allCases, id: \.self) { view in
            Button(L.view(view)) { state.view = view }
              .buttonStyle(DSPillButtonStyle(prominent: state.view == view))
          }
        }
        seamRow
        HStack(spacing: DS.controlGap) {
          Button(L.savePNG) { state.savePNG() }
            .buttonStyle(DSPillButtonStyle())
            .disabled(state.image == nil)
          Button(L.showInFinder) { state.showInFinder() }
            .buttonStyle(DSPillButtonStyle())
            .disabled(state.source == nil)
          if !state.status.isEmpty {
            Text(state.status).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var seamRow: some View {
    HStack(spacing: DS.groupGap) {
      Text(L.seam).font(.callout).foregroundStyle(.secondary)
      if let seam = state.seam {
        Text("←→ \(SPState.seamText(seam.leftRight, judged: state.mode.judgesLeftRight))")
        Text("↑↓ \(SPState.seamText(seam.upDown, judged: state.mode.judgesUpDown))")
      } else {
        Text("–").foregroundStyle(.secondary)
      }
    }
    .font(.callout.monospacedDigit())
  }
}
