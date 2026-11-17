import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// Min, Base and Max of a LoRA: the lowest weight, the one it starts with, and the highest. A field written when it is
/// left or confirmed; an empty Min or Max is no limit, an empty Base is 1.
struct LAWeightFields: View {
  @ObservedObject var state: LAState
  let lora: DTHubCatalogLoRA
  @State private var low = ""
  @State private var base = ""
  @State private var high = ""
  @FocusState private var focus: Field?

  private enum Field { case low, base, high }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: DS.controlGap) {
        field(.weightMin, text: $low, focus: .low)
        field(.weightBase, text: $base, focus: .base)
        field(.weightMax, text: $high, focus: .high)
      }
      if let message = state.weightsMessage {
        Text(verbatim: message).font(.caption).foregroundStyle(DS.remove)
      }
    }
    .onAppear(perform: sync)
    // Another LoRA, or new values from the app, while no field is being written.
    .onChange(of: lora.file) { sync() }
    .onChange(of: LAWeights.values(of: lora)) { if focus == nil { sync() } }
    .onChange(of: focus) { old, _ in if old != nil { commit() } }
  }

  private func field(_ key: L.Key, text: Binding<String>, focus: Field) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: state.text(key)).font(.caption).foregroundStyle(.secondary)
      TextField(state.text(key), text: text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .focused($focus, equals: focus)
        .onSubmit(commit)
    }
  }

  private func sync() {
    let values = LAWeights.values(of: lora)
    low = LAWeights.format(values.min)
    base = LAWeights.format(values.base)
    high = LAWeights.format(values.max)
  }

  private func commit() {
    let file = lora.file
    let (min, base, max) = (LAWeights.parse(low), LAWeights.parse(base), LAWeights.parse(high))
    Task {
      await state.setWeights(min: min, base: base, max: max, for: file)
      // Never while another field is being written: the answer would put the old text back over what is typed.
      if focus == nil { sync() }
    }
  }
}

/// Category, trigger and (for a Turbo LoRA) steps, guidance and shift of the LoRA that is open. Every field is written when
/// it is left or confirmed; an empty one is "not indicated". All of it is disabled when the app cannot save it.
struct LASettingsFields: View {
  @ObservedObject var state: LAState
  let lora: DTHubCatalogLoRA
  @State private var trigger = ""
  @State private var steps = ""
  @State private var guidance = ""
  @State private var shift = ""
  @FocusState private var focus: Field?

  private enum Field { case trigger, steps, guidance, shift }

  private var category: LACategory? { state.category(of: lora.file) }
  private var proposal: String? {
    state.triggerProposals.first { $0.lora.file == lora.file }?.proposal
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: DS.controlGap) {
        Text(verbatim: state.text(.category)).font(.caption).foregroundStyle(.secondary)
        Menu(category.map { state.name(of: $0) } ?? state.text(.categoryNone)) {
          Button(state.text(.categoryNone)) { choose(nil) }
          ForEach(LACategory.allCases, id: \.self) { item in
            Button(state.name(of: item)) { choose(item) }
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(state.text(.category))
        Spacer(minLength: 0)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: state.text(.triggerField)).font(.caption).foregroundStyle(.secondary)
        TextField(state.text(.triggerField), text: $trigger)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .focused($focus, equals: .trigger)
          .onSubmit(commitTrigger)
        if let proposal {
          HStack(spacing: DS.controlGap) {
            Text(verbatim: L.text(.foundTrigger, proposal, italian: state.italian))
              .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            Button(state.text(.apply)) { Task { await state.applyProposal(for: lora.file) } }
              .buttonStyle(DSPillButtonStyle()).controlSize(.small)
            Button(state.text(.notThisTrigger)) { state.dismissProposal(for: lora.file) }
              .buttonStyle(DSPillButtonStyle()).controlSize(.small)
          }
        }
      }
      if category == .turbo {
        HStack(spacing: DS.controlGap) {
          field(.steps, text: $steps, focus: .steps)
          field(.guidance, text: $guidance, focus: .guidance)
          field(.shift, text: $shift, focus: .shift)
        }
      }
      if !state.canSaveSettings {
        Text(verbatim: state.text(.settingsNeedNewApp)).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let message = state.settingsMessage {
        Text(verbatim: message).font(.caption).foregroundStyle(DS.remove).fixedSize(horizontal: false, vertical: true)
      }
    }
    .disabled(!state.canSaveSettings)
    .onAppear(perform: sync)
    .onChange(of: lora.file) { sync() }
    .onChange(of: lora.trigger) { if focus != .trigger { trigger = lora.trigger } }
    .onChange(of: [lora.steps.map(Double.init), lora.guidance, lora.shift]) { if focus == nil || focus == .trigger { syncTurbo() } }
    .onChange(of: focus) { old, _ in
      switch old {
      case .trigger: commitTrigger()
      case .steps, .guidance, .shift: commitTurbo()
      case nil: break
      }
    }
  }

  private func field(_ key: L.Key, text: Binding<String>, focus: Field) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: state.text(key)).font(.caption).foregroundStyle(.secondary)
      TextField(state.text(key), text: text)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .focused($focus, equals: focus)
        .onSubmit(commitTurbo)
    }
  }

  private func sync() {
    trigger = lora.trigger
    syncTurbo()
  }

  private func syncTurbo() {
    steps = lora.steps.map(String.init) ?? ""
    guidance = LAWeights.format(lora.guidance)
    shift = LAWeights.format(lora.shift)
  }

  private func choose(_ category: LACategory?) {
    let file = lora.file
    Task { await state.setCategory(category, for: file) }
  }

  private func commitTrigger() {
    let (file, typed) = (lora.file, trigger)
    Task {
      await state.setTrigger(typed, for: file)
      if focus != .trigger { trigger = state.catalog.first { $0.file == file }?.trigger ?? typed }
    }
  }

  private func commitTurbo() {
    let file = lora.file
    let stepsValue = LAWeights.parse(steps).map { Int($0.rounded()) }
    let (guidanceValue, shiftValue) = (LAWeights.parse(guidance), LAWeights.parse(shift))
    Task {
      await state.setTurbo(steps: stepsValue, guidance: guidanceValue, shift: shiftValue, for: file)
      if focus == nil { syncTurbo() }
    }
  }
}
