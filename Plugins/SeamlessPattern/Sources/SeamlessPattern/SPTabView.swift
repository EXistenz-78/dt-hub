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
        Text(warning == SPState.customServerWarning ? L.text(.needsServer) : warning).font(.callout).foregroundStyle(.secondary)
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
      DSPanelHeader(icon: "square.split.2x2.fill", title: L.text(.title))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack(spacing: DS.controlGap) {
          Text(L.text(.repeatTitle)).font(.callout).foregroundStyle(.secondary)
          ForEach(SPMode.allCases, id: \.self) { mode in
            modeButton(mode)
          }
          Spacer(minLength: DS.groupGap)
          Button(L.text(.prepare)) { Task { await state.prepare() } }
            .buttonStyle(DSPillButtonStyle(prominent: true))
            .disabled(!state.canPrepare || !state.active)
          Button(L.text(.stop)) { Task { await state.stop() } }
            .buttonStyle(DSPillButtonStyle())
            .disabled(!state.isPrepared)
        }
        if let notice = state.notice {
          Text(notice).font(.caption).foregroundStyle(DS.remove)
        } else if state.isPrepared {
          Text(L.text(.prepared)).font(.caption).foregroundStyle(.secondary)
        } else if !state.familySupported {
          Text(L.text(.unsupportedFamily)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var preview: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "photo", title: state.source == nil ? L.text(.lastResult) : state.source!.lastPathComponent)
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ZStack {
          RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
          if let image = state.previewImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
          } else {
            Text(L.text(.noImage)).font(.caption).foregroundStyle(.secondary)
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
          Text(L.text(.view)).font(.callout).foregroundStyle(.secondary)
          ForEach(SPView.allCases, id: \.self) { view in
            Button(L.view(view)) { state.view = view }
              .buttonStyle(DSPillButtonStyle(prominent: state.view == view))
          }
        }
        seamRow
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  /// Both is a word; the two single directions are only their arrows (the name is the tooltip).
  @ViewBuilder private func modeButton(_ mode: SPMode) -> some View {
    let button = Button { Task { await state.setMode(mode) } } label: {
      switch mode {
      case .both: Text(L.mode(mode))
      case .leftRight: Image(systemName: "arrow.left.arrow.right.square.fill")
      case .upDown: Image(systemName: "arrow.up.arrow.down.square.fill")
      }
    }
    button
      .buttonStyle(DSPillButtonStyle(prominent: state.mode == mode))
      .help(L.mode(mode))
      .accessibilityLabel(L.mode(mode))
  }

  private var seamRow: some View {
    HStack(spacing: DS.groupGap) {
      Text(L.text(.seam)).font(.callout).foregroundStyle(.secondary)
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
