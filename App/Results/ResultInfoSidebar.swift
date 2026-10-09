import DTHubDesign
import HubCore
import SwiftUI

/// The information saved with the chosen image: prompt, settings, LoRAs, timing, file. Read-only;
/// the text can be selected and copied with the mouse.
struct ResultInfoSidebar: View {
  let image: GeneratedImage?
  let selectionCount: Int

  static let width: CGFloat = 300

  var body: some View {
    Group {
      if let image {
        let info = ResultInfo(image)
        ScrollView {
          VStack(alignment: .leading, spacing: DS.controlGap) {
            if selectionCount > 1 {
              Text(String(format: String(localized: "results.info.multi"), selectionCount))
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(info.sections.enumerated()), id: \.offset) { _, section in
              DSGroupHeader(title: Self.title(of: section.kind))
              ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
              }
            }
          }
          .padding(.vertical, 2)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        ContentUnavailableView("results.info.none", systemImage: "info.circle")
      }
    }
    .frame(width: Self.width)
  }

  private func rowView(_ row: ResultInfo.Row) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      label(row.field)
        .font(.caption).foregroundStyle(.secondary)
      Text(verbatim: row.value)
        .font(Self.isLongText(row.field) ? .body : .system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private static func isLongText(_ field: ResultInfo.Field) -> Bool {
    switch field {
    case .prompt, .sentPrompt, .negativePrompt: true
    default: false
    }
  }

  @ViewBuilder private func label(_ field: ResultInfo.Field) -> some View {
    switch field {
    case .advanced(let key), .extra(let key): Text(verbatim: key)
    case .prompt: Text("results.info.field.prompt")
    case .sentPrompt: Text("results.info.field.sentPrompt")
    case .negativePrompt: Text("results.info.field.negativePrompt")
    case .model: Text("results.info.field.model")
    case .size: Text("results.info.field.size")
    case .seed: Text("results.info.field.seed")
    case .steps: Text("results.info.field.steps")
    case .guidance: Text("results.info.field.guidance")
    case .sampler: Text("results.info.field.sampler")
    case .shift: Text("results.info.field.shift")
    case .cfgZero: Text("results.info.field.cfgZero")
    case .lora: Text("results.info.field.lora")
    case .imageStrength: Text("results.info.field.imageStrength")
    case .moodboard: Text("results.info.field.moodboard")
    case .mask: Text("results.info.field.mask")
    case .time: Text("results.info.field.time")
    case .date: Text("results.info.field.date")
    case .fileName: Text("results.info.field.fileName")
    case .folder: Text("results.info.field.folder")
    case .notSaved: Text("results.info.field.notSaved")
    }
  }

  private static func title(of kind: ResultInfo.Kind) -> String {
    switch kind {
    case .prompt: String(localized: "results.info.section.prompt")
    case .model: String(localized: "results.info.section.model")
    case .loras: String(localized: "results.info.section.loras")
    case .input: String(localized: "results.info.section.input")
    case .advanced: String(localized: "results.info.section.advanced")
    case .extra: String(localized: "results.info.section.extra")
    case .file: String(localized: "results.info.section.file")
    }
  }
}
