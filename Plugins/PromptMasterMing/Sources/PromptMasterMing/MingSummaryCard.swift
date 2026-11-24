import DTHubDesign
import SwiftUI

/// La card di sinistra: l'idea e «Componi con LLM»; poi Foto/Arte e Shuffle, Image Style, i termini della luce, Ambient Lighting
/// e gli altri gruppi del database.
struct MingSummaryCard: View {
  @ObservedObject var state: MingState
  let compose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "slider.horizontal.3", title: L.text(.settingsTitle, italian: state.italian))
      ScrollView {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          FieldLabel(text: L.text(.ideaLabel, italian: state.italian))
          NoteField(text: $state.document.idea, placeholder: L.text(.ideaPlaceholder, italian: state.italian), minHeight: 84)
          HStack {
            Spacer(minLength: 0)
            Button(action: compose) {
              HStack(spacing: DS.pillIconGap) {
                if state.isWriting {
                  ProgressView().controlSize(.small)
                  Text(L.text(.writing, italian: state.italian))
                } else {
                  Image(systemName: "rectangle.3.group")
                  Text(L.text(.composeWithLLM, italian: state.italian))
                }
              }
            }
            .buttonStyle(DSPillButtonStyle())
            .disabled(!state.canCompose)
          }
          Divider()
          controls
          FieldLabel(text: L.text(.imageStyleLabel, italian: state.italian))
          NoteField(
            text: $state.document.imageStyle, placeholder: L.text(.imageStylePlaceholder, italian: state.italian), minHeight: 56,
            maxHeight: 120)
          ForEach(lightGroups) { group in GroupView(state: state, group: group) }
          FieldLabel(text: L.text(.ambientLightingLabel, italian: state.italian))
          NoteField(
            text: $state.document.ambientLighting, placeholder: L.text(.ambientLightingPlaceholder, italian: state.italian),
            minHeight: 44, maxHeight: 100)
          ForEach(otherGroups) { group in GroupView(state: state, group: group) }
        }
        .padding(DS.panelPadding)
      }
      .scrollIndicators(.hidden)
    }
    .dsPanel()
  }

  private var groups: [MingCatalogGroup] { state.catalog.groups(mode: state.document.mode) }
  private var lightGroups: [MingCatalogGroup] { groups.filter { state.catalog.isLighting($0) } }
  private var otherGroups: [MingCatalogGroup] { groups.filter { !state.catalog.isLighting($0) } }

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
  @ObservedObject var state: MingState
  let group: MingCatalogGroup

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
  @ObservedObject var state: MingState
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
