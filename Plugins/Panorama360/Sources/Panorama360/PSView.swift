import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The tab, in the look of the app.
struct PSView: View {
  @ObservedObject var state: PSState
  var actions: PSViewActions = .none
  @State private var confirmingClear = false
  @State private var choosingFiles = false
  @State private var dropTargeted = false

  var body: some View {
    ScrollView { content }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// What the tab scrolls (the tests draw this, a scroll view does not render to an image).
  var content: some View {
    VStack(spacing: DS.groupGap) {
      canvasCard
      HStack(alignment: .top, spacing: DS.groupGap) {
        PSStickerCard(state: state).frame(maxWidth: .infinity)
        PSPromptCard(state: state, actions: actions).frame(maxWidth: .infinity)
      }
    }
    .padding(DS.groupGap)
  }

  private var isSphere: Bool { state.doc.viewMode == .sphere }
  /// In the sphere, with the result as the source, the canvas is only looked at.
  private var viewOnly: Bool { isSphere && state.effectiveSource == .result }

  private var canvasCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "globe", title: state.text(.canvasTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack(spacing: DS.controlGap) {
          Picker("", selection: Binding(get: { state.doc.viewMode }, set: { state.setView($0) })) {
            Label(state.text(.viewPlane), systemImage: "rectangle").tag(PSViewMode.plane)
            Label(state.text(.viewSphere), systemImage: "globe").tag(PSViewMode.sphere)
          }
          .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
          if isSphere {
            Picker("", selection: Binding(get: { state.effectiveSource }, set: { state.setSource($0) })) {
              Text(state.text(.sourceCanvas)).tag(PSSource.canvas)
              Text(state.text(.sourceResult)).tag(PSSource.result)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
          }
          Spacer(minLength: 0)
          Text(verbatim: isSphere ? "4:3 · FOV \(Int(state.doc.camera.fov.rounded()))°" : "2048 × 1024 · 360°")
            .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        HStack(spacing: DS.controlGap) {
          Button { choosingFiles = true } label: { Image(systemName: "plus") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.add)).disabled(viewOnly)
          Button { confirmingClear = true } label: { Image(systemName: "trash") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.clearAll)).disabled(state.doc.stickers.isEmpty || viewOnly)
          if isSphere {
            Button { state.resetCamera() } label: { Image(systemName: "scope") }
              .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.resetView))
          }
          Toggle(state.text(.guides), isOn: Binding(get: { state.doc.guides }, set: { value in state.mutate { $0.guides = value } }))
            .toggleStyle(DSCheckboxToggleStyle())
          Spacer(minLength: 0)
        }
        area
        if isSphere { PSCutoutPanel(state: state, actions: actions) }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
      guard case .success(let urls) = result else { return }
      state.addStickers(from: urls)
    }
    .confirmationDialog(state.text(.clearConfirmMessage), isPresented: $confirmingClear) {
      Button(state.text(.clearConfirm), role: .destructive) { state.clearAll() }
      Button(state.text(.cancel), role: .cancel) {}
    }
  }

  /// The picture area (the plane or the sphere view) with the drop of pictures on it.
  private var area: some View {
    Group {
      if isSphere { PSSphereView(state: state) } else { PSCanvasView(state: state) }
    }
    .overlay {
      if dropTargeted && !viewOnly {
        ZStack {
          RoundedRectangle(cornerRadius: DS.boxRadius).fill(DS.accent.opacity(0.25))
          RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
          Text(state.text(.dropHere)).font(.headline)
        }
        .allowsHitTesting(false)
      }
    }
    .onDrop(of: PSDrop.types, isTargeted: $dropTargeted) { providers in
      guard !viewOnly else { return false }
      let temp = URL(fileURLWithPath: state.tempFolder.isEmpty ? NSTemporaryDirectory() : state.tempFolder, isDirectory: true)
      PSDrop.collect(providers, tempFolder: temp) { state.addStickers(from: $0) }
      return true
    }
  }
}
