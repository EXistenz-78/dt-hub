import AppKit
import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// What the buttons do; the plug-in fills it, a test leaves it empty.
struct TUViewActions {
  var prepare: (_ confirmed: Bool) -> Void = { _ in }
  var useAsStart: () -> Void = {}
  static var none: TUViewActions { TUViewActions() }
}

/// The tab, in the look of the app: the picture and the choices on the left, the summary and the result on the right.
struct TUView: View {
  @ObservedObject var state: TUState
  let actions: TUViewActions
  @State private var dropTargeted = false

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      ScrollView { controls.padding(.trailing, 4) }.frame(width: 330)
      summaryPanel.frame(maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Left: the picture and the choices

  private var controls: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: state.text(.image), prominent: true)
      dropZone
      Button(state.text(.open)) { chooseFile() }.buttonStyle(DSPillButtonStyle())
      DSGroupHeader(title: state.text(.enlargement))
      Picker(state.text(.enlargement), selection: $state.factor) {
        ForEach([2, 4, 8], id: \.self) { Text(verbatim: "\($0)×").tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden()
      DSGroupHeader(title: state.text(.overlap))
      Picker(state.text(.overlap), selection: $state.overlap) {
        ForEach(TileOverlap.allCases, id: \.self) { Text(verbatim: "\($0.rawValue) px").tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden()
      DSGroupHeader(title: state.text(.maskSection))
      sliderRow(state.text(.maskFree), value: Binding(get: { Double(state.maskFree) }, set: { state.maskFree = Int($0.rounded()) }),
        range: 0...Double(state.overlap.rawValue), step: 8, text: "\(state.maskFree) px")
      sliderRow(state.text(.maskBlur), value: Binding(get: { state.maskBlur }, set: { state.maskBlur = $0.rounded() }),
        range: TUSettings.blurRange, step: 1, text: "\(Int(state.maskBlur))")
      sliderRow(state.text(.maskOutset), value: Binding(get: { Double(state.maskOutset) }, set: { state.maskOutset = Int($0.rounded()) }),
        range: 0...Double(TUSettings.outsetRange.upperBound), step: 1, text: "\(state.maskOutset)")
      sliderRow(state.text(.junctionFade), value: Binding(get: { Double(state.junctionFade) }, set: { state.junctionFade = Int($0.rounded()) }),
        range: 0...Double(max(state.fadeRange.upperBound, 1)), step: 4, text: "\(state.junctionFade) px")
        .disabled(state.fadeRange.upperBound == 0)
      DSGroupHeader(title: state.text(.loraStrength))
      HStack {
        Slider(value: $state.loraWeight, in: TUPresetTable.loraWeightRange, step: 0.05)
        Text(verbatim: String(format: "%.2f", state.loraWeight)).font(.callout.monospacedDigit()).frame(width: 44)
      }
      Button {
        actions.prepare(state.awaitingConfirmation)
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "square.grid.3x3")
          Text(state.text(.prepare))
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .disabled(!state.canPrepare || !state.active)
      if !state.status.isEmpty {
        Text(state.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  /// A caption with its value, over a slider.
  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(verbatim: text).font(.caption.monospacedDigit())
      }
      Slider(value: value, in: range, step: step)
    }
  }

  private var dropZone: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .fill(Color.primary.opacity(dropTargeted ? 0.14 : 0.06))
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .strokeBorder(DS.accent.opacity(dropTargeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
      if let image = state.image {
        VStack(spacing: 4) {
          Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().interpolation(.high).scaledToFit()
          Text(state.imageName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
          Text(state.text(.dropHere)).font(.callout).foregroundStyle(.secondary)
        }
      }
    }
    .frame(height: 200)
    .onDrop(of: [.image, .fileURL, .url], isTargeted: $dropTargeted, perform: drop)
  }

  // MARK: Right: the picture and the tiles

  private var summaryPanel: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "flask", title: "Tiled Upscale Lab")
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let summary = state.summary {
          preview(summary)
          Text(verbatim: state.format(.finalSize, summary.width, summary.height)).font(.title3)
          HStack(spacing: DS.groupGap) {
            Text(verbatim: state.format(.tiles, summary.columns, summary.rows)).foregroundStyle(.secondary)
            Text(verbatim: state.format(.passes, summary.passes)).foregroundStyle(.secondary)
          }
          if state.tilesDone > 0 {
            Text(verbatim: state.format(.tilesDone, state.tilesDone, summary.passes)).font(.callout.monospacedDigit())
              .foregroundStyle(DS.accent)
          }
          if summary.cropped {
            Text(state.text(.croppedNote)).font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text(state.text(.resultPlaceholder)).font(.callout).foregroundStyle(.secondary)
        }
        Text(state.text(.tileRegenerated)).font(.caption).foregroundStyle(.secondary)
        if state.resultReady {
          Button(action: actions.useAsStart) {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "photo.on.rectangle")
              Text(state.text(.useAsStart))
            }
          }
          .buttonStyle(DSPillButtonStyle())
        }
      }
      .padding(DS.panelPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .dsPanel()
  }

  /// The enlarged picture, faded, with the grid of the tiles on it; the tiles that are back are drawn over both, at full
  /// opacity, so they hide the grid and a join that is not clean is not masked by a line.
  private func preview(_ summary: TUSummary) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06))
      if let base = state.previewBase {
        Image(nsImage: NSImage(cgImage: base, size: .zero)).resizable().interpolation(.high).opacity(0.35)
      }
      if let plan = state.plan {
        Canvas { context, size in
          let scaleX = size.width / CGFloat(plan.width)
          let scaleY = size.height / CGFloat(plan.height)
          for tile in plan.tiles {
            let rect = CGRect(
              x: CGFloat(tile.rect.x) * scaleX, y: CGFloat(tile.rect.y) * scaleY,
              width: CGFloat(tile.rect.width) * scaleX, height: CGFloat(tile.rect.height) * scaleY)
            context.stroke(Path(rect), with: .color(DS.accent.opacity(0.85)), lineWidth: 1)
          }
        }
      }
      if let progress = state.previewProgress {
        Image(nsImage: NSImage(cgImage: progress, size: .zero)).resizable().interpolation(.high)
      }
    }
    .aspectRatio(CGFloat(summary.width) / CGFloat(summary.height), contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    // It takes all the room the window gives (the picture is fitted in it, centered), no more fixed height.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: Getting a picture

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { state.setImage(file: url) }
  }

  /// Takes the picture of what was dropped: its data when the source hands it over, the file otherwise. An address
  /// alone is not followed (the plug-in uses no network).
  private func drop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    let state = state
    let name = provider.suggestedName ?? ""
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
        Task { @MainActor in
          if let data { state.setImage(data: data, name: name) } else { state.dropHadNoPicture() }
        }
      }
    } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        Task { @MainActor in
          if let url, url.isFileURL { state.setImage(file: url) } else { state.dropHadNoPicture() }
        }
      }
    } else {
      state.dropHadNoPicture()
    }
    return true
  }
}
