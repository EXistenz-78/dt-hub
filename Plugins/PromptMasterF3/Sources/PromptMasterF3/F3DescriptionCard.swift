import DTHubDesign
import SwiftUI

/// La card 1: descrizione generale, Foto/Arte e Shuffle, i gruppi del database con le loro categorie.
struct F3DescriptionCard: View {
  @ObservedObject var state: F3State

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: "1 · " + L.text(.descriptionTitle, italian: state.italian))
      ScrollView {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          NoteField(
            text: $state.document.description, placeholder: L.text(.descriptionPlaceholder, italian: state.italian), minHeight: 84)
          controls
          Divider()
          ForEach(state.catalog.groups(mode: state.document.mode)) { group in GroupView(state: state, group: group) }
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
}

private struct GroupView: View {
  @ObservedObject var state: F3State
  let group: F3CatalogGroup

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
  @ObservedObject var state: F3State
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
