import HubCore
import HubKit
import SwiftUI

/// The DT+ model picker (spec §5): a search field and the models by list (Official, Community, Uncurated) and, inside,
/// by family; every level opens and closes. Only Official is open at first. A click on a model chooses it.
struct ModelPickerView: View {
  let catalog: ModelCatalog
  let selectedFile: String?
  /// Why there is nothing to pick (not connected, model browsing off…); nil when there are models.
  let message: String?
  @Binding var state: ModelTreeState
  let onSelect: (CatalogModel) -> Void
  @State private var query = ""
  @FocusState private var searchFocused: Bool
  @Environment(\.dismiss) private var dismiss

  private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let message {
        Text(verbatim: message)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        TextField(String(localized: "header.model.search"), text: $query)
          .textFieldStyle(.roundedBorder)
          .focused($searchFocused)
        tree
      }
    }
    .padding(12)
    .frame(width: 340, height: 420)
    .onAppear { searchFocused = true }
    .onExitCommand { dismiss() }
  }

  @ViewBuilder private var tree: some View {
    let sections = ModelTree.sections(for: catalog, query: query, state: state)
    if sections.isEmpty {
      Text(String(localized: searching ? "header.model.noResults" : "header.model.empty"))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(sections) { section in
            header(
              title: Self.title(section.source), count: section.count, isExpanded: section.isExpanded, indent: 0,
              weight: .semibold
            ) {
              state.toggle(section.source)
            }
            if section.isExpanded {
              ForEach(section.families) { family in
                header(
                  title: family.family ?? "—", count: family.count, isExpanded: family.isExpanded, indent: 14,
                  weight: .medium
                ) {
                  state.toggle(family.id)
                }
                if family.isExpanded {
                  ForEach(family.models) { model in row(model) }
                }
              }
            }
          }
        }
      }
    }
  }

  private func header(
    title: String, count: Int, isExpanded: Bool, indent: CGFloat, weight: Font.Weight, toggle: @escaping () -> Void
  ) -> some View {
    Button(action: toggle) {
      HStack(spacing: 6) {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 12)
        Text(verbatim: title).fontWeight(weight)
        Text(verbatim: "· \(count)").foregroundStyle(.secondary).monospacedDigit()
        Spacer(minLength: 0)
      }
      .padding(.leading, indent)
      .padding(.vertical, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // While a search is typed every group with results is open, whatever the user opened.
    .disabled(searching)
    .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
    .accessibilityValue(Text(isExpanded ? "▾" : "▸"))
  }

  private func row(_ model: CatalogModel) -> some View {
    let selected = model.file == selectedFile
    return Button {
      onSelect(model)
      dismiss()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "checkmark")
          .font(.system(size: 10, weight: .bold))
          .frame(width: 12)
          .opacity(selected ? 1 : 0)
        Text(verbatim: model.name).lineLimit(1)
        Spacer(minLength: 4)
        if model.isRemote {
          Image(systemName: "cloud").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if model.isLocalOnly {
          Text("model.local").font(.caption2).foregroundStyle(.secondary)
        }
      }
      .padding(.leading, 28)
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        verbatim: model.name
          + (model.isRemote ? ", " + String(localized: "modelpicker.row.cloud") : "")
          + (selected ? ", " + String(localized: "modelpicker.row.selected") : "")))
  }

  /// The names of the lists as Draw Things has them (not translated).
  static func title(_ source: ModelSource) -> String {
    switch source {
    case .official: "Official"
    case .community: "Community"
    case .uncurated: "Uncurated"
    }
  }
}
