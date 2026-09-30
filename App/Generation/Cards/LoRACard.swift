import HubCore
import HubKit
import SwiftUI

/// The LoRAs of the next RUN, each with weight, mode and trigger word (spec §6). The menu offers the LoRAs
/// of the chosen model's family and those of unknown family; a LoRA that no longer fits
/// (other family, gone from the server) stays in the list with the reason and is not sent.
/// Trigger words stay in their own field, prefilled from Draw Things; at RUN those of the
/// LoRAs sent go in front of the prompt (`GenerationJob.promptWithTriggers`).
struct LoRACard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var catalog: ModelCatalog { connection.monitor.catalog }
  private var family: String? { controller.family(in: connection) }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.lora"), systemImage: "square.stack.3d.up",
      isExpanded: controller.cards.binding("lora")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if controller.parameters.loras.isEmpty {
          Text("card.lora.none")
            .foregroundStyle(.secondary)
        }
        ForEach(controller.parameters.loras) { selection in
          LoRARow(
            selection: binding(for: selection),
            name: catalog.lora(forFile: selection.file)?.name ?? selection.file,
            status: catalog.status(of: selection, family: family),
            remove: { controller.parameters.removeLoRA(selection.file) })
        }
        addMenu
      }
    }
  }

  /// A row's binding found by file, not by array index: a row still editing when its LoRA
  /// is removed (or replaced by "Resume parameters") then writes nowhere, instead of past
  /// the end of the list or into the LoRA that took its place.
  private func binding(for selection: LoRASelection) -> Binding<LoRASelection> {
    Binding(
      get: { controller.parameters.loras.first { $0.file == selection.file } ?? selection },
      set: { controller.parameters.updateLoRA($0) })
  }

  private var addMenu: some View {
    let offered = catalog.loras(for: family)
    let chosen = Set(controller.parameters.loras.map(\.file))
    return Menu {
      if offered.isEmpty {
        Text("card.lora.noneAvailable")
      }
      let known = offered.filter { $0.family != nil }
      let unknown = offered.filter { $0.family == nil }
      if !known.isEmpty {
        Section {
          ForEach(known) { lora in addButton(lora, disabled: chosen.contains(lora.file)) }
        } header: {
          Text(verbatim: family ?? "")
        }
      }
      if !unknown.isEmpty {
        Section {
          ForEach(unknown) { lora in addButton(lora, disabled: chosen.contains(lora.file)) }
        } header: {
          Text("card.lora.unknownFamily")
        }
      }
    } label: {
      DSMenuLabel(String(localized: "card.lora.add"), systemImage: "plus")
    }
    .dsMenuPill()
  }

  private func addButton(_ lora: CatalogLoRA, disabled: Bool) -> some View {
    Button {
      controller.parameters.addLoRA(lora.file, weight: lora.defaultWeight ?? 1, trigger: lora.trigger)
    } label: {
      Text(verbatim: lora.name)
    }
    .disabled(disabled)
  }
}

/// One chosen LoRA: name and remove on the first line, mode and weight on the second, the
/// trigger word on the third, the reason in orange when it is not sent.
private struct LoRARow: View {
  @Binding var selection: LoRASelection
  let name: String
  let status: LoRAStatus
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: DS.controlGap) {
        Text(verbatim: name)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(status == .usable ? .primary : .secondary)
        Spacer(minLength: DS.controlGap)
        Button(action: remove) {
          Image(systemName: "minus.circle.fill")
            .foregroundStyle(DS.remove)
        }
        .buttonStyle(.plain)
        .help(String(localized: "card.lora.remove"))
        .accessibilityLabel(String(localized: "card.lora.remove"))
      }
      HStack(spacing: DS.controlGap) {
        Picker(selection: $selection.mode) {
          ForEach(LoRAMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        } label: {
          EmptyView()
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(String(localized: "card.lora.mode"))
        Spacer(minLength: DS.controlGap)
        DecimalField(
          label: String(localized: "card.lora.weight"), value: $selection.weight,
          range: LoRASelection.weightRange, step: 0.05, fractionDigits: 2)
      }
      HStack(spacing: DS.controlGap) {
        Text("card.lora.trigger")
          .foregroundStyle(.secondary)
          .lineLimit(1)
        TextField(String(localized: "card.lora.trigger"), text: $selection.trigger, prompt: Text("card.lora.trigger.placeholder"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
      }
      if let reason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    }
    .padding(.vertical, 2)
  }

  private var reason: String? {
    switch status {
    case .usable: nil
    case .otherFamily(let family): String(format: String(localized: "card.lora.otherFamily"), family)
    case .notOnServer: String(localized: "card.lora.notOnServer")
    }
  }
}

extension LoRAMode {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .all: "card.lora.mode.all"
    case .base: "card.lora.mode.base"
    case .refiner: "card.lora.mode.refiner"
    }
  }
}
