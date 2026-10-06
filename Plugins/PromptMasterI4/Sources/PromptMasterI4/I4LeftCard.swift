import DTHubDesign
import SwiftUI

/// The left card: the description, Photo/Art and the Shuffle, the four lists, the palette and the background.
struct I4LeftCard: View {
  @ObservedObject var state: I4State

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "curlybraces", title: L.text(.title, italian: state.italian))
      ScrollView {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          FieldLabel(text: L.text(.description, italian: state.italian))
          NoteField(
            text: $state.document.description, placeholder: L.text(.descriptionPlaceholder, italian: state.italian),
            minHeight: 90)
          Divider()
          controls
          ForEach(I4Field.listed, id: \.self) { field in SectionView(state: state, field: field) }
          Divider()
          FieldLabel(text: L.text(.palette, italian: state.italian))
          PaletteRow(
            colors: state.document.colors, limit: Palette.styleLimit, italian: state.italian,
            set: { state.document.colors[$0] = $1 }, remove: { state.document.colors.remove(at: $0) },
            add: { state.addColor() })
          Divider()
          FieldLabel(text: L.text(.background, italian: state.italian))
          NoteField(
            text: $state.document.background, placeholder: L.text(.backgroundPlaceholder, italian: state.italian),
            minHeight: 60, maxHeight: 120)
          SectionCategories(state: state, field: .background)
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

/// A section of the lists (Aesthetics, Lighting, Photo or Art style, Medium): it opens onto its categories.
private struct SectionView: View {
  @ObservedObject var state: I4State
  let field: I4Field

  private var title: String {
    switch field {
    case .aesthetics: return L.text(.aesthetics, italian: state.italian)
    case .lighting: return L.text(.lighting, italian: state.italian)
    case .style:
      return L.text(state.document.mode == .photo ? .photoStyle : .artStyle, italian: state.italian)
    default: return L.text(.medium, italian: state.italian)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: title, detail: nil, count: state.document.chosenCount(in: field, catalog: state.catalog),
        isOpen: state.isOpen(section: field.rawValue), isSection: true
      ) { state.toggleOpen(section: field.rawValue) }
      if state.isOpen(section: field.rawValue) {
        SectionCategories(state: state, field: field).padding(.leading, 14)
      }
    }
  }
}

/// The categories of a field in the current mode, each opening onto its terms (one choice at most).
private struct SectionCategories: View {
  @ObservedObject var state: I4State
  let field: I4Field

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(state.catalog.categories(for: field, mode: state.document.mode)) { category in
        CategoryView(state: state, category: category)
      }
    }
  }
}

private struct CategoryView: View {
  @ObservedObject var state: I4State
  let category: PMCategory

  var body: some View {
    let chosen = state.document.chosen(in: category)
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: state.italian ? category.it : category.en, detail: chosen.map { state.italian ? $0.it : $0.en },
        count: 0, isOpen: state.isOpen(category: category.id), isSection: false
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
