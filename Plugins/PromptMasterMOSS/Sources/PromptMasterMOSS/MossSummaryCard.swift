import DTHubDesign
import SwiftUI

/// La card di sinistra: tutto ciò che va nel Summary. Descrizione, Foto/Arte e Shuffle, i gruppi del database, Meta, Canvas,
/// palette e negativo.
struct MossSummaryCard: View {
  @ObservedObject var state: MossState
  @State private var newTag = ""

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: L.text(.summaryTitle, italian: state.italian))
      ScrollView {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          FieldLabel(text: L.text(.descriptionLabel, italian: state.italian))
          NoteField(
            text: $state.document.description, placeholder: L.text(.descriptionPlaceholder, italian: state.italian), minHeight: 84)
          controls
          Divider()
          ForEach(state.catalog.groups(mode: state.document.mode)) { group in GroupView(state: state, group: group) }
          Divider()
          meta
          Divider()
          canvasKind
          Divider()
          FieldLabel(text: L.text(.paletteTitle, italian: state.italian))
          colors(.summary)
          Divider()
          NegativeView(state: state)
        }
        .padding(DS.panelPadding)
      }
      .scrollIndicators(.hidden)
    }
    .dsPanel()
  }

  private var controls: some View {
    HStack(spacing: DS.controlGap) {
      HStack(spacing: 4) {
        modeButton(.photo, L.text(.photo, italian: state.italian), "camera")
        modeButton(.art, L.text(.art, italian: state.italian), "paintpalette")
      }
      Spacer(minLength: 0)
      Button { state.shuffle() } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "dice")
          Text(L.text(.shuffle, italian: state.italian))
        }
      }
      .buttonStyle(DSPillButtonStyle())
    }
  }

  private func modeButton(_ mode: StyleMode, _ title: String, _ icon: String) -> some View {
    Button { state.setMode(mode) } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: icon)
        Text(title)
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: state.document.mode == mode))
  }

  /// Le voci di medium e genere (dal database) e i tag liberi: finiscono in `meta`.
  private var meta: some View {
    VStack(alignment: .leading, spacing: 6) {
      FieldLabel(text: L.text(.metaTitle, italian: state.italian))
      let fromDatabase = state.catalog.metaTerms(state.document.selection)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
        ForEach(fromDatabase, id: \.self) { tag in chip(tag, color: DS.accent, removable: false) {} }
        ForEach(Array(state.document.freeMeta.enumerated()), id: \.offset) { index, tag in
          chip(tag, color: .secondary, removable: true) { state.removeFreeMeta(at: index) }
        }
      }
      TextField(L.text(.metaPlaceholder, italian: state.italian), text: $newTag)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          state.addFreeMeta(newTag)
          newTag = ""
        }
    }
  }

  private func chip(_ text: String, color: Color, removable: Bool, remove: @escaping () -> Void) -> some View {
    HStack(spacing: 4) {
      Text(text).font(.caption.monospaced()).lineLimit(1)
      if removable {
        Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 2)
    .overlay(Capsule().strokeBorder(color, lineWidth: 1))
    .foregroundStyle(color)
  }

  private var canvasKind: some View {
    HStack {
      FieldLabel(text: L.text(.canvasKind, italian: state.italian))
      Spacer(minLength: 0)
      Picker("", selection: $state.document.canvas) {
        ForEach(MossCanvas.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
    }
  }

  private func colors(_ target: MossState.ColorTarget) -> some View {
    PaletteRow(
      colors: state.colors(of: target), limit: state.limit(of: target), italian: state.italian,
      set: { state.setColor($1, at: $0, in: target) }, remove: { state.removeColor(at: $0, from: target) },
      add: { state.addColor(to: target) })
  }
}

private struct GroupView: View {
  @ObservedObject var state: MossState
  let group: MossCatalogGroup

  private var chosenCount: Int { group.categories.filter { category in category.terms.contains { state.isChosen($0.id) } }.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: state.italian ? group.group.it : group.group.en, detail: nil, count: chosenCount,
        isOpen: state.isOpen(group: group.id), isSection: true
      ) { state.toggleOpen(group: group.id) }
      if state.isOpen(group: group.id) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(group.categories) { category in CategoryView(state: state, category: category) }
        }
        .padding(.leading, 14)
      }
    }
  }
}

private struct CategoryView: View {
  @ObservedObject var state: MossState
  let category: PMCategory

  var body: some View {
    let chosen = category.terms.first { state.isChosen($0.id) }
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: state.italian ? category.it : category.en, detail: chosen.map { state.italian ? $0.it : $0.en }, count: 0,
        isOpen: state.isOpen(category: category.id), isSection: false
      ) { state.toggleOpen(category: category.id) }
      if state.isOpen(category: category.id) {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(category.terms) { term in
            Toggle(isOn: Binding(get: { state.isChosen(term.id) }, set: { _ in state.choose(term.id) })) {
              Text(state.italian ? term.it : term.en).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(DSCheckboxToggleStyle())
          }
        }
        .padding(.leading, 18).padding(.top, 2).padding(.bottom, 8)
      }
    }
  }
}

/// Il negativo: le voci scelte (a scelta multipla, nell'ordine del catalogo) e il testo libero.
private struct NegativeView: View {
  @ObservedObject var state: MossState
  @State private var isOpen = false

  private var chosen: [PMTerm] { state.catalog.negativeChoices.filter { state.document.negativeSelection.contains($0.id) } }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      DisclosureRow(
        title: L.text(.negativeTitle, italian: state.italian), detail: chosen.map(\.en).joined(separator: ", "),
        count: chosen.count, isOpen: isOpen, isSection: true
      ) { isOpen.toggle() }
      if isOpen {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(state.catalog.negativeChoices) { term in
            Toggle(isOn: Binding(get: { state.document.negativeSelection.contains(term.id) }, set: { _ in state.toggleNegative(term.id) })) {
              Text(state.italian ? term.it : term.en).font(.callout)
            }
            .toggleStyle(DSCheckboxToggleStyle())
          }
        }
        .padding(.leading, 14)
      }
      TextField(L.text(.negativePlaceholder, italian: state.italian), text: $state.document.negativeText)
        .textFieldStyle(.roundedBorder)
    }
  }
}
