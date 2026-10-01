import AppKit
import HubCore
import HubKit
import SwiftUI

/// The whole Draw Things configuration as JSON (spec §6, level 3): the "Copy Configuration"
/// format, every setting reachable. Paste a complete or partial text and apply it: only the
/// keys in the text change.
struct JSONEditorSheet: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var error: String?
  @State private var unknown: [String] = []
  @State private var applyError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("json.title")
        .font(.headline)
      Text("json.explanation")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: $text)
        .font(.system(.callout, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
        .frame(minWidth: 520, minHeight: 320)
        .background(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .accessibilityLabel(String(localized: "json.title"))
      status
      HStack {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        } label: {
          Text("json.copy")
        }
        .buttonStyle(DSPillButtonStyle())
        Button {
          text = controller.exportJSON(in: connection)
        } label: {
          Text("json.reload")
        }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "json.reload.help"))
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.cancel")
        }
        .buttonStyle(DSPillButtonStyle())
        .keyboardShortcut(.cancelAction)
        Button(action: apply) {
          Text("json.apply")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(error != nil)
      }
    }
    .padding(20)
    .background(DSBackground())
    .tint(DS.accent)
    .onAppear { text = controller.exportJSON(in: connection) }
    .onChange(of: text) { check() }
  }

  /// What is wrong with the text, or what will be ignored.
  @ViewBuilder private var status: some View {
    if let error {
      Label {
        Text(String(format: String(localized: "json.invalid"), error))
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
      }
      .font(.caption)
      .foregroundStyle(DS.remove)
      .lineLimit(3)
    } else if let applyError {
      Text(String(format: String(localized: "json.invalid"), applyError))
        .font(.caption)
        .foregroundStyle(DS.remove)
    } else if !unknown.isEmpty {
      Text(String(format: String(localized: "json.unknownKeys"), unknown.joined(separator: ", ")))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func check() {
    applyError = nil
    error = controller.codec.validate(text, for: controller.configurationState(in: connection))
    unknown = error == nil ? controller.codec.unknownKeys(in: text) : []
  }

  private func apply() {
    do {
      try controller.applyJSON(text, with: connection)
      dismiss()
    } catch {
      applyError = error.message
    }
  }
}
