import HubCore
import HubKit
import SwiftUI

/// "Sent with RUN": one chip per input that will go (spec: tab Control §3), each with a ✕, a
/// "Clear all" and the warnings worth a look before pressing RUN.
struct ControlStrip: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  private var control: ControlStore { generation.control }

  var body: some View {
    let warnings = control.warnings(
      canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height,
      usesMoodboard: FamilyTraits.of(generation.family(in: connection)).usesMoodboard)
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        DSGroupHeader(title: String(localized: "control.strip.title"))
        if let image = control.inputs.image {
          chip(
            systemImage: "photo", title: String(localized: "control.strip.image"),
            detail: "\(image.pixelWidth)×\(image.pixelHeight)",
            remove: { control.removeImage() })
        }
        if control.inputs.paint != nil {
          chip(
            systemImage: "paintbrush", title: String(localized: "control.strip.paint"), detail: "",
            remove: { control.clearPaint() })
        }
        if let mask = control.inputs.mask {
          chip(
            systemImage: "paintbrush.pointed", title: String(localized: "control.strip.mask"),
            detail: "\(max(1, Int((mask.coverage * 100).rounded())))%", remove: { control.clearMask() })
        }
        if !control.inputs.moodboard.isEmpty {
          chip(
            systemImage: "square.grid.2x2", title: String(localized: "control.strip.moodboard"),
            detail: "\(control.inputs.moodboard.filter(\.isOn).count)",
            remove: { control.clearMoodboard() })
        }
        if control.inputs.image == nil, control.inputs.moodboard.isEmpty {
          Text("control.strip.empty").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if control.inputs != ControlInputs() {
          Button("control.strip.clear") { control.clear() }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.remove)
        }
      }
      ForEach(warnings, id: \.self) { warning in
        Label(ControlText.warning(warning), systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .dsPanel()
  }

  private func chip(systemImage: String, title: String, detail: String, remove: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      Text(title).font(.caption.weight(.semibold))
      Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
      Button(action: remove) {
        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "control.strip.remove"))
      .help(String(localized: "control.strip.remove"))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
  }
}
