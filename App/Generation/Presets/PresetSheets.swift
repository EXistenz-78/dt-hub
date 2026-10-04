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

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var replaces: Bool { controller.presets.contains(trimmed) }
  /// A name the file system does not take: shown as soon as it is typed.
  private var invalid: Bool { !trimmed.isEmpty && !PresetStore.isValidName(trimmed) }

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
      if invalid {
        Text("preset.save.invalidName")
          .font(.caption)
          .foregroundStyle(DS.remove)
      } else if replaces {
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
        .disabled(trimmed.isEmpty || invalid)
      }
    }
    .padding(20)
    .frame(width: 380)
    .background(DSBackground())
    .tint(DS.accent)
  }

  private func save() {
    if (try? controller.savePreset(named: name, with: connection)) != nil { dismiss() }
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
      if controller.presets.names.isEmpty {
        Text("preset.none")
          .foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(spacing: DS.controlGap) {
          ForEach(controller.presets.names, id: \.self) { name in
            PresetRow(presetName: name, store: controller.presets)
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
  let presetName: String
  let store: PresetStore
  @State private var name = ""
  @State private var model = ""
  @State private var problem: String?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      VStack(alignment: .leading, spacing: 2) {
        TextField(String(localized: "preset.save.name"), text: $name)
          .textFieldStyle(.roundedBorder)
          .onSubmit(rename)
        if let problem {
          Text(verbatim: problem)
            .font(.caption)
            .foregroundStyle(DS.remove)
        } else if !model.isEmpty {
          Text(verbatim: model)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Button {
        store.delete(named: presetName)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(DS.remove)
      }
      .buttonStyle(.plain)
      .help(String(localized: "preset.delete"))
      .accessibilityLabel(String(localized: "preset.delete"))
    }
    .onAppear {
      name = presetName
      model = store.preset(named: presetName)?.model ?? ""
    }
  }

  private func rename() {
    do {
      try store.rename(presetName, to: name)
      problem = nil
    } catch {
      problem = PresetBar.text(of: error)
      name = presetName
    }
  }
}
