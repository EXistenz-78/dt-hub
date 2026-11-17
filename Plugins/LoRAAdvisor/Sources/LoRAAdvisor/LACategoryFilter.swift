import DTHubDesign
import SwiftUI

extension LAState {
  /// The word of a category in the language of the tab.
  func name(of category: LACategory) -> String {
    switch category {
    case .character: text(.categoryCharacter)
    case .style: text(.categoryStyle)
    case .slider: text(.categorySlider)
    case .edit: text(.categoryEdit)
    case .turbo: text(.categoryTurbo)
    }
  }
}

/// `All · Character · Style · Slider · Edit · Turbo · No category`: one choice active at a time (spec §6).
struct LACategoryFilter: View {
  @ObservedObject var state: LAState

  var body: some View {
    HStack(spacing: 4) {
      choice(.all, title: state.text(.categoryAll))
      ForEach(LACategory.allCases, id: \.self) { category in
        choice(.only(category), title: state.name(of: category))
      }
      choice(.none, title: state.text(.noCategory))
      Spacer(minLength: 0)
    }
  }

  private func choice(_ filter: LAState.CategoryFilter, title: String) -> some View {
    let selected = state.categoryFilter == filter
    return Button { state.categoryFilter = filter } label: {
      Text(verbatim: title)
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(selected ? Color.white : Color.secondary)
        .background(Capsule().fill(selected ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.background.opacity(0.5))))
        .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.clear) : AnyShapeStyle(.separator)))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
