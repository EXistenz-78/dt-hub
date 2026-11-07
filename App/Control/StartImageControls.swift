import HubCore
import HubKit
import SwiftUI

/// What goes with the start image besides the picture itself (spec: tab Control): the strength, "adapt the
/// dimensions" and "generate prompt". Without an image there is only the button to choose one. It sits under the
/// Canvas, and alone in the Control tab while the Canvas is in its own window.
struct StartImageControls<Trailing: View>: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  /// Reports what went wrong with an import, or that the dimensions were adapted.
  let report: (ControlMessage) -> Void
  /// Shown beside the buttons, filling the rest of the row (the canvas puts what it says about the picture here).
  let trailing: Trailing

  init(
    generation: GenerationController, connection: DrawThingsConnection, report: @escaping (ControlMessage) -> Void,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.generation = generation
    self.connection = connection
    self.report = report
    self.trailing = trailing()
  }

  private var control: ControlStore { generation.control }

  var body: some View {
    if control.inputs.image != nil {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        strengthRow
        actions
        PromptAssistError(assistant: generation.assistant, hiding: .emptyPrompt)
      }
    } else {
      Button("control.image.choose") {
        Task { if let message = await ControlImport.choose(into: control) { report(.error(message)) } }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .frame(maxWidth: .infinity)
    }
  }

  private var actions: some View {
    HStack(spacing: DS.controlGap) {
      Button("control.image.adapt") {
        if let previous = generation.adaptDimensionsToImage() { report(.adapted(previous)) }
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "control.image.adapt.help"))
      Button {
        Task { await generation.promptFromImage(in: connection) }
      } label: {
        Label("control.image.describe", systemImage: "text.viewfinder")
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "control.image.describe.help"))
      .disabled(generation.assistant.working != nil)
      if generation.assistant.working == .describe { ProgressView().controlSize(.small) }
      PromptAssistUndo(controller: generation)
      trailing
    }
  }

  private var strengthRow: some View {
    let edit = generation.isEditModel(in: connection)
    let margins = control.hasMargins(canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)
    let value = control.inputs.effectiveStrength(editModel: edit, hasMargins: margins)
    return VStack(alignment: .leading, spacing: 4) {
      CardRow(label: String(localized: "control.strength")) {
        Slider(
          value: Binding(get: { value }, set: { control.setStrength($0) }), in: 0...1, step: 0.01
        )
        .frame(minWidth: 120)
      } control: {
        IntField(
          label: String(localized: "control.strength"),
          value: Binding(get: { Int((value * 100).rounded()) }, set: { control.setStrength(Double($0) / 100) }),
          range: 0...100, step: 5, commit: { $0 })
      }
      HStack(spacing: DS.controlGap) {
        if edit {
          Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
        } else if control.inputs.mask != nil || margins, control.inputs.strength == nil {
          Text("control.strength.mask").font(.caption).foregroundStyle(.secondary)
        }
        if control.inputs.strength != nil {
          Button("control.strength.auto") { control.setStrength(nil) }
            .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
        }
      }
    }
  }
}

extension StartImageControls where Trailing == EmptyView {
  init(generation: GenerationController, connection: DrawThingsConnection, report: @escaping (ControlMessage) -> Void) {
    self.init(generation: generation, connection: connection, report: report) { EmptyView() }
  }
}

/// A line of the Control tab's message bar.
enum ControlMessage: Equatable {
  case error(String)
  /// The dimensions were adapted; the previous ones can be put back.
  case adapted(Size)
}
