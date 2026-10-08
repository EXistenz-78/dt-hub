import HubCore
import HubKit
import SwiftUI

enum LoRAManagerWindow {
  static let id = "lora-manager"
}

/// «Manage LoRAs»: the LoRAs of the server in lists by model family, each with the trigger word and the default weight
/// the user wants (spec: the server's values are inherited and only the changes are kept, in `loras.json`). Compact:
/// the name on top, the trigger word and a small weight field below.
struct LoRAManagerView: View {
  let connection: DrawThingsConnection
  let controller: GenerationController
  @State private var query = ""
  /// The families that are open: "" is the group of unknown family. The chosen model's family opens at first.
  @State private var open: Set<String> = []
  @State private var didOpenFirst = false

  private var monitor: ConnectionMonitor { connection.monitor }

  private struct Group: Identifiable {
    let key: String
    let family: String?
    let loras: [CatalogLoRA]
    var id: String { key }
  }

  private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

  /// What matches the search (name or file), by family: families in alphabetical order, the unknown one last.
  private var groups: [Group] {
    let text = query.trimmingCharacters(in: .whitespaces)
    let matching = monitor.serverCatalog.loras.filter {
      text.isEmpty || $0.name.localizedStandardContains(text) || $0.file.localizedStandardContains(text)
    }
    let grouped = Dictionary(grouping: matching, by: \.family)
    let families = grouped.keys.sorted { lhs, rhs in
      switch (lhs, rhs) {
      case (nil, _): false
      case (_, nil): true
      case let (l?, r?): l.localizedStandardCompare(r) == .orderedAscending
      }
    }
    return families.map { family in
      Group(
        key: family ?? "", family: family,
        loras: grouped[family, default: []].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      TextField(String(localized: "lora.manager.search"), text: $query, prompt: Text("lora.manager.search"))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
      content
      Text("lora.manager.note")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 680)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
    .onAppear {
      guard !didOpenFirst else { return }
      didOpenFirst = true
      open.insert(controller.family(in: connection) ?? "")
    }
  }

  @ViewBuilder private var content: some View {
    let groups = groups
    if monitor.serverCatalog.loras.isEmpty {
      Text("lora.manager.empty").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if groups.isEmpty {
      Text("lora.manager.noMatch").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(groups) { group in
            let isOpen = isSearching || open.contains(group.key)
            header(group, isOpen: isOpen)
            if isOpen {
              ForEach(group.loras) { lora in
                LoRAManagerRow(lora: lora, monitor: monitor)
              }
            }
          }
        }
        .padding(.trailing, 4)
      }
    }
  }

  private func header(_ group: Group, isOpen: Bool) -> some View {
    Button {
      if isSearching { return }
      if open.contains(group.key) { open.remove(group.key) } else { open.insert(group.key) }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
          .font(.caption.weight(.semibold))
          .frame(width: 12)
        if let family = group.family {
          Text(verbatim: family).font(.callout.weight(.semibold))
        } else {
          Text("card.lora.unknownFamily").font(.callout.weight(.semibold))
        }
        Text(verbatim: "\(group.loras.count)").font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.top, 6)
  }
}

/// One LoRA: its name (and, when the user changed something, a button to go back to the server's values) above, the
/// trigger word and the weight below. A field is written when it is left or confirmed.
private struct LoRAManagerRow: View {
  let lora: CatalogLoRA
  let monitor: ConnectionMonitor
  @State private var trigger = ""
  @State private var weight = ""
  @FocusState private var focus: Field?

  private enum Field { case trigger, weight }

  private var entry: LoRAOverride? { monitor.loraOverrides.entries[lora.file] }
  private var effectiveTrigger: String { entry?.trigger ?? lora.trigger }
  private var effectiveWeight: Double { entry?.weight ?? LoRAOverrides.defaultWeight }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(verbatim: lora.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
        if monitor.loraOverrides.isChanged(lora) {
          Button {
            monitor.loraOverrides.reset(lora)
          } label: {
            Image(systemName: "arrow.uturn.backward.circle")
              .foregroundStyle(DS.accent)
          }
          .buttonStyle(.plain)
          .help(String(localized: "lora.manager.reset"))
          .accessibilityLabel(String(localized: "lora.manager.reset"))
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: DS.controlGap) {
        TextField(String(localized: "card.lora.trigger"), text: $trigger, prompt: Text("card.lora.trigger.placeholder"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .focused($focus, equals: .trigger)
          .onSubmit(commitTrigger)
        TextField(String(localized: "card.lora.weight"), text: $weight)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .monospacedDigit()
          .frame(width: 54)
          .focused($focus, equals: .weight)
          .onSubmit(commitWeight)
      }
    }
    .padding(.vertical, 3)
    .onAppear(perform: sync)
    .onChange(of: focus) { old, _ in
      if old == .trigger { commitTrigger() }
      if old == .weight { commitWeight() }
    }
    .onChange(of: entry) { if focus == nil { sync() } }
  }

  private func commitTrigger() {
    monitor.loraOverrides.setTrigger(trigger, for: lora)
    trigger = effectiveTrigger
  }

  /// An empty or unreadable weight is the default, one.
  private func commitWeight() {
    monitor.loraOverrides.setWeight(NumberText.decimal(weight, in: LoRAOverrides.weightRange), for: lora)
    weight = Self.format(effectiveWeight)
  }

  private func sync() {
    trigger = effectiveTrigger
    weight = Self.format(effectiveWeight)
  }

  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }
}
