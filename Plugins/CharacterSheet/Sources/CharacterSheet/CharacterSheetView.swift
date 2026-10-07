import AppKit
import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The tab, in the look of the app: the picture, the name, the two ways of writing the prompt, and «Prepare».
struct CharacterSheetView: View {
  @ObservedObject var state: CSState
  let prepare: () -> Void
  let openFolder: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "person.text.rectangle", title: "Character Sheet")
      VStack(alignment: .leading, spacing: DS.rowGap) {
        picture
        TextField(L.text(.characterName), text: $state.name)
          .textFieldStyle(.roundedBorder)
        Toggle(L.text(.staticPrompt), isOn: $state.useStatic).toggleStyle(DSCheckboxToggleStyle())
        modelMenu
        HStack(spacing: DS.controlGap) {
          Button {
            prepare()
          } label: {
            if state.busy {
              ProgressView().controlSize(.small)
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "sparkles")
                Text(L.text(.prepare))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(state.busy || !state.active || state.imagePath == nil)
          Button(L.text(.openFolder), action: openFolder).buttonStyle(DSPillButtonStyle())
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(DS.panelPadding)
    }
    .frame(maxWidth: 420, maxHeight: .infinity, alignment: .top)
    .dsPanel()
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var picture: some View {
    HStack(alignment: .top, spacing: DS.rowGap) {
      ZStack {
        RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
        if let path = state.imagePath, let image = NSImage(contentsOfFile: path) {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(4)
        } else {
          Text(L.text(.dropImage)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(8)
        }
      }
      .frame(width: 150, height: 150)
      .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url, (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
          else { return }
          Task { @MainActor in state.imagePath = url.path }
        }
        return true
      }
      Button(L.text(.chooseImage), action: chooseImage).buttonStyle(DSPillButtonStyle())
    }
  }

  private var modelMenu: some View {
    Group {
      if state.visionModels.isEmpty {
        Text(L.text(.noModelsShown)).font(.caption).foregroundStyle(.secondary)
      } else {
        Picker(
          L.text(.llmModel),
          selection: Binding(get: { state.resolvedModel?.name ?? "" }, set: { state.selectedModel = $0 })
        ) {
          ForEach(state.visionModels, id: \.name) { Text($0.name).tag($0.name) }
        }
        .disabled(state.useStatic)
      }
    }
  }

  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { state.imagePath = url.path }
  }
}
