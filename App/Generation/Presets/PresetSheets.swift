import HubCore
import HubKit
import SwiftUI

/// Asks for a name and saves the tab as a preset; an existing name is replaced, and the
/// sheet says so.
struct SavePresetSheet: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  private var replaces: Bool {
    controller.presets.preset(named: name.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("preset.save.title")
        .font(.headline)
      TextField(String(localized: "preset.save.name"), text: $name, prompt: Text("preset.save.name"))
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
      Text("preset.save.contents")
        .font(.caption)
        .foregroundStyle(.secondary)
      if replaces {
        Text("preset.save.replaces")
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.cancel")
        }
        .buttonStyle(DSPillButtonStyle())
        .keyboardShortcut(.cancelAction)
        Button(action: save) {
          Text("preset.save.button")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
    .background(DSBackground())
    .tint(DS.accent)
  }

  private func save() {
    if controller.savePreset(named: name, with: connection) { dismiss() }
  }
}

/// The saved presets, each renamed in place or deleted.
struct ManagePresetsSheet: View {
  let controller: GenerationController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("preset.manage.title")
        .font(.headline)
      if controller.presets.presets.isEmpty {
        Text("preset.none")
          .foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(spacing: DS.controlGap) {
          ForEach(controller.presets.presets) { preset in
            PresetRow(preset: preset, store: controller.presets)
          }
        }
      }
      .frame(minHeight: 120, maxHeight: 360)
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.done")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 440)
    .background(DSBackground())
    .tint(DS.accent)
  }
}

private struct PresetRow: View {
  let preset: Preset
  let store: PresetStore
  @State private var name = ""
  @State private var taken = false

  var body: some View {
    HStack(spacing: DS.controlGap) {
      VStack(alignment: .leading, spacing: 2) {
        TextField(String(localized: "preset.save.name"), text: $name)
          .textFieldStyle(.roundedBorder)
          .onSubmit(rename)
        if taken {
          Text("preset.rename.taken")
            .font(.caption)
            .foregroundStyle(DS.remove)
        } else if !preset.model.isEmpty {
          Text(verbatim: preset.model)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Button {
        store.delete(preset.id)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(DS.remove)
      }
      .buttonStyle(.plain)
      .help(String(localized: "preset.delete"))
      .accessibilityLabel(String(localized: "preset.delete"))
    }
    .onAppear { name = preset.name }
  }

  private func rename() {
    taken = !store.rename(preset.id, to: name)
    if taken { name = preset.name }
  }
}
