import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// The tab, in the look of the app: the parameters (or the prompts) on the left, the preview and the button on the right.
struct BatchPlusView: View {
  @ObservedObject var state: BatchPlusState
  let send: () -> Void
  private var italian: Bool { L.systemIsItalian }
  /// The width of the preview card: fixed, so it neither starts narrow nor grows with its content.
  private static let sideWidth: CGFloat = 320

  var body: some View {
    VStack(alignment: .leading, spacing: DS.groupGap) {
      Picker("", selection: $state.session.mode) {
        Text(L.text(.modeParameters)).tag(BatchPlusSession.Mode.parameters)
        Text(L.text(.modePrompts)).tag(BatchPlusSession.Mode.prompts)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 320)
      HStack(alignment: .top, spacing: DS.groupGap) {
        Group {
          if state.session.mode == .parameters { parametersPanel } else { promptsPanel }
        }
        .frame(maxWidth: .infinity)
        sendPanel
      }
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Parameters

  @ViewBuilder private var parametersPanel: some View {
    if let p = state.parameters {
      ScrollView {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          readOnly(L.text(.model), state.modelName ?? "—")
          readOnly(L.text(.size), size(p))
          incrementRow(.steps, L.text(.steps), p.steps.map(String.init))
          incrementRow(.guidanceScale, L.text(.guidanceRow), p.guidanceScale.map(format))
          readOnly(L.text(.cfgZero), p.cfgZeroStar.map { $0 ? L.text(.yes) : L.text(.no) } ?? "—")
          incrementRow(.cfgZeroInitSteps, L.text(.cfgZeroSteps), p.cfgZeroInitSteps.map(String.init))
          samplerRow(p)
          shiftRow(p)
          incrementRow(.seed, L.text(.seed), p.seed.map { String($0) }, suffix: p.randomSeed == true ? L.text(.random) : nil)
          readOnly(L.text(.batch), "\(p.batchSize ?? 1) × \(p.batchCount ?? 1)")
          ForEach(p.loras ?? [], id: \.file) { lora in
            incrementField(
              id: "lora:\(lora.file)", label: "\(L.text(.lora)) · \((lora.file as NSString).deletingPathExtension)",
              current: format(lora.weight), integer: false)
          }
          advanced(p)
        }
        .padding(DS.panelPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .dsPanel()
    } else {
      Text(L.text(state.contextArrived ? .needsNewApp : .noParameters))
        .foregroundStyle(.secondary)
        .padding(DS.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanel()
    }
  }

  private func size(_ p: DTHubParameters) -> String {
    guard let w = p.width, let h = p.height else { return "—" }
    return "\(w) × \(h)"
  }

  private func format(_ value: Double) -> String { String(format: "%g", value) }

  private func readOnly(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(verbatim: value).font(.system(.body, design: .monospaced))
    }
  }

  private func incrementRow(_ key: BatchPlusKey, _ label: String, _ current: String?, suffix: String? = nil) -> some View {
    incrementField(id: key.rawValue, label: label, current: current ?? "—", integer: key.isInteger, suffix: suffix)
  }

  /// The sampler of the tab and a button that opens the list of the 20: ticked in the order they are to be used, as many as
  /// there are passes. The list stays open until the user clicks outside it.
  private func samplerRow(_ p: DTHubParameters) -> some View {
    HStack(spacing: DS.controlGap) {
      Text(L.text(.sampler)).foregroundStyle(.secondary)
      Spacer(minLength: DS.controlGap)
      Text(verbatim: p.sampler.map(SamplerNames.name) ?? "—").font(.system(.body, design: .monospaced))
      SamplerPicker(session: $state.session)
    }
  }

  private func shiftRow(_ p: DTHubParameters) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      incrementField(
        id: BatchPlusKey.shift.rawValue, label: L.text(.shift), current: p.shift.map(format) ?? "—", integer: false,
        suffix: state.shiftIsAuto ? L.text(.auto) : nil, disabled: state.shiftIsAuto)
      if state.shiftIsAuto {
        Text(L.text(.shiftAutoNote)).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func incrementField(
    id: String, label: String, current: String, integer: Bool, suffix: String? = nil, disabled: Bool = false
  ) -> some View {
    let text = Binding(
      get: { state.session.increments[id] ?? "" }, set: { state.session.increments[id] = $0 })
    let invalid = state.resolved.invalid.contains(id)
    return HStack(spacing: DS.controlGap) {
      Text(label).foregroundStyle(.secondary).lineLimit(1)
      Spacer(minLength: DS.controlGap)
      Text(verbatim: current + (suffix.map { " (\($0))" } ?? "")).font(.system(.body, design: .monospaced))
      TextField(L.text(.increment), text: text)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 88)
        .disabled(disabled)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(invalid ? Color.red : Color.clear, lineWidth: 1.5))
    }
  }

  @ViewBuilder private func advanced(_ p: DTHubParameters) -> some View {
    let values = (p.advanced ?? [:]).keys.sorted()
    if !values.isEmpty {
      DisclosureGroup(L.text(.advanced)) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(values, id: \.self) { key in
            readOnly(key, describe(p.advanced?[key]))
          }
        }
        .padding(.top, 4)
      }
    }
  }

  private func describe(_ value: DTHubValue?) -> String {
    switch value {
    case .bool(let flag)?: flag ? L.text(.yes) : L.text(.no)
    case .number(let number)?: format(number)
    case .string(let text)?: text.isEmpty ? "—" : text
    default: "…"
    }
  }

  // MARK: Prompts

  private var promptsPanel: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      TextEditor(text: $state.session.promptText)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
        .frame(minHeight: 200)
      Text(L.text(.promptsHint)).font(.caption).foregroundStyle(.secondary)
      Text(L.format(.promptsCount, state.promptItems.count)).font(.caption).foregroundStyle(.secondary)
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .dsPanel()
  }

  // MARK: Preview and send

  private var sendPanel: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: L.text(.preview), prominent: true)
      if state.session.mode == .parameters {
        Stepper(
          value: $state.session.count, in: BatchPlusSession.passRange
        ) {
          Text("\(L.text(.passes)): \(state.session.count)")
        }
        if state.session.count >= BatchPlusSession.warnFrom {
          Text(L.format(.passesWarning, state.session.count)).font(.caption).foregroundStyle(DS.remove)
        }
      }
      Toggle(L.text(.fixedSeed), isOn: $state.session.fixedSeed).toggleStyle(DSCheckboxToggleStyle())
      previewList
      HStack(spacing: DS.controlGap) {
        Button(action: send) {
          if state.isSending {
            ProgressView().controlSize(.small)
          } else {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "square.stack.3d.up")
              Text(L.text(.send))
            }
          }
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(state.isSending || !state.active || state.blocker() != nil)
      }
      if let blocker = state.blocker() {
        Text(blocker).font(.caption).foregroundStyle(.secondary)
      }
      if !state.status.isEmpty {
        Text(state.status).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(DS.panelPadding)
    // The card is always as wide as its column, whatever the preview holds.
    .frame(width: Self.sideWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .dsPanel()
  }

  @ViewBuilder private var previewList: some View {
    switch state.session.mode {
    case .parameters:
      if let base = state.base, state.blocker() == nil {
        let batch = state.resolved.batch
        let columns = BatchPlusBuilder.varying(batch, base: base)
        let rows = BatchPlusBuilder.preview(batch, from: base)
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            Text(
              verbatim: "\(index + 1)  "
                + columns.map { "\(BatchPlusBuilder.columnLabel($0, italian: italian)) \(display($0, row[$0]))" }
                .joined(separator: " · ")
            )
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
          }
          Text(L.text(.previewNote)).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
      }
    case .prompts:
      VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(state.promptItems.enumerated()), id: \.offset) { index, item in
          Text(verbatim: "\(index + 1)  \(item.prefix(80))").font(.caption).lineLimit(1)
        }
      }
    }
  }

  private func shortNumber(_ value: Double) -> String { String(format: "%g", value) }

  private func display(_ id: String, _ value: Double?) -> String {
    guard let value else { return "—" }
    return id == BatchPlusBuilder.samplerID ? SamplerNames.name(Int(value)) : shortNumber(value)
  }
}

/// The button of the sampler row and the list it opens (a popover, so it does not close after each tick).
private struct SamplerPicker: View {
  @Binding var session: BatchPlusSession
  @State private var isOpen = false

  private var chosen: [Int] { Array(session.samplers.prefix(session.count)) }

  var body: some View {
    Button {
      isOpen.toggle()
    } label: {
      HStack(spacing: 4) {
        Text(chosen.isEmpty ? L.text(.samplerVary) : "\(chosen.count)/\(session.count)")
        Image(systemName: "chevron.down").font(.caption2)
      }
      .frame(width: 72)
    }
    .buttonStyle(DSPillButtonStyle())
    .popover(isPresented: $isOpen, arrowEdge: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(SamplerNames.names.indices, id: \.self) { number in row(number) }
        }
        .padding(8)
      }
      .frame(width: 250, height: 380)
    }
  }

  private func row(_ number: Int) -> some View {
    let position = chosen.firstIndex(of: number)
    let full = chosen.count >= session.count
    return Button {
      if position != nil {
        session.samplers.removeAll { $0 == number }
      } else {
        session.samplers.append(number)
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: position != nil ? "checkmark.square.fill" : "square")
          .foregroundStyle(position != nil ? DS.accent : Color.secondary)
        Text(verbatim: SamplerNames.name(number))
        Spacer()
        if let position { Text("\(position + 1)").font(.caption).foregroundStyle(.secondary) }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(position == nil && full)
    .opacity(position == nil && full ? 0.4 : 1)
  }
}
