import DTHubDesign
import SwiftUI

/// The left card: groups → categories → terms with a check box, the Photo/Art switch, the Shuffle and the search.
struct TermListView: View {
  @ObservedObject var state: PMState

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "list.bullet.indent", title: L.text(.terms, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        controls
        searchField
        if state.visibleTree.groups.isEmpty {
          Text(L.text(.noMatches, italian: state.italian)).font(.callout).foregroundStyle(.secondary).padding(.top, 6)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(state.visibleTree.groups) { group in GroupSection(state: state, group: group) }
          }
          .padding(.bottom, DS.panelPadding)
        }
        .scrollIndicators(.hidden)
      }
      .padding(DS.panelPadding)
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
    Button { state.mode = mode } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: icon)
        Text(title)
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: state.mode == mode))
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField(L.text(.search, italian: state.italian), text: $state.query).textFieldStyle(.plain)
      if !state.query.isEmpty {
        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
          .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}

/// A row that opens and closes: a chevron, a title and how many terms of it are chosen.
private struct DisclosureRow: View {
  let title: String
  let chosen: Int
  let isOpen: Bool
  let isGroup: Bool
  let help: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(isOpen ? 90 : 0))
        if isGroup {
          DSGroupHeader(title: title, prominent: true)
        } else {
          Text(title).font(.subheadline.weight(.semibold))
        }
        Spacer(minLength: 0)
        if chosen > 0 {
          Text("\(chosen)").font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(DS.accent.opacity(0.25)))
        }
      }
      .padding(.vertical, isGroup ? 7 : 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help ?? "")
  }
}

private struct GroupSection: View {
  @ObservedObject var state: PMState
  let group: GroupNode

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: group.title, chosen: state.chosenCount(inGroup: group.id), isOpen: state.isOpen(group: group.id),
        isGroup: true, help: nil
      ) { state.toggleOpen(group: group.id) }
      if state.isOpen(group: group.id) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(group.categories) { category in CategorySection(state: state, category: category) }
        }
        .padding(.leading, 14)
      }
    }
  }
}

private struct CategorySection: View {
  @ObservedObject var state: PMState
  let category: CategoryNode

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: category.title, chosen: state.chosenCount(inCategory: category.id),
        isOpen: state.isOpen(category: category.id), isGroup: false, help: category.details
      ) { state.toggleOpen(category: category.id) }
      if state.isOpen(category: category.id) {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(category.terms) { term in TermRow(state: state, term: term) }
          if !state.visibleTree.isFiltered { addTerm }
        }
        .padding(.leading, 18).padding(.top, 2).padding(.bottom, 8)
      }
    }
  }

  @ViewBuilder private var addTerm: some View {
    if state.addingIn == category.id {
      HStack(spacing: 6) {
        TextField(L.text(.addTermPlaceholder, italian: state.italian), text: $state.newTermText)
          .textFieldStyle(.roundedBorder).onSubmit { state.addCustomTerm() }
        Button { state.addCustomTerm() } label: { Image(systemName: "checkmark.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(DS.accent)
      }
    } else {
      Button {
        state.newTermText = ""
        state.addingIn = category.id
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "plus")
          Text(L.text(.addTerm, italian: state.italian))
        }
        .font(.caption).foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
  }
}

private struct TermRow: View {
  @ObservedObject var state: PMState
  let term: TermNode

  var body: some View {
    HStack(spacing: 6) {
      Toggle(isOn: Binding(get: { state.selection.contains(term.id) }, set: { state.setChosen(term.id, $0) })) {
        Text(term.title).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
      .toggleStyle(DSCheckboxToggleStyle())
      if term.isCustom {
        Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
          .help(L.text(.customTerm, italian: state.italian))
        Spacer(minLength: 0)
        Button { state.removeCustomTerm(term.id) } label: { Image(systemName: "minus.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeTerm, italian: state.italian))
      }
    }
  }
}
