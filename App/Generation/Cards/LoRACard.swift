import HubCore
import HubKit
import SwiftUI

/// The LoRAs of the next RUN, each with weight, mode and trigger word (spec §6). The menu offers the LoRAs
/// of the chosen model's family and those of unknown family, in a popover with search and category sections; a LoRA that no longer fits
/// (other family, gone from the server) stays in the list with the reason and is not sent.
/// Trigger words stay in their own field, prefilled from Draw Things; at RUN those of the
/// LoRAs sent go in front of the prompt (`GenerationJob.promptWithTriggers`).
struct LoRACard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(ContributionStore.self) private var contributions: ContributionStore?
  @Environment(\.openWindow) private var openWindow
  @State private var isAdding = false

  private var catalog: ModelCatalog { connection.monitor.catalog }
  private var family: String? { controller.family() }

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
            offered: offered, chosen: chosenFiles,
            pick: { controller.replaceLoRA(selection.file, with: self.selection(for: $0)) },
            selection: binding(for: selection),
            name: catalog.lora(forFile: selection.file)?.name ?? selection.file,
            limits: limits(of: catalog.lora(forFile: selection.file)),
            status: catalog.status(of: selection, family: family),
            isContributed: contributions?.loraPlugins[selection.file] != nil,
            turboNote: controller.turboNote(for: selection.file),
            remove: { controller.removeLoRA(selection.file) })
        }
        HStack(spacing: DS.controlGap) {
          addButton
          manageButton
          Spacer(minLength: 0)
        }
      }
    }
  }

  /// The user's lowest and highest weight for a LoRA, when it has any (the missing side is the range's own).
  private func limits(of lora: CatalogLoRA?) -> ClosedRange<Double>? {
    guard let lora, lora.minWeight != nil || lora.maxWeight != nil else { return nil }
    let range = LoRASelection.weightRange
    let low = lora.minWeight ?? range.lowerBound
    return low...max(low, lora.maxWeight ?? range.upperBound)
  }

  /// A row's binding found by file, not by array index: a row still editing when its LoRA
  /// is removed (or replaced by "Resume parameters") then writes nowhere, instead of past
  /// the end of the list or into the LoRA that took its place.
  private func binding(for selection: LoRASelection) -> Binding<LoRASelection> {
    Binding(
      get: { controller.parameters.loras.first { $0.file == selection.file } ?? selection },
      set: { controller.parameters.updateLoRA($0) })
  }

  private var addButton: some View {
    Button {
      isAdding = true
    } label: {
      DSMenuLabel(String(localized: "card.lora.add"), systemImage: "plus")
    }
    .buttonStyle(DSPillButtonStyle())
    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
      LoRAPicker(loras: offered, chosen: chosenFiles, current: nil) { lora in
        isAdding = false
        controller.addLoRA(selection(for: lora))
      }
    }
  }

  private var offered: [CatalogLoRA] { catalog.loras(for: family) }
  private var chosenFiles: Set<String> { Set(controller.parameters.loras.map(\.file)) }

  private func selection(for lora: CatalogLoRA) -> LoRASelection {
    LoRASelection(file: lora.file, weight: lora.defaultWeight ?? 1, trigger: lora.trigger)
  }

  /// The window where the user keeps the trigger word and the default weight of every LoRA of the server.
  private var manageButton: some View {
    Button {
      openWindow(id: LoRAManagerWindow.id)
    } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: "slider.horizontal.3")
        Text("lora.manage")
      }
    }
    .buttonStyle(DSPillButtonStyle())
  }
}

/// One chosen LoRA: name and remove on the first line, mode and weight on the second, the
/// trigger word on the third, the reason in orange when it is not sent.
private struct LoRARow: View {
  /// The picker of the name: the same LoRAs as "Add LoRA", each replacing this LoRA.
  let offered: [CatalogLoRA]
  let chosen: Set<String>
  let pick: (CatalogLoRA) -> Void
  @State private var isReplacing = false
  @Binding var selection: LoRASelection
  let name: String
  let limits: ClosedRange<Double>?
  let status: LoRAStatus
  /// A plug-in added this LoRA: teal at 30%.
  let isContributed: Bool
  /// What a Turbo LoRA set (steps, guidance, shift), nil for the others.
  let turboNote: String?
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: DS.controlGap) {
        Button {
          isReplacing = true
        } label: {
          HStack(spacing: 4) {
            Text(verbatim: name)
              .lineLimit(1)
              .truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
          }
          .foregroundStyle(status == .usable ? DS.accent : DS.accent.opacity(0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isReplacing, arrowEdge: .bottom) {
          LoRAPicker(loras: offered, chosen: chosen, current: selection.file) { lora in
            isReplacing = false
            pick(lora)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .help(String(localized: "card.lora.replace"))
        .accessibilityLabel(String(localized: "card.lora.replace"))
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
          range: LoRASelection.weightRange, step: 0.05, fractionDigits: 2, limits: limits)
      }
      HStack(spacing: DS.controlGap) {
        Text("card.lora.trigger")
          .foregroundStyle(.secondary)
          .lineLimit(1)
        TextField(String(localized: "card.lora.trigger"), text: $selection.trigger, prompt: Text("card.lora.trigger.placeholder"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
      }
      if let turboNote {
        Text(turboNote)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let reason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    }
    .padding(.vertical, 2)
    .contributed(isContributed)
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
