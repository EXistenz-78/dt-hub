import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The tab, in the look of the app.
struct PSView: View {
  @ObservedObject var state: PSState
  @State private var confirmingClear = false
  @State private var choosingFiles = false

  var body: some View {
    ScrollView { content }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// What the tab scrolls (the tests draw this, a scroll view does not render to an image).
  var content: some View {
    VStack(spacing: DS.groupGap) {
      canvasCard
      PSStickerCard(state: state)
    }
    .padding(DS.groupGap)
  }

  private var canvasCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "globe", title: state.text(.canvasTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack(spacing: DS.controlGap) {
          Button { choosingFiles = true } label: { Image(systemName: "plus") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.add))
          Button { confirmingClear = true } label: { Image(systemName: "trash") }
            .buttonStyle(DSGlassCircleButtonStyle()).help(state.text(.clearAll)).disabled(state.doc.stickers.isEmpty)
          Toggle(state.text(.guides), isOn: Binding(get: { state.doc.guides }, set: { value in state.mutate { $0.guides = value } }))
            .toggleStyle(DSCheckboxToggleStyle())
          Spacer(minLength: 0)
          Text(verbatim: "2048 × 1024 · 360°").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        PSCanvasView(state: state)
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
}
