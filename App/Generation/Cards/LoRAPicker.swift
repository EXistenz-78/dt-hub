import HubCore
import HubKit
import SwiftUI

/// The content of the LoRA popover: a search field and the LoRAs offered, in sections by
/// category (`LoRAPickerSections`). The query is `@State` here, so it starts empty every time
/// the popover opens. With `current` a pick replaces that LoRA (it is ticked); without it adds.
struct LoRAPicker: View {
  let loras: [CatalogLoRA]
  /// The files already in the list: shown disabled.
  let chosen: Set<String>
  let current: String?
  let onPick: (CatalogLoRA) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  private var sections: [LoRAPickerSections.Section] {
    LoRAPickerSections.make(loras: loras, query: query)
  }

  var body: some View {
    VStack(spacing: 8) {
      TextField(String(localized: "card.lora.search"), text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .onExitCommand { dismiss() }
        .onSubmit {
          guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
          if let first = sections.lazy.flatMap(\.loras).first(where: { !chosen.contains($0.file) }) {
            onPick(first)
          }
        }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if sections.isEmpty {
            Text(loras.isEmpty ? "card.lora.noneAvailable" : "card.lora.noResults")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
          }
          ForEach(sections, id: \.category) { section in
            Text(Self.title(of: section.category))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.top, 6)
            ForEach(section.loras) { lora in row(lora) }
          }
        }
      }
    }
    .padding(12)
    .frame(width: 320)
    .frame(maxHeight: 360)
    .onAppear { searchFocused = true }
  }

  private static func title(of category: String?) -> LocalizedStringKey {
    switch category {
    case "character": "card.lora.category.character"
    case "style": "card.lora.category.style"
    case "slider": "card.lora.category.slider"
    case "edit": "card.lora.category.edit"
    case "turbo": "card.lora.category.turbo"
    default: "card.lora.category.none"
    }
  }

  private func row(_ lora: CatalogLoRA) -> some View {
    Button {
      onPick(lora)
    } label: {
      HStack(spacing: 6) {
        Text(verbatim: lora.name)
          .lineLimit(1)
          .truncationMode(.middle)
        if lora.family == nil {
          Text("card.lora.unknownFamily")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if lora.file == current {
          Image(systemName: "checkmark")
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(chosen.contains(lora.file))
    .padding(.vertical, 2)
  }
}
