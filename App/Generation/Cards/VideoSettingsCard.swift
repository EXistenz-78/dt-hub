import HubCore
import HubKit
import SwiftUI

/// Frames and estimated length, audio shift, strategic stochastic sampling and compression artifacts
/// for the enabled video families; hidden for any other model (video design, "Interfaccia").
struct VideoSettingsCard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    let rows = VideoCardRows(
      model: controller.selectedModel(in: connection), sampler: controller.parameters.sampler)
    if let info = rows.info {
      DSCollapsibleCard(
        String(localized: "card.video"), systemImage: "film", isExpanded: controller.cards.binding("video")
      ) {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          if controller.control.startImageURL != nil {
            Label(String(localized: "card.video.imageToVideo"), systemImage: "photo.on.rectangle")
              .font(.callout)
              .foregroundStyle(DS.accent)
          }
          framesRow(info)
          if rows.showsAudioShift {
            CardRow(label: String(localized: "card.video.audioShift")) {
              DecimalField(
                label: String(localized: "card.video.audioShift"), value: $controller.parameters.video.shiftForAudio,
                range: VideoParameters.audioShiftRange, step: 0.1)
            }
          }
          if rows.showsStochasticSampling {
            CardRow(label: String(localized: "card.video.stochastic")) {
              DecimalField(
                label: String(localized: "card.video.stochastic"),
                value: $controller.parameters.advanced.stochasticSamplingGamma,
                range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
            }
          }
          compressionRows
        }
      }
    }
  }

  /// The current count is snapped to a valid one before every step: `step` on an invalid number rounds first
  /// and could skip a valid value.
  private func framesRow(_ info: VideoFamilyInfo) -> some View {
    let frames = $controller.parameters.video.numFrames
    return CardRow(label: String(localized: "card.video.frames")) {
      HStack(spacing: DS.controlGap) {
        // The estimate sits to the left of the field (the user asked for it there).
        Text(
          String(
            format: String(localized: "card.video.frames.seconds"),
            info.seconds(forFrames: frames.wrappedValue).formatted(.number.precision(.fractionLength(1)))))
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        FramesField(label: String(localized: "card.video.frames"), value: frames, info: info)
      }
    }
  }

  @ViewBuilder private var compressionRows: some View {
    let advanced = $controller.parameters.advanced
    CardRow(label: String(localized: "card.video.compression")) {
      Picker(selection: advanced.compressionArtifacts) {
        Text("advanced.compression.none").tag(CompressionArtifacts.none)
        Text(verbatim: "H.264").tag(CompressionArtifacts.h264)
        Text(verbatim: "H.265").tag(CompressionArtifacts.h265)
        Text(verbatim: "JPEG").tag(CompressionArtifacts.jpeg)
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel(String(localized: "card.video.compression"))
    }
    if advanced.wrappedValue.compressionArtifacts != .none {
      CardRow(label: String(localized: "card.video.compressionQuality")) {
        DecimalField(
          label: String(localized: "card.video.compressionQuality"), value: advanced.compressionQuality,
          range: AdvancedParameters.qualityRange, step: 1)
      }
    }
  }
}

/// A frame count you can type or step through the valid series of the family. Typing is free; when editing
/// ends the number snaps to a valid one.
private struct FramesField: View {
  let label: String
  @Binding var value: Int
  let info: VideoFamilyInfo

  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 4) {
      TextField(label, text: $text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 64)
        .focused($focused)
        .onSubmit(finish)
        .onChange(of: focused) { if !focused { finish() } }
      Stepper(
        label,
        onIncrement: { move(1) },
        onDecrement: { move(-1) }
      )
      .labelsHidden()
    }
    .onAppear { text = String(value) }
    .onChange(of: value) { text = String(value) }
  }

  private func move(_ direction: Int) {
    // Commit what is typed first, so the step starts from it.
    let typed = NumberText.int(text, in: info.minFrames...info.maxFrames) ?? value
    value = info.step(info.snap(typed), by: direction)
    text = String(value)
  }

  private func finish() {
    let typed = NumberText.int(text, in: info.minFrames...info.maxFrames) ?? value
    value = info.snap(typed)
    text = String(value)
  }
}
