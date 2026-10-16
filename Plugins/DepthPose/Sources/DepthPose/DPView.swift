import AppKit
import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// What the buttons do; the plug-in fills it, a test leaves it empty.
struct DPViewActions {
  var create: () -> Void = {}
  var send: () -> Void = {}
  var saveToDesktop: () -> Void = {}
  var download: () -> Void = {}
  var cancel: () -> Void = {}
  static var none: DPViewActions { DPViewActions() }
}

/// The tab, in the look of the app: the picture and the choices on the left, the maps in a panel on the right.
struct DPView: View {
  @ObservedObject var state: DPState
  let actions: DPViewActions
  @State private var dropTargeted = false

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      controls.frame(width: 320)
      maps.frame(maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Left: the picture, the choice, the model

  private var controls: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: state.text(.image), prominent: true)
      dropZone
      Button(state.text(.open)) { chooseFile() }.buttonStyle(DSPillButtonStyle())
      DSGroupHeader(title: state.text(.mode))
      HStack(spacing: DS.groupGap) {
        Toggle(state.text(.depth), isOn: $state.wantsDepth)
          .toggleStyle(DSCheckboxToggleStyle())
          .disabled(!state.depthAvailable)
          .opacity(state.depthAvailable ? 1 : 0.5)
        Toggle(state.text(.pose), isOn: $state.wantsPose).toggleStyle(DSCheckboxToggleStyle())
      }
      modelSection
      Button(action: actions.create) {
        if state.isWorking {
          ProgressView().controlSize(.small)
        } else {
          HStack(spacing: DS.pillIconGap) {
            Image(systemName: "sparkles")
            Text(state.text(.create))
          }
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .disabled(!state.canCreate)
      if !state.status.isEmpty {
        Text(state.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
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
    .frame(height: 230)
    .onDrop(of: [.image, .fileURL, .url], isTargeted: $dropTargeted, perform: drop)
  }

  /// The tasto «Scarica il modello» only when the model is not found; while it comes, a bar and «Annulla».
  @ViewBuilder private var modelSection: some View {
    if case .downloading(let value) = state.modelState {
      VStack(alignment: .leading, spacing: 6) {
        ProgressView(value: value).tint(DS.accent)
        HStack {
          Text(state.downloadingText(value))
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(state.text(.cancel), action: actions.cancel).buttonStyle(DSPillButtonStyle())
        }
      }
    } else if state.showsDownloadButton {
      Button(action: actions.download) {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "arrow.down.circle")
          Text(state.text(state.modelState == .damaged ? .redownload : .downloadModel))
        }
      }
      .buttonStyle(DSPillButtonStyle())
    }
  }

  // MARK: Right: the maps

  private var maps: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.stack.3d.up", title: state.text(.mode))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if state.depthImage == nil && state.poseImage == nil {
          Text(state.text(.mapsPlaceholder)).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HStack(alignment: .top, spacing: DS.rowGap) {
            if let depth = state.depthImage { thumbnail(depth, title: state.text(.depth)) }
            if let pose = state.poseImage { thumbnail(pose, title: state.text(.pose)) }
          }
          .frame(maxHeight: .infinity)
        }
        HStack(spacing: DS.controlGap) {
          Button(action: actions.send) {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "square.and.arrow.up")
              Text(state.text(.sendToMoodboard))
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(!state.canSend)
          Button(action: actions.saveToDesktop) {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "desktopcomputer")
              Text(state.text(.saveToDesktop))
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.canSave)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private func thumbnail(_ image: CGImage, title: String) -> some View {
    VStack(spacing: 4) {
      Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().interpolation(.high).scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
  }

  // MARK: Getting a picture

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { state.setImage(file: url) }
  }

  /// Takes the picture of what was dropped: its data when the source hands it over, the file otherwise. An address
  /// alone is not followed (the plug-in only contacts Hugging Face, and only for the model).
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
