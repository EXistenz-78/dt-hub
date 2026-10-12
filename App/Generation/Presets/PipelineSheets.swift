import HubCore
import HubKit
import SwiftUI

/// "Create pipeline…" (`2026-10-12-pipeline-di-preset-utente-design.md` §6): the presets, ticked in the order of
/// the passes, each with its scale and strength. Saving writes the pipeline and leaves the window open.
struct CreatePipelineSheet: View {
  let controller: GenerationController
  @Environment(\.dismiss) private var dismiss
  @State private var draft = PipelineDraft()
  /// The model each preset names, read once when the window opens.
  @State private var models: [String: String] = [:]
  /// The draft as it was saved: "Saved." shows until something changes.
  @State private var saved: PipelineDraft?
  @State private var failure: String?

  private static let numberColumn: CGFloat = 64

  private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("pipeline.create.title")
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        TextField(String(localized: "preset.save.name"), text: $draft.name, prompt: Text("preset.save.name"))
          .textFieldStyle(.roundedBorder)
        nameNote
      }
      Toggle(isOn: $draft.chain) {
        HStack(spacing: 6) {
          Text("pipeline.chain")
          Text(verbatim: "(" + String(localized: "pipeline.chain.note") + ")")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.checkbox)
      list
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.close")
        }
        .buttonStyle(DSPillButtonStyle())
        .keyboardShortcut(.cancelAction)
        Button(action: save) {
          Text("preset.save.button")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canSave)
      }
    }
    .padding(20)
    .frame(width: 500)
    .background(DSBackground())
    .tint(DS.accent)
    .onAppear {
      controller.presets.refresh()
      for name in controller.presets.names { models[name] = controller.presets.preset(named: name)?.model ?? "" }
    }
  }

  /// Under the name: what happened to the last saving, or what is wrong with the name.
  @ViewBuilder private var nameNote: some View {
    if saved == draft {
      if let failure {
        Text(verbatim: failure).font(.caption).foregroundStyle(DS.remove)
      } else {
        Text("pipeline.saved").font(.caption).foregroundStyle(.secondary)
      }
    } else if !trimmedName.isEmpty && !draft.hasValidName {
      Text("pipeline.invalidName").font(.caption).foregroundStyle(DS.remove)
    } else if !trimmedName.isEmpty && controller.userPipelines.names.contains(where: { Self.same($0, trimmedName) }) {
      Text("pipeline.replaces").font(.caption).foregroundStyle(DS.remove)
    }
  }

  private var list: some View {
    VStack(spacing: 0) {
      HStack(spacing: DS.controlGap) {
        Text(verbatim: "#").frame(width: 26, alignment: .leading)
        Text("pipeline.column.preset").frame(maxWidth: .infinity, alignment: .leading)
        Text("pipeline.column.scale").frame(width: Self.numberColumn)
        Text("control.strength").frame(width: Self.numberColumn)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      Divider()
      ScrollView {
        VStack(spacing: 0) {
          row(.current, title: String(localized: "pipeline.current"), note: String(localized: "pipeline.current.note"))
          ForEach(controller.presets.names, id: \.self) { name in
            Divider()
            row(
              .preset(name), title: name,
              note: models[name].flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "pipeline.noModel"))
          }
        }
      }
      .frame(minHeight: 120, maxHeight: 340)
    }
    .background(RoundedRectangle(cornerRadius: DS.boxRadius).fill(.background.opacity(0.5)))
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(.separator))
  }

  private func row(_ row: PipelineDraft.Row, title: String, note: String) -> some View {
    let number = draft.number(of: row)
    return HStack(spacing: DS.controlGap) {
      Button {
        draft.toggle(row)
      } label: {
        tick(number)
      }
      .buttonStyle(.plain)
      .frame(width: 26, alignment: .leading)
      .accessibilityLabel(title)
      .accessibilityValue(number.map(String.init) ?? "")
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: title)
          .italic(row == .current)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(verbatim: note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(number == nil ? 0.5 : 1)
      // The first pass has the tab's size: it shows a dash.
      field(
        text: number == 1
          ? .constant("—") : Binding(get: { draft.scaleText[row] ?? "1" }, set: { draft.scaleText[row] = $0 }),
        label: String(localized: "pipeline.column.scale"), placeholder: "", unit: "×", enabled: draft.editsScale(row), valid: draft.isScaleValid(row))
      field(
        text: Binding(get: { draft.strengthText[row] ?? "" }, set: { draft.strengthText[row] = $0 }),
        label: String(localized: "control.strength"),
        placeholder: draft.editsStrength(row) ? String(localized: "pipeline.strength.auto") : "", unit: "%",
        enabled: draft.editsStrength(row), valid: draft.isStrengthValid(row))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  /// The checkbox of a row: empty, or with the number of the pass in it.
  private func tick(_ number: Int?) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(number == nil ? AnyShapeStyle(.background) : AnyShapeStyle(DS.accent))
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(number == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(DS.accent)))
      .overlay {
        if let number {
          Text(verbatim: "\(number)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.black.opacity(0.8))
        }
      }
      .frame(width: 18, height: 18)
      .contentShape(Rectangle())
  }

  /// A small number field with its unit outside; a value that is not valid has a red border.
  private func field(
    text: Binding<String>, label: String, placeholder: String, unit: String, enabled: Bool, valid: Bool
  ) -> some View {
    HStack(spacing: 3) {
      TextField(label, text: text, prompt: Text(verbatim: placeholder))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 44)
        .disabled(!enabled)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.remove, lineWidth: valid ? 0 : 1.5))
      Text(verbatim: unit)
        .foregroundStyle(.secondary)
    }
    .frame(width: Self.numberColumn)
  }

  private func save() {
    guard let pipeline = draft.pipeline else { return }
    do {
      try controller.userPipelines.save(pipeline, named: draft.name)
      failure = nil
      // A pipeline saved again under the name of the one on RUN: RUN shows the new passes.
      controller.syncActivePipeline()
    } catch {
      failure = PresetBar.text(of: error)
    }
    saved = draft
  }

  private static func same(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }
}
