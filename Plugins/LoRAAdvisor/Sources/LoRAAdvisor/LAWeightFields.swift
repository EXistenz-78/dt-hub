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
